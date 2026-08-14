const { sql, getPool } = require('../config/db');
const { registrarAuditoria } = require('../utils/auditLog');
const { obtenerIdTrabajador, obtenerTiendasAsignadas } = require('../utils/tiendaAcceso');
const { obtenerSiguienteNumeroPedidoDia } = require('../utils/numeracionPedidos');
// Reusa la misma consulta/mapeo que Hamburguesas para no duplicar ~30
// líneas de JOINs de auditoría — ver la nota en pedidosController.js.
const { SELECT_PEDIDOS_BASE, mapearFilaPedido } = require('./pedidosController');

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
    const numeroPedidoDia = await obtenerSiguienteNumeroPedidoDia(transaction, idTienda);

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
      .input('NumeroPedidoDia', sql.Int, numeroPedidoDia)
      .query(`
        INSERT INTO Pedidos (IdCliente, IdTienda, IdProducto, IdTrabajador, IdUsuarioRegistro, TipoPedido, Cantidad, PrecioUnitario, Total, FechaEntrega, Notas, NumeroPedidoDia, Estado)
        OUTPUT INSERTED.IdPedido, INSERTED.FechaCreacion
        VALUES (@IdCliente, @IdTienda, @IdProducto, @IdTrabajador, @IdUsuarioRegistro, @TipoPedido, @Cantidad, @PrecioUnitario, @Total, @FechaEntrega, @Notas, @NumeroPedidoDia, 'PENDIENTE')
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
      numeroPedidoDia,
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

/** Trae de un solo golpe el detalle (Carne/Presentación/Aderezo) de varios
 * pedidos, indexado por IdPedido — para fusionarlo con las filas que ya
 * trajo SELECT_PEDIDOS_BASE sin hacer una consulta por pedido. */
async function obtenerDetalleHorneadosPorPedidos(pool, idsPedidos) {
  if (idsPedidos.length === 0) return new Map();
  const resultado = await pool.request().query(`
    SELECT IdPedido, Carne, Presentacion, AplicaAderezo, TipoAderezo, PrecioAderezo
    FROM PedidosHorneadosDetalle
    WHERE IdPedido IN (${idsPedidos.map(Number).join(',')})
  `);
  return new Map(resultado.recordset.map((fila) => [fila.IdPedido, fila]));
}

function fusionarDetalleHorneado(pedidoMapeado, detalle) {
  return {
    ...pedidoMapeado,
    carne: detalle?.Carne ?? null,
    presentacion: detalle?.Presentacion ?? null,
    aplicaAderezo: detalle?.AplicaAderezo === 1,
    tipoAderezo: detalle?.TipoAderezo ?? null,
    precioAderezo: detalle?.PrecioAderezo ?? null,
  };
}

/** true si el usuario tiene permitido ver los pedidos de Horneados —
 * SUPERADMIN siempre; TRABAJADOR/ADMIN solo si tienen esa tienda asignada. */
async function tieneAccesoAHorneados(req, idTiendaHorneados) {
  if (req.usuario.rol === 'SUPERADMIN') return true;
  const idTrabajador = await obtenerIdTrabajador(req.usuario.idPersona);
  const idsTiendas = idTrabajador ? await obtenerTiendasAsignadas(idTrabajador) : [];
  return idsTiendas.includes(idTiendaHorneados);
}

/** Mismo candado de tienda que listarPedidos de Hamburguesas, pero para
 * Horneados — antes de esto no existía ningún endpoint para listar estos
 * pedidos desde la app (solo se podían crear), así que no aparecían en
 * ninguna pantalla de personal. */
async function listarPedidosHorneados(req, res, next) {
  try {
    const pool = await getPool();
    const incluirAuditoria = ['ADMIN', 'SUPERADMIN'].includes(req.usuario.rol);

    const tienda = await obtenerTiendaHorneados(pool);
    if (!tienda) return res.status(200).json({ pedidos: [] });

    if (!(await tieneAccesoAHorneados(req, tienda.IdTienda))) {
      return res.status(200).json({ pedidos: [] });
    }

    const result = await pool
      .request()
      .input('IdTienda', sql.Int, tienda.IdTienda)
      .query(`${SELECT_PEDIDOS_BASE} WHERE pd.IdTienda = @IdTienda ORDER BY pd.FechaCreacion DESC`);

    const detalles = await obtenerDetalleHorneadosPorPedidos(pool, result.recordset.map((f) => f.IdPedido));
    const pedidos = result.recordset.map((fila) =>
      fusionarDetalleHorneado(mapearFilaPedido(fila, incluirAuditoria), detalles.get(fila.IdPedido)),
    );

    return res.status(200).json({ pedidos });
  } catch (err) {
    return next(err);
  }
}

/** Deudas pendientes (Estado=ENTREGADO, EstadoPago=DEUDA) de Horneados —
 * mismo candado de tienda que listarPedidosHorneados. */
async function listarDeudasHorneados(req, res, next) {
  try {
    const pool = await getPool();
    const incluirAuditoria = ['ADMIN', 'SUPERADMIN'].includes(req.usuario.rol);

    const tienda = await obtenerTiendaHorneados(pool);
    if (!tienda) return res.status(200).json({ pedidos: [] });

    if (!(await tieneAccesoAHorneados(req, tienda.IdTienda))) {
      return res.status(200).json({ pedidos: [] });
    }

    const result = await pool
      .request()
      .input('IdTienda', sql.Int, tienda.IdTienda)
      .query(`
        ${SELECT_PEDIDOS_BASE}
        WHERE pd.Estado = 'ENTREGADO' AND pd.EstadoPago = 'DEUDA' AND pd.IdTienda = @IdTienda
        ORDER BY pd.FechaEntregaReal ASC
      `);

    const detalles = await obtenerDetalleHorneadosPorPedidos(pool, result.recordset.map((f) => f.IdPedido));
    const pedidos = result.recordset.map((fila) =>
      fusionarDetalleHorneado(mapearFilaPedido(fila, incluirAuditoria), detalles.get(fila.IdPedido)),
    );

    return res.status(200).json({ pedidos });
  } catch (err) {
    return next(err);
  }
}

module.exports = {
  listarSugerencias,
  crearPedidoHorneado,
  listarPedidosHorneados,
  listarDeudasHorneados,
  TIPOS_ADEREZO,
};
