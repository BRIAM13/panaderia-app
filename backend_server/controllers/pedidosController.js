const { sql, getPool } = require('../config/db');
const { registrarAuditoria } = require('../utils/auditLog');
const { enviarPush } = require('../services/pushService');
const { obtenerIdTrabajador, obtenerTiendasAsignadas, tieneAccesoATienda } = require('../utils/tiendaAcceso');

async function crearPedido(req, res, next) {
  const { idCliente, tipoPedido, cantidad, precioUnitario, fechaEntrega, notas } = req.body;
  const { idPersona, idUsuario } = req.usuario;

  const pool = await getPool();
  const transaction = new sql.Transaction(pool);

  try {
    await transaction.begin();

    // La ruta ya exige TRABAJADOR/ADMIN/SUPERADMIN (ver pedidosRoutes.js),
    // así que cualquiera que llegue hasta acá es personal — no hace falta
    // que además tenga una ficha de Trabajador (el SUPERADMIN dueño, por
    // ejemplo, nunca tiene una: tiene acceso implícito global). Si sí
    // tiene una, se guarda en IdTrabajador aparte (informativo, ej. su
    // cargo/tiendas); quién lo registró de verdad siempre queda en
    // IdUsuarioRegistro, sin importar si tiene ficha o no.
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

    // El producto solo se usa para categorizar el pedido en reportes; el
    // precio real lo decide el vendedor en pantalla (ver más abajo), no el
    // catálogo — así se pueden negociar descuentos o precios especiales.
    const productoResult = await new sql.Request(transaction).query(`
      SELECT TOP 1 p.IdProducto, c.IdTienda
      FROM Productos p
      INNER JOIN Categorias c ON c.IdCategoria = p.IdCategoria
      WHERE c.Nombre = 'Pan de Hamburguesa' AND p.Estado = 1
      ORDER BY p.IdProducto
    `);

    if (productoResult.recordset.length === 0) {
      await transaction.rollback();
      return res.status(500).json({ mensaje: 'No hay un producto de Pan de Hamburguesa configurado' });
    }

    const { IdProducto: idProducto, IdTienda: idTienda } = productoResult.recordset[0];
    const precioUnitarioFinal = Number(Number(precioUnitario).toFixed(2));
    const total = Number((precioUnitarioFinal * cantidad).toFixed(2));
    // La fecha/hora de entrega es opcional: un pedido puede quedar "sin
    // fecha programada" y coordinarse después. Registrado por el propio
    // personal: nace confirmado (PENDIENTE), no necesita aprobación.
    const fechaEntregaFinal = fechaEntrega ? new Date(fechaEntrega) : null;

    const insertResult = await new sql.Request(transaction)
      .input('IdCliente', sql.Int, idCliente)
      .input('IdTienda', sql.Int, idTienda)
      .input('IdProducto', sql.Int, idProducto)
      .input('IdTrabajador', sql.Int, idTrabajador)
      .input('IdUsuarioRegistro', sql.Int, idUsuario)
      .input('TipoPedido', sql.VarChar(20), tipoPedido)
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
    const { IdPedido: idPedido, FechaCreacion: fechaCreacion } = insertResult.recordset[0];

    await transaction.commit();

    await registrarAuditoria({
      idUsuario,
      accion: 'CREAR_PEDIDO',
      tablaAfectada: 'Pedidos',
      registroAfectadoId: String(idPedido),
      datosNuevos: { idCliente, tipoPedido, cantidad, precioUnitario: precioUnitarioFinal, total, fechaEntrega },
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    // Silencioso a propósito (sin titulo/cuerpo, ver enviarPush): solo para
    // que las pantallas de Pedidos de OTROS dispositivos/miembros del
    // personal de esta tienda se actualicen solas — nadie quiere un banner
    // de notificación por cada acción de otro compañero, serían demasiadas.
    await notificarPersonalTienda({
      idTienda,
      datos: { tipo: 'NUEVO_PEDIDO', idTienda: String(idTienda), idPedido: String(idPedido) },
    });

    return res.status(201).json({
      mensaje: 'Pedido registrado correctamente',
      idPedido,
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

/**
 * Notifica por push a todo el personal con acceso vigente a [idTienda]
 * (TrabajadorTiendas.Estado = 1) más todos los SUPERADMIN (acceso global
 * implícito). Nunca revienta la creación del pedido si el envío falla —
 * las notificaciones son un extra, no un requisito para que el pedido se
 * registre.
 */
async function notificarPersonalTienda({ idTienda, titulo, cuerpo, datos }) {
  try {
    const pool = await getPool();
    const result = await pool
      .request()
      .input('IdTienda', sql.Int, idTienda)
      .query(`
        SELECT DISTINCT dn.FcmToken
        FROM DispositivosNotificacion dn
        INNER JOIN Usuarios u ON u.IdUsuario = dn.IdUsuario
        INNER JOIN Roles rol ON rol.IdRol = u.IdRol
        LEFT JOIN Trabajadores trab ON trab.IdPersona = u.IdPersona AND trab.Estado = 1
        LEFT JOIN TrabajadorTiendas tt ON tt.IdTrabajador = trab.IdTrabajador AND tt.IdTienda = @IdTienda AND tt.Estado = 1
        WHERE rol.NombreRol = 'SUPERADMIN' OR tt.IdTrabajadorTienda IS NOT NULL
      `);

    await enviarPushLimpiandoInvalidos(result.recordset.map((f) => f.FcmToken), { titulo, cuerpo, datos });
  } catch (_) {
    // Silencioso a propósito: un fallo de notificación no debe afectar al
    // pedido que ya se registró correctamente.
  }
}

/** Notifica al propio cliente (todos sus dispositivos) sobre el estado de
 * uno de sus pedidos — aprobado, rechazado o entregado. */
async function notificarCliente({ idCliente, titulo, cuerpo, datos }) {
  try {
    const pool = await getPool();
    const result = await pool
      .request()
      .input('IdCliente', sql.Int, idCliente)
      .query(`
        SELECT dn.FcmToken
        FROM Clientes c
        INNER JOIN Personas p ON p.IdPersona = c.IdPersona
        INNER JOIN Usuarios u ON u.IdPersona = p.IdPersona
        INNER JOIN DispositivosNotificacion dn ON dn.IdUsuario = u.IdUsuario
        WHERE c.IdCliente = @IdCliente
      `);

    await enviarPushLimpiandoInvalidos(result.recordset.map((f) => f.FcmToken), { titulo, cuerpo, datos });
  } catch (_) {
    // Igual de silencioso: el cambio de estado ya se guardó, notificar es
    // un extra.
  }
}

async function enviarPushLimpiandoInvalidos(tokens, { titulo, cuerpo, datos }) {
  if (tokens.length === 0) return;
  const pool = await getPool();
  const { tokensInvalidos } = await enviarPush({ tokens, titulo, cuerpo, datos });
  if (tokensInvalidos.length > 0) {
    await pool
      .request()
      .query(`DELETE FROM DispositivosNotificacion WHERE FcmToken IN (${tokensInvalidos.map((t) => `'${t.replace(/'/g, "''")}'`).join(',')})`);
  }
}

/**
 * Autoservicio (rol CLIENTE): el propio cliente registra su pedido. A
 * diferencia de crearPedido (personal, precio negociado en el momento),
 * aquí el precio SIEMPRE sale del catálogo — nadie está ahí para negociar.
 * idCliente nunca viene del body: siempre es el del propio JWT, así un
 * cliente jamás puede registrar un pedido a nombre de otro.
 *
 * Por ahora solo se permite Hamburguesas + Paquetes: es el único producto
 * con precio fijo y confiable (Configuraciones.PRECIO_PAQUETE) — el resto
 * del catálogo (Horneados, Unidades sueltas) todavía no tiene un precio
 * estable como para que un cliente lo pida sin que alguien lo revise antes.
 *
 * Nace en estado 'SOLICITADO': el personal de la tienda debe aceptarlo o
 * rechazarlo según stock antes de que cuente como confirmado.
 */
async function crearMiPedido(req, res, next) {
  const { idTienda, tipoPedido, cantidad, fechaEntrega, notas } = req.body;
  const { idPersona, idUsuario } = req.usuario;

  const pool = await getPool();
  const transaction = new sql.Transaction(pool);

  try {
    await transaction.begin();

    const clienteResult = await new sql.Request(transaction)
      .input('IdPersona', sql.Int, idPersona)
      .query(`
        SELECT c.IdCliente, c.DescripcionNegocio, p.DNI, p.Nombres, p.ApellidoPaterno, p.ApellidoMaterno
        FROM Clientes c
        INNER JOIN Personas p ON p.IdPersona = c.IdPersona
        WHERE c.IdPersona = @IdPersona AND c.Estado = 1
      `);

    if (clienteResult.recordset.length === 0) {
      await transaction.rollback();
      return res.status(404).json({ mensaje: 'No tienes un perfil de cliente asociado a tu cuenta' });
    }
    const cliente = clienteResult.recordset[0];

    const tiendaResult = await new sql.Request(transaction)
      .input('IdTienda', sql.Int, idTienda)
      .query('SELECT IdTienda, Nombre, Slug FROM Tiendas WHERE IdTienda = @IdTienda AND Disponible = 1 AND Estado = 1');

    if (tiendaResult.recordset.length === 0) {
      await transaction.rollback();
      return res.status(404).json({ mensaje: 'Tienda no disponible' });
    }
    const tienda = tiendaResult.recordset[0];

    if (tienda.Slug !== 'hamburguesas' || tipoPedido !== 'PAQUETES') {
      await transaction.rollback();
      return res.status(400).json({
        mensaje: 'Por ahora solo puedes pedir paquetes de pan de hamburguesa — el resto del catálogo aún no tiene precio fijo.',
      });
    }

    const productoResult = await new sql.Request(transaction)
      .input('IdTienda', sql.Int, idTienda)
      .query(`
        SELECT TOP 1 p.IdProducto, p.PrecioUnitario
        FROM Productos p
        INNER JOIN Categorias c ON c.IdCategoria = p.IdCategoria
        WHERE c.IdTienda = @IdTienda AND p.Estado = 1
        ORDER BY p.IdProducto
      `);

    if (productoResult.recordset.length === 0) {
      await transaction.rollback();
      return res.status(500).json({ mensaje: 'Esta tienda todavía no tiene un producto configurado' });
    }
    const { IdProducto: idProducto } = productoResult.recordset[0];

    // Paquetes de Hamburguesas usa el precio de Configuraciones (el mismo
    // que ve el personal), no Productos.PrecioUnitario — así el cliente
    // siempre ve el precio vigente real del paquete de 12.
    const config = await new sql.Request(transaction).query("SELECT Valor FROM Configuraciones WHERE Clave = 'PRECIO_PAQUETE'");
    const precioUnitarioFinal = config.recordset.length > 0 ? Number(config.recordset[0].Valor) : 0;

    const total = Number((precioUnitarioFinal * cantidad).toFixed(2));
    const fechaEntregaFinal = fechaEntrega ? new Date(fechaEntrega) : null;

    const insertResult = await new sql.Request(transaction)
      .input('IdCliente', sql.Int, cliente.IdCliente)
      .input('IdTienda', sql.Int, idTienda)
      .input('IdProducto', sql.Int, idProducto)
      .input('TipoPedido', sql.VarChar(20), tipoPedido)
      .input('Cantidad', sql.Int, cantidad)
      .input('PrecioUnitario', sql.Decimal(10, 2), precioUnitarioFinal)
      .input('Total', sql.Decimal(10, 2), total)
      .input('FechaEntrega', sql.DateTime2, fechaEntregaFinal)
      .input('Notas', sql.NVarChar(300), notas ? notas.trim().toUpperCase() : null)
      .query(`
        INSERT INTO Pedidos (IdCliente, IdTienda, IdProducto, IdTrabajador, TipoPedido, Cantidad, PrecioUnitario, Total, FechaEntrega, Notas, Estado)
        OUTPUT INSERTED.IdPedido, INSERTED.FechaCreacion
        VALUES (@IdCliente, @IdTienda, @IdProducto, NULL, @TipoPedido, @Cantidad, @PrecioUnitario, @Total, @FechaEntrega, @Notas, 'SOLICITADO')
      `);
    const { IdPedido: idPedido, FechaCreacion: fechaCreacion } = insertResult.recordset[0];

    await transaction.commit();

    await registrarAuditoria({
      idUsuario,
      accion: 'CREAR_MI_PEDIDO',
      tablaAfectada: 'Pedidos',
      registroAfectadoId: String(idPedido),
      datosNuevos: { idTienda, tipoPedido, cantidad, precioUnitario: precioUnitarioFinal, total, fechaEntrega },
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    const nombreCliente = [cliente.Nombres, cliente.ApellidoPaterno].filter(Boolean).join(' ');
    await notificarPersonalTienda({
      idTienda,
      titulo: `Pedido por confirmar — ${tienda.Nombre}`,
      cuerpo: `${cliente.DescripcionNegocio || nombreCliente} solicitó un pedido por S/ ${total.toFixed(2)}. Revisa el stock y acéptalo o recházalo.`,
      datos: { tipo: 'PEDIDO_SOLICITADO', idTienda: String(idTienda), idPedido: String(idPedido) },
    });

    return res.status(201).json({
      mensaje: 'Pedido solicitado — el personal lo confirmará según stock disponible',
      idPedido,
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

const SELECT_PEDIDOS_BASE = `
  SELECT pd.IdPedido, pd.IdCliente, pd.IdTienda, pd.TipoPedido, pd.Cantidad, pd.PrecioUnitario, pd.Total, pd.FechaEntrega,
         pd.Estado, pd.EstadoPago, pd.FechaEntregaReal, pd.Notas, pd.FechaCreacion,
         per.DNI AS ClienteDni, per.Nombres AS ClienteNombres,
         per.ApellidoPaterno AS ClienteApellidoPaterno, per.ApellidoMaterno AS ClienteApellidoMaterno,
         c.DescripcionNegocio AS ClienteDescripcionNegocio,
         t.Nombre AS TiendaNombre,
         prod.Nombre AS ProductoNombre,
         registroPer.Nombres AS VendedorNombres, registroPer.ApellidoPaterno AS VendedorApellidoPaterno,
         registroRol.NombreRol AS VendedorRol,
         aprobPer.Nombres AS AprobadoNombres, aprobPer.ApellidoPaterno AS AprobadoApellidoPaterno,
         cancelPer.Nombres AS CanceladoNombres, cancelPer.ApellidoPaterno AS CanceladoApellidoPaterno,
         entregPer.Nombres AS EntregadoNombres, entregPer.ApellidoPaterno AS EntregadoApellidoPaterno
  FROM Pedidos pd
  INNER JOIN Clientes c ON c.IdCliente = pd.IdCliente
  INNER JOIN Personas per ON per.IdPersona = c.IdPersona
  LEFT JOIN Tiendas t ON t.IdTienda = pd.IdTienda
  INNER JOIN Productos prod ON prod.IdProducto = pd.IdProducto
  -- Quién lo registró: por IdUsuarioRegistro, no por IdTrabajador — así
  -- funciona igual sin importar si esa persona tiene o no una ficha de
  -- Trabajador (ej. el SUPERADMIN dueño no tiene una).
  LEFT JOIN Usuarios registroUsr ON registroUsr.IdUsuario = pd.IdUsuarioRegistro
  LEFT JOIN Personas registroPer ON registroPer.IdPersona = registroUsr.IdPersona
  LEFT JOIN Roles registroRol ON registroRol.IdRol = registroUsr.IdRol
  LEFT JOIN Usuarios aprobUsr ON aprobUsr.IdUsuario = pd.IdUsuarioAprobo
  LEFT JOIN Personas aprobPer ON aprobPer.IdPersona = aprobUsr.IdPersona
  LEFT JOIN Usuarios cancelUsr ON cancelUsr.IdUsuario = pd.IdUsuarioCancelo
  LEFT JOIN Personas cancelPer ON cancelPer.IdPersona = cancelUsr.IdPersona
  LEFT JOIN Usuarios entregUsr ON entregUsr.IdUsuario = pd.IdUsuarioEntrego
  LEFT JOIN Personas entregPer ON entregPer.IdPersona = entregUsr.IdPersona
`;

/**
 * `incluirAuditoria` solo debe venir en true para SUPERADMIN/ADMIN (ver
 * listarPedidos/listarDeudas) — un TRABAJADOR raso o el propio cliente
 * nunca deben ver quién registró/aprobó/canceló/entregó cada pedido.
 */
function mapearFilaPedido(fila, incluirAuditoria = false) {
  const base = {
    idPedido: fila.IdPedido,
    idCliente: fila.IdCliente,
    idTienda: fila.IdTienda,
    tienda: fila.TiendaNombre,
    tipoPedido: fila.TipoPedido,
    cantidad: fila.Cantidad,
    precioUnitario: fila.PrecioUnitario,
    total: fila.Total,
    fechaEntrega: fila.FechaEntrega,
    estado: fila.Estado,
    estadoPago: fila.EstadoPago,
    fechaEntregaReal: fila.FechaEntregaReal,
    notas: fila.Notas,
    fechaCreacion: fila.FechaCreacion,
    cliente: {
      dni: fila.ClienteDni,
      nombres: fila.ClienteNombres,
      apellidoPaterno: fila.ClienteApellidoPaterno,
      apellidoMaterno: fila.ClienteApellidoMaterno,
      descripcionNegocio: fila.ClienteDescripcionNegocio,
    },
    producto: fila.ProductoNombre,
    // null si lo registró el propio cliente (autoservicio), no el personal.
    vendedor: fila.VendedorNombres ? `${fila.VendedorNombres} ${fila.VendedorApellidoPaterno}` : null,
  };

  if (!incluirAuditoria) return base;

  return {
    ...base,
    // Quién registró el pedido: el rol del vendedor si lo hizo el
    // personal, o 'CLIENTE' si fue autoservicio (vendedor null).
    registradoPorRol: fila.VendedorNombres ? fila.VendedorRol : 'CLIENTE',
    aprobadoPor: fila.AprobadoNombres ? `${fila.AprobadoNombres} ${fila.AprobadoApellidoPaterno}` : null,
    canceladoPor: fila.CanceladoNombres ? `${fila.CanceladoNombres} ${fila.CanceladoApellidoPaterno}` : null,
    entregadoPor: fila.EntregadoNombres ? `${fila.EntregadoNombres} ${fila.EntregadoApellidoPaterno}` : null,
  };
}

/**
 * SUPERADMIN ve todos los pedidos de todas las tiendas. TRABAJADOR/ADMIN
 * solo ven pedidos de las tiendas donde tienen acceso vigente — mismo
 * candado que ya aplica para gestionar trabajadores/notificaciones.
 */
async function listarPedidos(req, res, next) {
  try {
    const pool = await getPool();
    // Quién registró/aprobó/canceló/entregó cada pedido es información
    // sensible de gestión interna — solo ADMIN/SUPERADMIN la ven, un
    // TRABAJADOR raso no.
    const incluirAuditoria = ['ADMIN', 'SUPERADMIN'].includes(req.usuario.rol);
    const mapear = (fila) => mapearFilaPedido(fila, incluirAuditoria);

    if (req.usuario.rol === 'SUPERADMIN') {
      const result = await pool.request().query(`${SELECT_PEDIDOS_BASE} ORDER BY pd.FechaCreacion DESC`);
      return res.status(200).json({ pedidos: result.recordset.map(mapear) });
    }

    const idTrabajador = await obtenerIdTrabajador(req.usuario.idPersona);
    const idsTiendas = idTrabajador ? await obtenerTiendasAsignadas(idTrabajador) : [];
    if (idsTiendas.length === 0) {
      return res.status(200).json({ pedidos: [] });
    }

    const result = await pool
      .request()
      .query(`${SELECT_PEDIDOS_BASE} WHERE pd.IdTienda IN (${idsTiendas.join(',')}) ORDER BY pd.FechaCreacion DESC`);
    return res.status(200).json({ pedidos: result.recordset.map(mapear) });
  } catch (err) {
    return next(err);
  }
}

/**
 * Autoservicio (rol CLIENTE): solo SUS propios pedidos, nunca los de otro
 * cliente. Los rechazados (por el personal) y cancelados (por el propio
 * cliente) no se muestran — "desaparecen" de su lista una vez notificados,
 * aunque la fila sigue existiendo para auditoría.
 */
async function misPedidos(req, res, next) {
  try {
    const pool = await getPool();
    const clienteResult = await pool
      .request()
      .input('IdPersona', sql.Int, req.usuario.idPersona)
      .query('SELECT IdCliente FROM Clientes WHERE IdPersona = @IdPersona AND Estado = 1');

    if (clienteResult.recordset.length === 0) {
      return res.status(404).json({ mensaje: 'No tienes un perfil de cliente asociado a tu cuenta' });
    }
    const { IdCliente: idCliente } = clienteResult.recordset[0];

    const result = await pool
      .request()
      .input('IdCliente', sql.Int, idCliente)
      .query(
        `${SELECT_PEDIDOS_BASE} WHERE pd.IdCliente = @IdCliente AND pd.Estado NOT IN ('RECHAZADO', 'CANCELADO') ORDER BY pd.FechaCreacion DESC`,
      );

    return res.status(200).json({ pedidos: result.recordset.map(mapearFilaPedido) });
  } catch (err) {
    return next(err);
  }
}

/**
 * Autoservicio (rol CLIENTE): el propio cliente cancela un pedido suyo,
 * siempre que todavía no haya sido entregado — puede estar SOLICITADO
 * (ni siquiera revisado aún) o PENDIENTE (ya confirmado, en espera de
 * entrega). Una vez ENTREGADO ya no se puede deshacer. Avisa al personal
 * de la tienda por si ya empezaron a prepararlo.
 */
async function cancelarMiPedido(req, res, next) {
  try {
    const { id } = req.params;
    const pool = await getPool();

    const clienteResult = await pool
      .request()
      .input('IdPersona', sql.Int, req.usuario.idPersona)
      .query(`
        SELECT c.IdCliente, c.DescripcionNegocio, p.Nombres, p.ApellidoPaterno
        FROM Clientes c
        INNER JOIN Personas p ON p.IdPersona = c.IdPersona
        WHERE c.IdPersona = @IdPersona AND c.Estado = 1
      `);
    if (clienteResult.recordset.length === 0) {
      return res.status(404).json({ mensaje: 'No tienes un perfil de cliente asociado a tu cuenta' });
    }
    const cliente = clienteResult.recordset[0];

    const pedidoResult = await pool
      .request()
      .input('IdPedido', sql.Int, id)
      .input('IdCliente', sql.Int, cliente.IdCliente)
      .query('SELECT IdPedido, IdTienda, Estado FROM Pedidos WHERE IdPedido = @IdPedido AND IdCliente = @IdCliente');

    if (pedidoResult.recordset.length === 0) {
      return res.status(404).json({ mensaje: 'Pedido no encontrado' });
    }
    const pedido = pedidoResult.recordset[0];

    if (pedido.Estado !== 'SOLICITADO' && pedido.Estado !== 'PENDIENTE') {
      return res.status(400).json({ mensaje: 'Este pedido ya no se puede cancelar.' });
    }

    await pool
      .request()
      .input('IdPedido', sql.Int, pedido.IdPedido)
      .input('IdUsuario', sql.Int, req.usuario.idUsuario)
      .query(`
        UPDATE Pedidos
        SET Estado = 'CANCELADO', IdUsuarioCancelo = @IdUsuario, FechaCancelacion = SYSUTCDATETIME()
        WHERE IdPedido = @IdPedido
      `);

    await registrarAuditoria({
      idUsuario: req.usuario.idUsuario,
      accion: 'CANCELAR_MI_PEDIDO',
      tablaAfectada: 'Pedidos',
      registroAfectadoId: String(pedido.IdPedido),
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    if (pedido.IdTienda) {
      const nombreCliente = [cliente.Nombres, cliente.ApellidoPaterno].filter(Boolean).join(' ');
      await notificarPersonalTienda({
        idTienda: pedido.IdTienda,
        titulo: 'Pedido cancelado por el cliente',
        cuerpo: `${cliente.DescripcionNegocio || nombreCliente} canceló su pedido #${pedido.IdPedido}.`,
        datos: { tipo: 'PEDIDO_CANCELADO', idTienda: String(pedido.IdTienda), idPedido: String(pedido.IdPedido) },
      });
    }

    return res.status(200).json({ mensaje: 'Pedido cancelado correctamente' });
  } catch (err) {
    return next(err);
  }
}

/**
 * El personal cancela un pedido (SOLICITADO o PENDIENTE) desde su lado —
 * ej. ya se había confirmado pero por algún motivo no se puede cumplir.
 * Distinto de cancelarMiPedido (autoservicio del cliente): este lo usa el
 * personal sobre cualquier pedido de su tienda, y deja registrado quién lo
 * hizo. Antes de esto, la única acción disponible para un pedido ya
 * confirmado era "marcar entregado" — no había forma de deshacerlo.
 */
async function cancelarPedido(req, res, next) {
  try {
    const pedido = await obtenerPedidoConAcceso(req, res);
    if (!pedido) return;
    if (pedido.Estado !== 'SOLICITADO' && pedido.Estado !== 'PENDIENTE') {
      return res.status(400).json({ mensaje: 'Este pedido ya no se puede cancelar' });
    }

    const pool = await getPool();
    await pool
      .request()
      .input('IdPedido', sql.Int, pedido.IdPedido)
      .input('IdUsuario', sql.Int, req.usuario.idUsuario)
      .query(`
        UPDATE Pedidos
        SET Estado = 'CANCELADO', IdUsuarioCancelo = @IdUsuario, FechaCancelacion = SYSUTCDATETIME()
        WHERE IdPedido = @IdPedido
      `);

    await registrarAuditoria({
      idUsuario: req.usuario.idUsuario,
      accion: 'CANCELAR_PEDIDO',
      tablaAfectada: 'Pedidos',
      registroAfectadoId: String(pedido.IdPedido),
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    await notificarCliente({
      idCliente: pedido.IdCliente,
      titulo: 'Tu pedido fue cancelado',
      cuerpo: `Tu pedido #${pedido.IdPedido} fue cancelado por la tienda.`,
      datos: { tipo: 'PEDIDO_CANCELADO', idPedido: String(pedido.IdPedido) },
    });
    // Silencioso a propósito — ver comentario en notificarPersonalTienda
    // de crearPedido: solo refresca la pantalla de otros dispositivos del
    // personal, sin bombardearlos de notificaciones.
    await notificarPersonalTienda({
      idTienda: pedido.IdTienda,
      datos: { tipo: 'PEDIDO_CANCELADO', idTienda: String(pedido.IdTienda), idPedido: String(pedido.IdPedido) },
    });

    return res.status(200).json({ mensaje: 'Pedido cancelado correctamente' });
  } catch (err) {
    return next(err);
  }
}

/** Trae un pedido + valida que quien llama tenga acceso a SU tienda —
 * usado por aprobar/rechazar/entregar, que no son rutas con :idTienda en
 * la URL (son :id de pedido, hace falta resolver la tienda primero). */
async function obtenerPedidoConAcceso(req, res) {
  const { id } = req.params;
  const pool = await getPool();
  const result = await pool
    .request()
    .input('IdPedido', sql.Int, id)
    .query('SELECT IdPedido, IdCliente, IdTienda, Estado, Total FROM Pedidos WHERE IdPedido = @IdPedido');

  if (result.recordset.length === 0) {
    res.status(404).json({ mensaje: 'Pedido no encontrado' });
    return null;
  }
  const pedido = result.recordset[0];

  const acceso = await tieneAccesoATienda({ rol: req.usuario.rol, idPersona: req.usuario.idPersona, idTienda: pedido.IdTienda });
  if (!acceso) {
    res.status(403).json({ mensaje: 'No tienes acceso a esta tienda' });
    return null;
  }

  return pedido;
}

/** El personal acepta un pedido SOLICITADO por un cliente — pasa a
 * PENDIENTE (confirmado, en espera de entrega). */
async function aprobarPedido(req, res, next) {
  try {
    const pedido = await obtenerPedidoConAcceso(req, res);
    if (!pedido) return;
    if (pedido.Estado !== 'SOLICITADO') {
      return res.status(400).json({ mensaje: 'Este pedido ya no está pendiente de aprobación' });
    }

    const pool = await getPool();
    await pool
      .request()
      .input('IdPedido', sql.Int, pedido.IdPedido)
      .input('IdUsuario', sql.Int, req.usuario.idUsuario)
      .query(`
        UPDATE Pedidos
        SET Estado = 'PENDIENTE', IdUsuarioAprobo = @IdUsuario, FechaAprobacion = SYSUTCDATETIME()
        WHERE IdPedido = @IdPedido
      `);

    await registrarAuditoria({
      idUsuario: req.usuario.idUsuario,
      accion: 'APROBAR_PEDIDO',
      tablaAfectada: 'Pedidos',
      registroAfectadoId: String(pedido.IdPedido),
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    await notificarCliente({
      idCliente: pedido.IdCliente,
      titulo: 'Tu pedido fue confirmado',
      cuerpo: `Tu pedido #${pedido.IdPedido} por S/ ${Number(pedido.Total).toFixed(2)} fue aceptado y ya está en camino a entregarse.`,
      datos: { tipo: 'PEDIDO_APROBADO', idPedido: String(pedido.IdPedido) },
    });
    // Silencioso — ídem.
    await notificarPersonalTienda({
      idTienda: pedido.IdTienda,
      datos: { tipo: 'PEDIDO_APROBADO', idTienda: String(pedido.IdTienda), idPedido: String(pedido.IdPedido) },
    });

    return res.status(200).json({ mensaje: 'Pedido confirmado correctamente' });
  } catch (err) {
    return next(err);
  }
}

/** El personal rechaza un pedido SOLICITADO (ej. no hay stock) — pasa a
 * RECHAZADO y desaparece de "Mis pedidos" del cliente. */
async function rechazarPedido(req, res, next) {
  try {
    const pedido = await obtenerPedidoConAcceso(req, res);
    if (!pedido) return;
    if (pedido.Estado !== 'SOLICITADO') {
      return res.status(400).json({ mensaje: 'Este pedido ya no está pendiente de aprobación' });
    }

    const pool = await getPool();
    await pool.request().input('IdPedido', sql.Int, pedido.IdPedido).query("UPDATE Pedidos SET Estado = 'RECHAZADO' WHERE IdPedido = @IdPedido");

    await registrarAuditoria({
      idUsuario: req.usuario.idUsuario,
      accion: 'RECHAZAR_PEDIDO',
      tablaAfectada: 'Pedidos',
      registroAfectadoId: String(pedido.IdPedido),
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    await notificarCliente({
      idCliente: pedido.IdCliente,
      titulo: 'Tu pedido fue rechazado',
      cuerpo: `Tu pedido #${pedido.IdPedido} no pudo confirmarse por falta de stock. Intenta nuevamente más tarde.`,
      datos: { tipo: 'PEDIDO_RECHAZADO', idPedido: String(pedido.IdPedido) },
    });
    // Silencioso — ídem.
    await notificarPersonalTienda({
      idTienda: pedido.IdTienda,
      datos: { tipo: 'PEDIDO_RECHAZADO', idTienda: String(pedido.IdTienda), idPedido: String(pedido.IdPedido) },
    });

    return res.status(200).json({ mensaje: 'Pedido rechazado correctamente' });
  } catch (err) {
    return next(err);
  }
}

/**
 * Deudas pendientes (Estado=ENTREGADO, EstadoPago=DEUDA), con el mismo
 * candado de tienda que listarPedidos — SUPERADMIN ve todas, el resto solo
 * las de sus tiendas asignadas. El pago real por distintos medios queda
 * para más adelante; por ahora el personal solo puede marcarla saldada a
 * mano (ej. el cliente pagó en efectivo/Yape y se confirma manualmente).
 */
async function listarDeudas(req, res, next) {
  try {
    const pool = await getPool();
    const filtroEstado = "WHERE pd.Estado = 'ENTREGADO' AND pd.EstadoPago = 'DEUDA'";
    const incluirAuditoria = ['ADMIN', 'SUPERADMIN'].includes(req.usuario.rol);
    const mapear = (fila) => mapearFilaPedido(fila, incluirAuditoria);

    if (req.usuario.rol === 'SUPERADMIN') {
      const result = await pool.request().query(`${SELECT_PEDIDOS_BASE} ${filtroEstado} ORDER BY pd.FechaEntregaReal ASC`);
      return res.status(200).json({ pedidos: result.recordset.map(mapear) });
    }

    const idTrabajador = await obtenerIdTrabajador(req.usuario.idPersona);
    const idsTiendas = idTrabajador ? await obtenerTiendasAsignadas(idTrabajador) : [];
    if (idsTiendas.length === 0) {
      return res.status(200).json({ pedidos: [] });
    }

    const result = await pool
      .request()
      .query(`${SELECT_PEDIDOS_BASE} ${filtroEstado} AND pd.IdTienda IN (${idsTiendas.join(',')}) ORDER BY pd.FechaEntregaReal ASC`);
    return res.status(200).json({ pedidos: result.recordset.map(mapear) });
  } catch (err) {
    return next(err);
  }
}

/** Marca una deuda como saldada manualmente (efectivo/Yape/etc. confirmado
 * en persona) — la integración con pasarelas de pago reales queda para
 * después. */
async function marcarDeudaPagada(req, res, next) {
  try {
    const pedido = await obtenerPedidoConAcceso(req, res);
    if (!pedido) return;
    if (pedido.Estado !== 'ENTREGADO') {
      return res.status(400).json({ mensaje: 'Este pedido todavía no ha sido entregado' });
    }

    const pool = await getPool();
    const actual = await pool.request().input('IdPedido', sql.Int, pedido.IdPedido).query('SELECT EstadoPago FROM Pedidos WHERE IdPedido = @IdPedido');
    if (actual.recordset[0]?.EstadoPago !== 'DEUDA') {
      return res.status(400).json({ mensaje: 'Este pedido no tiene una deuda pendiente' });
    }

    await pool
      .request()
      .input('IdPedido', sql.Int, pedido.IdPedido)
      .query("UPDATE Pedidos SET EstadoPago = 'PAGADO', FechaPagoDeuda = SYSUTCDATETIME() WHERE IdPedido = @IdPedido");

    await registrarAuditoria({
      idUsuario: req.usuario.idUsuario,
      accion: 'MARCAR_DEUDA_PAGADA',
      tablaAfectada: 'Pedidos',
      registroAfectadoId: String(pedido.IdPedido),
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    await notificarCliente({
      idCliente: pedido.IdCliente,
      titulo: 'Deuda saldada',
      cuerpo: `Tu deuda del pedido #${pedido.IdPedido} por S/ ${Number(pedido.Total).toFixed(2)} quedó registrada como pagada. ¡Gracias!`,
      datos: { tipo: 'DEUDA_PAGADA', idPedido: String(pedido.IdPedido) },
    });
    // Silencioso — ver comentario en notificarPersonalTienda de crearPedido.
    await notificarPersonalTienda({
      idTienda: pedido.IdTienda,
      datos: { tipo: 'DEUDA_PAGADA', idTienda: String(pedido.IdTienda), idPedido: String(pedido.IdPedido) },
    });

    return res.status(200).json({ mensaje: 'Deuda marcada como pagada' });
  } catch (err) {
    return next(err);
  }
}

/** El personal marca un pedido PENDIENTE como entregado, indicando si se
 * pagó al momento o quedó como deuda del cliente. */
async function entregarPedido(req, res, next) {
  const { pagado } = req.body;
  if (typeof pagado !== 'boolean') {
    return res.status(400).json({ mensaje: 'Debes indicar si el pedido fue pagado al momento o no.' });
  }

  try {
    const pedido = await obtenerPedidoConAcceso(req, res);
    if (!pedido) return;
    if (pedido.Estado !== 'PENDIENTE') {
      return res.status(400).json({ mensaje: 'Este pedido no está pendiente de entrega' });
    }

    const estadoPago = pagado ? 'PAGADO' : 'DEUDA';
    const pool = await getPool();
    await pool
      .request()
      .input('IdPedido', sql.Int, pedido.IdPedido)
      .input('EstadoPago', sql.VarChar(20), estadoPago)
      .input('IdUsuario', sql.Int, req.usuario.idUsuario)
      .query(`
        UPDATE Pedidos
        SET Estado = 'ENTREGADO', EstadoPago = @EstadoPago, FechaEntregaReal = SYSUTCDATETIME(), IdUsuarioEntrego = @IdUsuario
        WHERE IdPedido = @IdPedido
      `);

    await registrarAuditoria({
      idUsuario: req.usuario.idUsuario,
      accion: 'ENTREGAR_PEDIDO',
      tablaAfectada: 'Pedidos',
      registroAfectadoId: String(pedido.IdPedido),
      datosNuevos: { estadoPago },
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    await notificarCliente({
      idCliente: pedido.IdCliente,
      titulo: 'Tu pedido fue entregado',
      cuerpo: pagado
        ? `Tu pedido #${pedido.IdPedido} fue entregado y pagado. ¡Gracias por tu compra!`
        : `Tu pedido #${pedido.IdPedido} fue entregado. Queda una deuda pendiente de S/ ${Number(pedido.Total).toFixed(2)}.`,
      datos: { tipo: 'PEDIDO_ENTREGADO', idPedido: String(pedido.IdPedido) },
    });
    // Silencioso — ídem.
    await notificarPersonalTienda({
      idTienda: pedido.IdTienda,
      datos: { tipo: 'PEDIDO_ENTREGADO', idTienda: String(pedido.IdTienda), idPedido: String(pedido.IdPedido) },
    });

    return res.status(200).json({ mensaje: 'Pedido marcado como entregado' });
  } catch (err) {
    return next(err);
  }
}

module.exports = {
  crearPedido,
  crearMiPedido,
  listarPedidos,
  misPedidos,
  cancelarMiPedido,
  cancelarPedido,
  aprobarPedido,
  rechazarPedido,
  entregarPedido,
  listarDeudas,
  marcarDeudaPagada,
};
