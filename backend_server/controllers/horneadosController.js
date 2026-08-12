const { sql, getPool } = require('../config/db');
const { registrarAuditoria } = require('../utils/auditLog');

const TIPOS_ADEREZO = ['CRIOLLO', 'ORIENTAL'];

/**
 * Campos de texto libre que "aprenden" — cada valor nuevo que un vendedor
 * escribe (ej. un tipo de carne) queda disponible como sugerencia para la
 * próxima vez, por tienda. Ver [guardarSugerenciaSiEsNueva].
 */
async function listarSugerencias(req, res, next) {
  try {
    const campo = String(req.query.campo || '').toUpperCase();
    const texto = String(req.query.q || '').trim();
    if (!campo) {
      return res.status(400).json({ mensaje: 'Falta el parámetro campo.' });
    }

    const pool = await getPool();
    const tienda = await obtenerTiendaHorneados(pool);
    if (!tienda) {
      return res.status(500).json({ mensaje: 'La tienda Horneados no está configurada.' });
    }

    const request = pool
      .request()
      .input('IdTienda', sql.Int, tienda.IdTienda)
      .input('Campo', sql.VarChar(50), campo);

    // Sin texto: se listan las sugerencias más usadas recientemente (para
    // mostrar algo de entrada, antes de que el vendedor empiece a tipear).
    // Con texto: solo las que empiezan con lo ya escrito (autocompletar).
    const resultado = texto
      ? await request
          .input('Prefijo', sql.VarChar(100), `${texto}%`)
          .query(`
            SELECT Valor FROM SugerenciasCampo
            WHERE IdTienda = @IdTienda AND Campo = @Campo AND Valor LIKE @Prefijo
            ORDER BY Valor ASC
            LIMIT 20
          `)
      : await request.query(`
          SELECT Valor FROM SugerenciasCampo
          WHERE IdTienda = @IdTienda AND Campo = @Campo
          ORDER BY FechaCreacion DESC
          LIMIT 20
        `);

    return res.status(200).json({ sugerencias: resultado.recordset.map((f) => f.Valor) });
  } catch (err) {
    return next(err);
  }
}

/** INSERT IGNORE: si (IdTienda, Campo, Valor) ya existe (UNIQUE), no hace
 * nada — así un valor reusado no se duplica ni cambia su antigüedad. */
async function guardarSugerenciaSiEsNueva(request, { idTienda, campo, valor }) {
  await request
    .input(`Sug_${campo}_IdTienda`, sql.Int, idTienda)
    .input(`Sug_${campo}_Campo`, sql.VarChar(50), campo)
    .input(`Sug_${campo}_Valor`, sql.VarChar(100), valor)
    .query(`
      INSERT IGNORE INTO SugerenciasCampo (IdTienda, Campo, Valor)
      VALUES (@Sug_${campo}_IdTienda, @Sug_${campo}_Campo, @Sug_${campo}_Valor)
    `);
}

async function obtenerTiendaHorneados(pool) {
  const resultado = await pool.request().query(`
    SELECT t.IdTienda, p.IdProducto
    FROM Tiendas t
    INNER JOIN Categorias c ON c.IdTienda = t.IdTienda AND c.Nombre = 'Horneados'
    INNER JOIN Productos p ON p.IdCategoria = c.IdCategoria AND p.Estado = 1
    WHERE t.Slug = 'horneados'
    ORDER BY p.IdProducto
    LIMIT 1
  `);
  return resultado.recordset[0] ?? null;
}

/**
 * Registra un pedido de Horneados — mismo espíritu que `crearPedido` en
 * pedidosController.js (personal registra a nombre de un cliente ya
 * existente, precio libre, nace PENDIENTE), pero con los campos propios de
 * este rubro (carne, presentación, aderezo opcional) guardados aparte en
 * `PedidosHorneadosDetalle` — `Pedidos` no tiene dónde ponerlos.
 */
async function crearPedidoHorneado(req, res, next) {
  const {
    idCliente,
    carne,
    presentacion,
    cantidad,
    aplicaAderezo,
    tipoAderezo,
    precioHorneado,
    precioAderezo,
    fechaEntrega,
    notas,
  } = req.body;
  const { idPersona, idUsuario } = req.usuario;

  const pool = await getPool();
  const transaction = new sql.Transaction(pool);

  try {
    await transaction.begin();

    const trabajadorResult = await new sql.Request(transaction)
      .input('IdPersona', sql.Int, idPersona)
      .query('SELECT IdTrabajador FROM Trabajadores WHERE IdPersona = @IdPersona AND Estado = 1');
    const idTrabajador = trabajadorResult.recordset[0]?.IdTrabajador ?? null;

    const clienteResult = await new sql.Request(transaction)
      .input('IdCliente', sql.Int, idCliente)
      .query(`
        SELECT c.DescripcionNegocio, p.DNI, p.Nombres, p.ApellidoPaterno, p.ApellidoMaterno
        FROM Clientes c
        INNER JOIN Personas p ON p.IdPersona = c.IdPersona
        WHERE c.IdCliente = @IdCliente AND c.Estado = 1
      `);
    if (clienteResult.recordset.length === 0) {
      await transaction.rollback();
      return res.status(404).json({ mensaje: 'Cliente no encontrado' });
    }
    const cliente = clienteResult.recordset[0];

    const tiendaResult = await new sql.Request(transaction).query(`
      SELECT t.IdTienda, p.IdProducto
      FROM Tiendas t
      INNER JOIN Categorias c ON c.IdTienda = t.IdTienda AND c.Nombre = 'Horneados'
      INNER JOIN Productos p ON p.IdCategoria = c.IdCategoria AND p.Estado = 1
      WHERE t.Slug = 'horneados'
      ORDER BY p.IdProducto
      LIMIT 1
    `);
    if (tiendaResult.recordset.length === 0) {
      await transaction.rollback();
      return res.status(500).json({ mensaje: 'La tienda Horneados no está configurada.' });
    }
    const { IdTienda: idTienda, IdProducto: idProducto } = tiendaResult.recordset[0];

    const aplicaAderezoFinal = aplicaAderezo === true;
    const precioHorneadoFinal = Number(Number(precioHorneado).toFixed(2));
    const precioAderezoFinal = aplicaAderezoFinal ? Number(Number(precioAderezo).toFixed(2)) : null;
    const precioUnitarioFinal = Number(
      (precioHorneadoFinal + (precioAderezoFinal ?? 0)).toFixed(2),
    );
    const total = Number((precioUnitarioFinal * cantidad).toFixed(2));
    const fechaEntregaFinal = fechaEntrega ? new Date(fechaEntrega) : null;

    const insertPedido = await new sql.Request(transaction)
      .input('IdCliente', sql.Int, idCliente)
      .input('IdTienda', sql.Int, idTienda)
      .input('IdProducto', sql.Int, idProducto)
      .input('IdTrabajador', sql.Int, idTrabajador)
      .input('IdUsuarioRegistro', sql.Int, idUsuario)
      .input('TipoPedido', sql.VarChar(20), 'UNIDADES')
      .input('Cantidad', sql.Int, cantidad)
      .input('PrecioUnitario', sql.Decimal(10, 2), precioUnitarioFinal)
      .input('Total', sql.Decimal(10, 2), total)
      .input('FechaEntrega', sql.DateTime2, fechaEntregaFinal)
      .input('Notas', sql.NVarChar(300), notas ? notas.trim().toUpperCase() : null)
      .query(`
        INSERT INTO Pedidos (IdCliente, IdTienda, IdProducto, IdTrabajador, IdUsuarioRegistro, TipoPedido, Cantidad, PrecioUnitario, Total, FechaEntrega, Notas, Estado)
        OUTPUT INSERTED.IdPedido, INSERTED.FechaCreacion
        VALUES (@IdCliente, @IdTienda, @IdProducto, @IdTrabajador, @IdUsuarioRegistro, @TipoPedido, @Cantidad, @PrecioUnitario, @Total, @FechaEntrega, @Notas, 'PENDIENTE')
      `);
    const { IdPedido: idPedido, FechaCreacion: fechaCreacion } = insertPedido.recordset[0];

    const carneNormalizada = String(carne).trim().toUpperCase();
    const presentacionNormalizada = String(presentacion).trim().toUpperCase();

    await new sql.Request(transaction)
      .input('IdPedido', sql.Int, idPedido)
      .input('Carne', sql.VarChar(100), carneNormalizada)
      .input('Presentacion', sql.VarChar(100), presentacionNormalizada)
      .input('AplicaAderezo', sql.Bit, aplicaAderezoFinal)
      .input('TipoAderezo', sql.VarChar(20), aplicaAderezoFinal ? tipoAderezo : null)
      .input('PrecioAderezo', sql.Decimal(10, 2), precioAderezoFinal)
      .query(`
        INSERT INTO PedidosHorneadosDetalle (IdPedido, Carne, Presentacion, AplicaAderezo, TipoAderezo, PrecioAderezo)
        VALUES (@IdPedido, @Carne, @Presentacion, @AplicaAderezo, @TipoAderezo, @PrecioAderezo)
      `);

    await guardarSugerenciaSiEsNueva(new sql.Request(transaction), {
      idTienda,
      campo: 'CARNE',
      valor: carneNormalizada,
    });
    await guardarSugerenciaSiEsNueva(new sql.Request(transaction), {
      idTienda,
      campo: 'PRESENTACION',
      valor: presentacionNormalizada,
    });

    await transaction.commit();

    await registrarAuditoria({
      idUsuario,
      accion: 'CREAR_PEDIDO_HORNEADO',
      tablaAfectada: 'Pedidos',
      registroAfectadoId: String(idPedido),
      datosNuevos: {
        idCliente, carne: carneNormalizada, presentacion: presentacionNormalizada, cantidad,
        aplicaAderezo: aplicaAderezoFinal, tipoAderezo, precioHorneado: precioHorneadoFinal,
        precioAderezo: precioAderezoFinal, total, fechaEntrega,
      },
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    return res.status(201).json({
      mensaje: 'Pedido de horneados registrado correctamente',
      idPedido,
      carne: carneNormalizada,
      presentacion: presentacionNormalizada,
      cantidad,
      aplicaAderezo: aplicaAderezoFinal,
      tipoAderezo: aplicaAderezoFinal ? tipoAderezo : null,
      precioHorneado: precioHorneadoFinal,
      precioAderezo: precioAderezoFinal,
      precioUnitario: precioUnitarioFinal,
      total,
      fechaEntrega: fechaEntregaFinal,
      fechaCreacion,
      cliente: {
        dni: cliente.DNI,
        nombres: cliente.Nombres,
        apellidoPaterno: cliente.ApellidoPaterno,
        apellidoMaterno: cliente.ApellidoMaterno,
        descripcionNegocio: cliente.DescripcionNegocio,
      },
    });
  } catch (err) {
    await transaction.rollback();
    return next(err);
  }
}

module.exports = { listarSugerencias, crearPedidoHorneado, TIPOS_ADEREZO };
