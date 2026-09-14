const { sql, getPool } = require('../config/db');
const { registrarAuditoria } = require('../utils/auditLog');
const { obtenerIdTrabajador, obtenerTiendasAsignadas, tieneAccesoATienda } = require('../utils/tiendaAcceso');
const {
  ESTADO_VERIFICANDO,
  resolverPagoAdelanto,
  describirResultadoPago,
} = require('../utils/pagoAdelanto');
const {
  obtenerPedidoConAcceso,
  mapearFilaAjuste,
  notificarCliente,
  notificarPersonalTienda,
} = require('./pedidosController');

/**
 * El lado del PERSONAL del pago por adelantado con Yape (el lado del
 * cliente vive en publicoController.js, `crearPedidoPublico`).
 *
 * El pedido llega con un código de operación y un monto DECLARADO por el
 * cliente. Alguien del negocio abre su Yape, busca ese código, ve cuánto
 * llegó de verdad y escribe ESE número acá. De ahí sale todo lo demás —
 * ver `utils/pagoAdelanto.js`, donde vive el cálculo puro.
 *
 * A propósito el personal NO elige el resultado de una lista de tres
 * opciones: escribe un monto y el sistema deduce si fue justo, de menos o
 * de más. Un menú dejaría marcar "pagado" sobre un pago incompleto, que es
 * exactamente el error que esta pantalla existe para evitar.
 */
async function confirmarPagoAdelanto(req, res, next) {
  const montoConfirmado = Number(req.body?.montoConfirmado);
  if (!Number.isFinite(montoConfirmado) || montoConfirmado <= 0) {
    return res.status(400).json({ mensaje: 'Indica el monto que llegó realmente a la cuenta de Yape.' });
  }

  const pool = await getPool();
  const transaction = new sql.Transaction(pool);

  try {
    // Mismo candado de tienda que aprobar/rechazar/entregar: la ruta es
    // /:id de pedido, así que primero hay que resolver de qué tienda es.
    const pedido = await obtenerPedidoConAcceso(req, res);
    if (!pedido) return;

    if (pedido.EstadoPagoAdelanto !== ESTADO_VERIFICANDO) {
      return res.status(400).json({
        mensaje:
          pedido.EstadoPagoAdelanto === 'NO_APLICA'
            ? 'Este pedido no se pagó por adelantado.'
            : 'El pago de este pedido ya fue verificado.',
      });
    }

    const total = Number(pedido.Total);
    const { estadoPagoAdelanto, ajuste } = resolverPagoAdelanto(total, montoConfirmado);

    // El cambio de estado del pedido y la creación del ajuste van en la
    // MISMA transacción: un pedido marcado DEUDA_PARCIAL sin su fila de
    // AjustesPago sería una deuda que nadie puede ver ni cobrar, y un
    // ajuste sin su pedido confirmado sería un reclamo huérfano.
    await transaction.begin();

    await new sql.Request(transaction)
      .input('IdPedido', sql.Int, pedido.IdPedido)
      .input('EstadoPagoAdelanto', sql.VarChar(20), estadoPagoAdelanto)
      .input('MontoConfirmadoStaff', sql.Decimal(10, 2), montoConfirmado)
      .input('IdUsuario', sql.Int, req.usuario.idUsuario)
      .query(`
        UPDATE Pedidos
        SET Estado = 'CONFIRMADO',
            EstadoPagoAdelanto = @EstadoPagoAdelanto,
            MontoConfirmadoStaff = @MontoConfirmadoStaff,
            IdUsuarioAprobo = @IdUsuario,
            FechaAprobacion = SYSUTCDATETIME()
        WHERE IdPedido = @IdPedido
      `);

    let idAjuste = null;
    if (ajuste) {
      // `FechaCreacion` explícita aunque la columna tenga DEFAULT
      // CURRENT_TIMESTAMP: el default de MariaDB guarda la hora del
      // servidor de base, y todo el resto del sistema guarda UTC vía
      // SYSUTCDATETIME() (que el shim traduce a UTC_TIMESTAMP(3)). Mezclar
      // los dos husos en la misma tabla haría imposible ordenar por fecha.
      const insertAjuste = await new sql.Request(transaction)
        .input('IdPedido', sql.Int, pedido.IdPedido)
        .input('Tipo', sql.VarChar(10), ajuste.tipo)
        .input('Monto', sql.Decimal(10, 2), ajuste.monto)
        .query(`
          INSERT INTO AjustesPago (IdPedido, Tipo, Monto, Estado, FechaCreacion)
          OUTPUT INSERTED.IdAjuste
          VALUES (@IdPedido, @Tipo, @Monto, 'PENDIENTE', SYSUTCDATETIME())
        `);
      idAjuste = insertAjuste.recordset[0].IdAjuste;
    }

    await transaction.commit();

    const resumen = describirResultadoPago({ estadoPagoAdelanto, ajuste });

    await registrarAuditoria({
      idUsuario: req.usuario.idUsuario,
      accion: 'CONFIRMAR_PAGO_ADELANTO',
      tablaAfectada: 'Pedidos',
      registroAfectadoId: String(pedido.IdPedido),
      datosNuevos: {
        total,
        montoConfirmado,
        estadoPagoAdelanto,
        ajuste: ajuste ? { ...ajuste, idAjuste } : null,
      },
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    // Al cliente se le cuenta exactamente lo mismo que ve el personal — con
    // la diferencia a favor o en contra bien dicha, para que nadie se
    // entere del saldo recién al llegar al mostrador.
    await notificarCliente({
      idCliente: pedido.IdCliente,
      titulo: 'Confirmamos tu pago',
      cuerpo: mensajeParaCliente(pedido.NumeroPedidoDia, estadoPagoAdelanto, ajuste),
      datos: { tipo: 'PAGO_ADELANTO_CONFIRMADO', idPedido: String(pedido.IdPedido) },
    });
    // Silencioso (sin título/cuerpo): solo refresca la pantalla de Pedidos
    // de los demás dispositivos del personal — ver notificarPersonalTienda.
    await notificarPersonalTienda({
      idTienda: pedido.IdTienda,
      datos: {
        tipo: 'PAGO_ADELANTO_CONFIRMADO',
        idTienda: String(pedido.IdTienda),
        idPedido: String(pedido.IdPedido),
      },
    });

    return res.status(200).json({
      mensaje: resumen,
      idPedido: pedido.IdPedido,
      estado: 'CONFIRMADO',
      estadoPagoAdelanto,
      total,
      montoConfirmado,
      ajuste: ajuste ? { idAjuste, tipo: ajuste.tipo, monto: ajuste.monto, estado: 'PENDIENTE' } : null,
    });
  } catch (err) {
    await transaction.rollback();
    return next(err);
  }
}

function mensajeParaCliente(numeroPedidoDia, estadoPagoAdelanto, ajuste) {
  switch (estadoPagoAdelanto) {
    case 'DEUDA_PARCIAL':
      return `Recibimos tu pago del pedido #${numeroPedidoDia}, pero faltaron S/ ${ajuste.monto.toFixed(2)}. Los completas al recoger.`;
    case 'VUELTO_PENDIENTE':
      return `Recibimos tu pago del pedido #${numeroPedidoDia}. Pagaste S/ ${ajuste.monto.toFixed(2)} de más y te los devolvemos al recoger.`;
    default:
      return `Tu pago del pedido #${numeroPedidoDia} quedó verificado. Ya lo estamos preparando.`;
  }
}

/**
 * Saldos y vueltos pendientes de las tiendas del personal.
 *
 * Vive aparte de la lista de pedidos por una razón concreta: un ajuste
 * puede sobrevivir a su pedido. La pantalla de Pedidos oculta lo ya
 * finalizado (entregado/rechazado/cancelado), así que un vuelto que no se
 * alcanzó a devolver el día de la entrega desaparecería de la vista justo
 * cuando más falta hace recordarlo.
 *
 * Mismo candado que listarPedidos/listarDeudas: SUPERADMIN ve cualquier
 * tienda; el resto, solo las que tenga asignadas — y sin acceso devuelve
 * lista vacía, no 403, para que la pantalla no tenga que distinguir "sin
 * acceso" de "sin ajustes".
 */
async function listarAjustesPendientes(req, res, next) {
  try {
    const idTienda = Number(req.query.idTienda);
    if (!idTienda) {
      return res.status(400).json({ mensaje: 'Debes indicar una tienda válida.' });
    }

    if (req.usuario.rol !== 'SUPERADMIN') {
      const idTrabajador = await obtenerIdTrabajador(req.usuario.idPersona);
      const idsTiendas = idTrabajador ? await obtenerTiendasAsignadas(idTrabajador) : [];
      if (!idsTiendas.includes(idTienda)) {
        return res.status(200).json({ ajustes: [] });
      }
    }

    const pool = await getPool();
    const result = await pool
      .request()
      .input('IdTienda', sql.Int, idTienda)
      .query(`
        SELECT a.IdAjuste, a.IdPedido, a.Tipo, a.Monto, a.Estado, a.Notas,
               a.FechaCreacion, a.FechaResolucion,
               pd.NumeroPedidoDia, pd.Total, pd.Estado AS EstadoPedido,
               pd.CodigoOperacionYape, pd.MontoConfirmadoStaff,
               per.DNI AS ClienteDni, per.Nombres AS ClienteNombres,
               per.ApellidoPaterno AS ClienteApellidoPaterno, per.ApellidoMaterno AS ClienteApellidoMaterno,
               c.DescripcionNegocio AS ClienteDescripcionNegocio
        FROM AjustesPago a
        INNER JOIN Pedidos pd ON pd.IdPedido = a.IdPedido
        INNER JOIN Clientes c ON c.IdCliente = pd.IdCliente
        INNER JOIN Personas per ON per.IdPersona = c.IdPersona
        WHERE a.Estado = 'PENDIENTE' AND pd.IdTienda = @IdTienda
        ORDER BY a.FechaCreacion ASC
      `);

    return res.status(200).json({
      ajustes: result.recordset.map((fila) => ({
        ...mapearFilaAjuste(fila),
        numeroPedidoDia: fila.NumeroPedidoDia,
        totalPedido: Number(fila.Total),
        estadoPedido: fila.EstadoPedido,
        codigoOperacionYape: fila.CodigoOperacionYape ?? null,
        montoConfirmadoStaff: fila.MontoConfirmadoStaff != null ? Number(fila.MontoConfirmadoStaff) : null,
        cliente: {
          dni: fila.ClienteDni,
          nombres: fila.ClienteNombres,
          apellidoPaterno: fila.ClienteApellidoPaterno,
          apellidoMaterno: fila.ClienteApellidoMaterno,
          descripcionNegocio: fila.ClienteDescripcionNegocio,
        },
      })),
    });
  } catch (err) {
    return next(err);
  }
}

/**
 * El personal marca un saldo/vuelto como saldado.
 *
 * A propósito NO está pegado a "marcar entregado": lo normal es resolverlo
 * al recoger, pero el dueño puede devolver un vuelto por Yape el mismo día
 * o cobrar un saldo la semana siguiente. Atar las dos acciones obligaría a
 * mentir en una para poder hacer la otra.
 */
async function resolverAjustePago(req, res, next) {
  try {
    const { id } = req.params;
    const notas = req.body?.notas;
    if (notas !== undefined && notas !== null && String(notas).trim().length > 300) {
      return res.status(400).json({ mensaje: 'La nota es demasiado larga.' });
    }

    const pool = await getPool();
    const result = await pool
      .request()
      .input('IdAjuste', sql.Int, id)
      .query(`
        SELECT a.IdAjuste, a.IdPedido, a.Tipo, a.Monto, a.Estado, pd.IdTienda, pd.IdCliente, pd.NumeroPedidoDia
        FROM AjustesPago a
        INNER JOIN Pedidos pd ON pd.IdPedido = a.IdPedido
        WHERE a.IdAjuste = @IdAjuste
      `);

    if (result.recordset.length === 0) {
      return res.status(404).json({ mensaje: 'Ajuste de pago no encontrado' });
    }
    const ajuste = result.recordset[0];

    const acceso = await tieneAccesoATienda({
      rol: req.usuario.rol,
      idPersona: req.usuario.idPersona,
      idTienda: ajuste.IdTienda,
    });
    if (!acceso) {
      return res.status(403).json({ mensaje: 'No tienes acceso a esta tienda' });
    }

    if (ajuste.Estado !== 'PENDIENTE') {
      return res.status(400).json({ mensaje: 'Este ajuste ya estaba resuelto.' });
    }

    await pool
      .request()
      .input('IdAjuste', sql.Int, ajuste.IdAjuste)
      .input('IdUsuario', sql.Int, req.usuario.idUsuario)
      .input('Notas', sql.NVarChar(300), notas ? String(notas).trim() : null)
      .query(`
        UPDATE AjustesPago
        SET Estado = 'RESUELTO', IdUsuarioResolvio = @IdUsuario,
            FechaResolucion = SYSUTCDATETIME(), Notas = @Notas
        WHERE IdAjuste = @IdAjuste
      `);

    await registrarAuditoria({
      idUsuario: req.usuario.idUsuario,
      accion: 'RESOLVER_AJUSTE_PAGO',
      tablaAfectada: 'AjustesPago',
      registroAfectadoId: String(ajuste.IdAjuste),
      datosNuevos: { tipo: ajuste.Tipo, monto: Number(ajuste.Monto), notas: notas ?? null },
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    await notificarCliente({
      idCliente: ajuste.IdCliente,
      titulo: ajuste.Tipo === 'VUELTO' ? 'Te devolvimos tu vuelto' : 'Saldo cobrado',
      cuerpo:
        ajuste.Tipo === 'VUELTO'
          ? `El vuelto de S/ ${Number(ajuste.Monto).toFixed(2)} de tu pedido #${ajuste.NumeroPedidoDia} quedó devuelto.`
          : `El saldo de S/ ${Number(ajuste.Monto).toFixed(2)} de tu pedido #${ajuste.NumeroPedidoDia} quedó pagado. ¡Gracias!`,
      datos: { tipo: 'AJUSTE_PAGO_RESUELTO', idPedido: String(ajuste.IdPedido) },
    });
    // Silencioso — ídem.
    await notificarPersonalTienda({
      idTienda: ajuste.IdTienda,
      datos: {
        tipo: 'AJUSTE_PAGO_RESUELTO',
        idTienda: String(ajuste.IdTienda),
        idPedido: String(ajuste.IdPedido),
      },
    });

    return res.status(200).json({
      mensaje: ajuste.Tipo === 'VUELTO' ? 'Vuelto marcado como devuelto' : 'Saldo marcado como cobrado',
    });
  } catch (err) {
    return next(err);
  }
}

module.exports = { confirmarPagoAdelanto, listarAjustesPendientes, resolverAjustePago };
