const { sql, getPool } = require('../config/db');
const { registrarAuditoria } = require('../utils/auditLog');
const { obtenerIdTrabajador, obtenerTiendasAsignadas } = require('../utils/tiendaAcceso');
const { obtenerSiguienteNumeroPedidoDia } = require('../utils/numeracionPedidos');
// Reusa la misma consulta/mapeo que Hamburguesas para no duplicar ~30
// líneas de JOINs de auditoría — ver la nota en pedidosController.js.
const { SELECT_PEDIDOS_BASE, armarPedidosConItems, resumirProductos } = require('./pedidosController');

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
 * Registra un pedido de Horneados con UNA O VARIAS líneas — mismo espíritu
 * que `crearPedido` en pedidosController.js (personal registra a nombre de
 * un cliente ya existente, precio libre, nace PENDIENTE), pero con los
 * campos propios de este rubro (carne, presentación, aderezo opcional)
 * guardados aparte en `PedidosHorneadosDetalle`, que cuelga de cada línea
 * (`PedidoItems.IdPedidoItem`) — así un mismo pedido puede tener dos carnes
 * distintas, cada una con su propia presentación y aderezo.
 *
 * Todas las líneas usan el MISMO producto: Horneados tiene un único
 * producto placeholder en el catálogo (lo que varía no es el producto sino
 * sus atributos), resuelto una sola vez por request.
 *
 * Body: `{ idCliente, fechaEntrega?, notas?, items: [{ carne, presentacion,
 * cantidad, aplicaAderezo, tipoAderezo?, precioHorneado, precioAderezo? }] }`.
 */
async function crearPedidoHorneado(req, res, next) {
  const { idCliente, items, fechaEntrega, notas } = req.body;
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
      SELECT t.IdTienda, p.IdProducto, p.Nombre AS ProductoNombre
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
    const productoNombre = tiendaResult.recordset[0].ProductoNombre;

    // Una línea del carrito por cada combinación carne/presentación/aderezo
    // que pidió el vendedor. El precio unitario de la línea es el del
    // horneado más el del aderezo (si aplica), igual que antes — solo que
    // ahora se calcula por línea en vez de una vez por pedido.
    const lineas = items.map((item) => {
      const aplicaAderezoFinal = item.aplicaAderezo === true;
      const precioHorneadoFinal = Number(Number(item.precioHorneado).toFixed(2));
      const precioAderezoFinal = aplicaAderezoFinal ? Number(Number(item.precioAderezo).toFixed(2)) : null;
      const precioUnitario = Number((precioHorneadoFinal + (precioAderezoFinal ?? 0)).toFixed(2));
      return {
        idProducto,
        producto: productoNombre,
        tipoPedido: 'UNIDADES',
        cantidad: item.cantidad,
        precioUnitario,
        subtotal: Number((precioUnitario * item.cantidad).toFixed(2)),
        carne: String(item.carne).trim().toUpperCase(),
        presentacion: String(item.presentacion).trim().toUpperCase(),
        aplicaAderezo: aplicaAderezoFinal,
        tipoAderezo: aplicaAderezoFinal ? item.tipoAderezo : null,
        precioHorneado: precioHorneadoFinal,
        precioAderezo: precioAderezoFinal,
      };
    });

    const total = Number(lineas.reduce((acc, l) => acc + l.subtotal, 0).toFixed(2));
    const fechaEntregaFinal = fechaEntrega ? new Date(fechaEntrega) : null;
    const numeroPedidoDia = await obtenerSiguienteNumeroPedidoDia(transaction, idTienda);

    const insertPedido = await new sql.Request(transaction)
      .input('IdCliente', sql.Int, idCliente)
      .input('IdTienda', sql.Int, idTienda)
      .input('IdTrabajador', sql.Int, idTrabajador)
      .input('IdUsuarioRegistro', sql.Int, idUsuario)
      .input('Total', sql.Decimal(10, 2), total)
      .input('FechaEntrega', sql.DateTime2, fechaEntregaFinal)
      .input('Notas', sql.NVarChar(300), notas ? notas.trim().toUpperCase() : null)
      .input('NumeroPedidoDia', sql.Int, numeroPedidoDia)
      .query(`
        INSERT INTO Pedidos (IdCliente, IdTienda, IdTrabajador, IdUsuarioRegistro, Total, FechaEntrega, Notas, NumeroPedidoDia, Estado)
        OUTPUT INSERTED.IdPedido, INSERTED.FechaCreacion
        VALUES (@IdCliente, @IdTienda, @IdTrabajador, @IdUsuarioRegistro, @Total, @FechaEntrega, @Notas, @NumeroPedidoDia, 'PENDIENTE')
      `);
    const { IdPedido: idPedido, FechaCreacion: fechaCreacion } = insertPedido.recordset[0];

    for (const linea of lineas) {
      const insertItem = await new sql.Request(transaction)
        .input('IdPedido', sql.Int, idPedido)
        .input('IdProducto', sql.Int, linea.idProducto)
        .input('TipoPedido', sql.VarChar(20), linea.tipoPedido)
        .input('Cantidad', sql.Int, linea.cantidad)
        .input('PrecioUnitario', sql.Decimal(10, 2), linea.precioUnitario)
        .input('Subtotal', sql.Decimal(10, 2), linea.subtotal)
        .query(`
          INSERT INTO PedidoItems (IdPedido, IdProducto, TipoPedido, Cantidad, PrecioUnitario, Subtotal)
          OUTPUT INSERTED.IdPedidoItem
          VALUES (@IdPedido, @IdProducto, @TipoPedido, @Cantidad, @PrecioUnitario, @Subtotal)
        `);
      const idPedidoItem = insertItem.recordset[0].IdPedidoItem;
      linea.idPedidoItem = idPedidoItem;

      // El detalle cuelga de la LÍNEA, no del pedido: cada una conserva su
      // propia carne/presentación/aderezo.
      await new sql.Request(transaction)
        .input('IdPedidoItem', sql.Int, idPedidoItem)
        .input('Carne', sql.VarChar(100), linea.carne)
        .input('Presentacion', sql.VarChar(100), linea.presentacion)
        .input('AplicaAderezo', sql.Bit, linea.aplicaAderezo)
        .input('TipoAderezo', sql.VarChar(20), linea.tipoAderezo)
        .input('PrecioAderezo', sql.Decimal(10, 2), linea.precioAderezo)
        .query(`
          INSERT INTO PedidosHorneadosDetalle (IdPedidoItem, Carne, Presentacion, AplicaAderezo, TipoAderezo, PrecioAderezo)
          VALUES (@IdPedidoItem, @Carne, @Presentacion, @AplicaAderezo, @TipoAderezo, @PrecioAderezo)
        `);
    }

    // Las sugerencias se guardan una sola vez por valor ÚNICO del carrito:
    // dos líneas con la misma carne no tienen por qué generar dos INSERT
    // (el INSERT IGNORE los absorbería igual, pero es un viaje de más).
    for (const carne of new Set(lineas.map((l) => l.carne))) {
      await guardarSugerenciaSiEsNueva(new sql.Request(transaction), { idTienda, campo: 'CARNE', valor: carne });
    }
    for (const presentacion of new Set(lineas.map((l) => l.presentacion))) {
      await guardarSugerenciaSiEsNueva(new sql.Request(transaction), {
        idTienda,
        campo: 'PRESENTACION',
        valor: presentacion,
      });
    }

    await transaction.commit();

    await registrarAuditoria({
      idUsuario,
      accion: 'CREAR_PEDIDO_HORNEADO',
      tablaAfectada: 'Pedidos',
      registroAfectadoId: String(idPedido),
      datosNuevos: { idCliente, items: lineas, total, fechaEntrega },
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    return res.status(201).json({
      mensaje: 'Pedido de horneados registrado correctamente',
      idPedido,
      numeroPedidoDia,
      items: lineas,
      productoResumen: resumirProductos(lineas),
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

// `obtenerDetalleHorneadosPorPedidos`/`fusionarDetalleHorneado` ya no
// existen: el detalle de Horneados ahora cuelga de cada línea de carrito y
// lo trae `obtenerItemsPorPedidos` (pedidosController.js) con el mismo
// LEFT JOIN, para todas las tiendas por igual.

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

    const pedidos = await armarPedidosConItems(pool, result.recordset, incluirAuditoria);

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

    const pedidos = await armarPedidosConItems(pool, result.recordset, incluirAuditoria);

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
