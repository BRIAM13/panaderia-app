const { sql, getPool } = require('../config/db');
const { registrarAuditoria } = require('../utils/auditLog');
const { enviarPush } = require('../services/pushService');
const { obtenerIdTrabajador, obtenerTiendasAsignadas, tieneAccesoATienda } = require('../utils/tiendaAcceso');

const MINUTOS_EXPIRACION = 30;
const CARACTERES_CODIGO = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // sin 0/O/1/I para evitar confusiones al leerlo a mano

function generarCodigoReferencia() {
  let codigo = '';
  for (let i = 0; i < 6; i += 1) {
    codigo += CARACTERES_CODIGO[Math.floor(Math.random() * CARACTERES_CODIGO.length)];
  }
  return codigo;
}

async function obtenerIdClientePropio(idPersona) {
  const pool = await getPool();
  const r = await pool
    .request()
    .input('IdPersona', sql.Int, idPersona)
    .query('SELECT IdCliente FROM Clientes WHERE IdPersona = @IdPersona AND Estado = 1');
  return r.recordset[0]?.IdCliente ?? null;
}

/**
 * Autoservicio (rol CLIENTE): sus propios pedidos entregados con deuda
 * pendiente, junto con la solicitud de pago activa (si ya generó un QR
 * para ese pedido y sigue vigente) para que el frontend no deje
 * seleccionarlo dos veces a la vez.
 */
async function misDeudas(req, res, next) {
  try {
    const idCliente = await obtenerIdClientePropio(req.usuario.idPersona);
    if (!idCliente) {
      return res.status(404).json({ mensaje: 'No tienes un perfil de cliente asociado a tu cuenta' });
    }

    const pool = await getPool();
    const result = await pool
      .request()
      .input('IdCliente', sql.Int, idCliente)
      .query(`
        SELECT pd.IdPedido, pd.IdTienda, t.Nombre AS TiendaNombre, pd.Total, pd.FechaEntregaReal,
               sp.IdSolicitudPago, sp.CodigoReferencia, sp.Estado AS EstadoSolicitud, sp.FechaExpiracion
        FROM Pedidos pd
        LEFT JOIN Tiendas t ON t.IdTienda = pd.IdTienda
        -- "OUTER APPLY" era T-SQL puro (MariaDB no lo soporta) — el
        -- equivalente portable es un LEFT JOIN contra una subconsulta
        -- correlacionada que resuelve la solicitud activa más reciente por
        -- pedido con LIMIT 1 (no TOP: así no choca con el regex del shim de
        -- compatibilidad, que solo traduce TOP en el SELECT más externo).
        LEFT JOIN SolicitudesPago sp ON sp.IdSolicitudPago = (
          SELECT s.IdSolicitudPago
          FROM SolicitudPagoPedidos spp
          INNER JOIN SolicitudesPago s ON s.IdSolicitudPago = spp.IdSolicitudPago
          WHERE spp.IdPedido = pd.IdPedido AND s.Estado IN ('GENERADO', 'REPORTADO')
          ORDER BY s.IdSolicitudPago DESC
          LIMIT 1
        )
        WHERE pd.IdCliente = @IdCliente AND pd.Estado = 'ENTREGADO' AND pd.EstadoPago = 'DEUDA'
        ORDER BY pd.FechaEntregaReal ASC
      `);

    const deudas = result.recordset.map((fila) => ({
      idPedido: fila.IdPedido,
      idTienda: fila.IdTienda,
      tienda: fila.TiendaNombre,
      total: fila.Total,
      fechaEntregaReal: fila.FechaEntregaReal,
      solicitudPagoActiva: fila.IdSolicitudPago
        ? {
            idSolicitudPago: fila.IdSolicitudPago,
            codigoReferencia: fila.CodigoReferencia,
            estado: fila.EstadoSolicitud,
            fechaExpiracion: fila.FechaExpiracion,
          }
        : null,
    }));

    return res.status(200).json({ deudas });
  } catch (err) {
    return next(err);
  }
}

/**
 * Autoservicio (rol CLIENTE): junta 1+ deudas propias en una sola solicitud
 * de pago con un código de referencia único (la "nota" que el cliente debe
 * escribir al transferir/yapear) — de un solo uso: una vez REPORTADA o
 * CONFIRMADA deja de servir para un pago nuevo, hay que generar otra.
 */
async function crear(req, res, next) {
  const { idMedioPago, idsPedidos } = req.body;

  const pool = await getPool();
  const transaction = new sql.Transaction(pool);

  try {
    await transaction.begin();

    const idCliente = await obtenerIdClientePropio(req.usuario.idPersona);
    if (!idCliente) {
      await transaction.rollback();
      return res.status(404).json({ mensaje: 'No tienes un perfil de cliente asociado a tu cuenta' });
    }

    const medioResult = await new sql.Request(transaction)
      .input('IdMedioPago', sql.Int, idMedioPago)
      .query('SELECT * FROM MediosPagoTienda WHERE IdMedioPago = @IdMedioPago AND Estado = 1');
    if (medioResult.recordset.length === 0) {
      await transaction.rollback();
      return res.status(404).json({ mensaje: 'Medio de pago no disponible' });
    }
    const medioPago = medioResult.recordset[0];

    const placeholders = idsPedidos.map((_, i) => `@Pedido${i}`).join(',');
    const solicitudPedidos = new sql.Request(transaction);
    idsPedidos.forEach((id, i) => solicitudPedidos.input(`Pedido${i}`, sql.Int, id));
    const pedidosResult = await solicitudPedidos
      .input('IdCliente', sql.Int, idCliente)
      .query(`
        SELECT pd.IdPedido, pd.IdTienda, pd.Total,
               (SELECT COUNT(*) FROM SolicitudPagoPedidos spp
                INNER JOIN SolicitudesPago s ON s.IdSolicitudPago = spp.IdSolicitudPago
                WHERE spp.IdPedido = pd.IdPedido AND s.Estado IN ('GENERADO', 'REPORTADO')) AS SolicitudesActivas
        FROM Pedidos pd
        WHERE pd.IdPedido IN (${placeholders}) AND pd.IdCliente = @IdCliente AND pd.Estado = 'ENTREGADO' AND pd.EstadoPago = 'DEUDA'
      `);

    if (pedidosResult.recordset.length !== idsPedidos.length) {
      await transaction.rollback();
      return res.status(400).json({ mensaje: 'Uno o más pedidos seleccionados no son deudas tuyas válidas.' });
    }
    if (pedidosResult.recordset.some((p) => p.SolicitudesActivas > 0)) {
      await transaction.rollback();
      return res.status(400).json({ mensaje: 'Uno o más pedidos ya tienen una solicitud de pago activa. Repórtala o espera a que expire.' });
    }
    if (pedidosResult.recordset.some((p) => p.IdTienda !== medioPago.IdTienda)) {
      await transaction.rollback();
      return res.status(400).json({ mensaje: 'Todos los pedidos deben ser de la misma tienda que el medio de pago elegido.' });
    }

    const montoTotal = pedidosResult.recordset.reduce((acc, p) => acc + Number(p.Total), 0);

    let codigoReferencia;
    let insertResult;
    for (let intento = 0; intento < 5; intento += 1) {
      codigoReferencia = generarCodigoReferencia();
      try {
        insertResult = await new sql.Request(transaction)
          .input('IdCliente', sql.Int, idCliente)
          .input('IdMedioPago', sql.Int, idMedioPago)
          .input('CodigoReferencia', sql.VarChar(10), codigoReferencia)
          .input('MontoTotal', sql.Decimal(10, 2), montoTotal)
          .input('FechaExpiracion', sql.DateTime2, new Date(Date.now() + MINUTOS_EXPIRACION * 60 * 1000))
          .query(`
            INSERT INTO SolicitudesPago (IdCliente, IdMedioPago, CodigoReferencia, MontoTotal, FechaExpiracion)
            OUTPUT INSERTED.IdSolicitudPago, INSERTED.FechaExpiracion
            VALUES (@IdCliente, @IdMedioPago, @CodigoReferencia, @MontoTotal, @FechaExpiracion)
          `);
        break;
      } catch (err) {
        if (!String(err.message).includes('UQ_SolicitudesPago_CodigoReferencia') || intento === 4) throw err;
      }
    }

    const idSolicitudPago = insertResult.recordset[0].IdSolicitudPago;

    for (const idPedido of idsPedidos) {
      await new sql.Request(transaction)
        .input('IdSolicitudPago', sql.Int, idSolicitudPago)
        .input('IdPedido', sql.Int, idPedido)
        .query('INSERT INTO SolicitudPagoPedidos (IdSolicitudPago, IdPedido) VALUES (@IdSolicitudPago, @IdPedido)');
    }

    await transaction.commit();

    await registrarAuditoria({
      idUsuario: req.usuario.idUsuario,
      accion: 'CREAR_SOLICITUD_PAGO',
      tablaAfectada: 'SolicitudesPago',
      registroAfectadoId: String(idSolicitudPago),
      datosNuevos: { idMedioPago, idsPedidos, montoTotal, codigoReferencia },
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    return res.status(201).json({
      mensaje: 'Solicitud de pago generada',
      idSolicitudPago,
      codigoReferencia,
      montoTotal,
      fechaExpiracion: insertResult.recordset[0].FechaExpiracion,
      medioPago: {
        idMedioPago: medioPago.IdMedioPago,
        tipo: medioPago.Tipo,
        titular: medioPago.Titular,
        numeroDestino: medioPago.NumeroDestino,
        cci: medioPago.CCI,
        nombreBanco: medioPago.NombreBanco,
        notas: medioPago.Notas,
        imagenQrBase64: medioPago.ImagenQrBase64 || null,
      },
    });
  } catch (err) {
    await transaction.rollback();
    return next(err);
  }
}

/** El cliente marca que ya realizó la transferencia/yapeo — avisa al
 * personal de la tienda para que revise y confirme. */
async function reportar(req, res, next) {
  try {
    const { id } = req.params;
    const idCliente = await obtenerIdClientePropio(req.usuario.idPersona);
    if (!idCliente) {
      return res.status(404).json({ mensaje: 'No tienes un perfil de cliente asociado a tu cuenta' });
    }

    const pool = await getPool();
    const result = await pool
      .request()
      .input('Id', sql.Int, id)
      .input('IdCliente', sql.Int, idCliente)
      .query('SELECT IdSolicitudPago, Estado, FechaExpiracion, MontoTotal FROM SolicitudesPago WHERE IdSolicitudPago = @Id AND IdCliente = @IdCliente');

    if (result.recordset.length === 0) {
      return res.status(404).json({ mensaje: 'Solicitud de pago no encontrada' });
    }
    const solicitud = result.recordset[0];

    if (new Date(solicitud.FechaExpiracion) < new Date() && solicitud.Estado === 'GENERADO') {
      await pool.request().input('Id', sql.Int, id).query("UPDATE SolicitudesPago SET Estado = 'EXPIRADO' WHERE IdSolicitudPago = @Id");
      return res.status(400).json({ mensaje: 'Esta solicitud de pago expiró. Genera una nueva.' });
    }
    if (solicitud.Estado !== 'GENERADO') {
      return res.status(400).json({ mensaje: 'Esta solicitud ya no está pendiente de reporte.' });
    }

    await pool
      .request()
      .input('Id', sql.Int, id)
      .query("UPDATE SolicitudesPago SET Estado = 'REPORTADO', FechaReporte = SYSUTCDATETIME() WHERE IdSolicitudPago = @Id");

    await registrarAuditoria({
      idUsuario: req.usuario.idUsuario,
      accion: 'REPORTAR_PAGO',
      tablaAfectada: 'SolicitudesPago',
      registroAfectadoId: String(id),
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    // El estado ya quedó guardado arriba — si algo falla desde acá en
    // adelante (la notificación es un extra), no debe hacer que el cliente
    // vea un error cuando su reporte en realidad sí se registró.
    try {
      const clienteInfo = await pool
        .request()
        .input('IdCliente', sql.Int, idCliente)
        .input('Id', sql.Int, id)
        .query(`
          SELECT c.DescripcionNegocio, p.Nombres, p.ApellidoPaterno, pd.IdTienda
          FROM Clientes c
          INNER JOIN Personas p ON p.IdPersona = c.IdPersona
          INNER JOIN SolicitudPagoPedidos spp ON spp.IdSolicitudPago = @Id
          INNER JOIN Pedidos pd ON pd.IdPedido = spp.IdPedido
          WHERE c.IdCliente = @IdCliente
        `);
      const info = clienteInfo.recordset[0];
      if (info) {
        const nombreCliente = [info.Nombres, info.ApellidoPaterno].filter(Boolean).join(' ');
        await notificarPersonalDeTienda(info.IdTienda, {
          titulo: 'Pago reportado por el cliente',
          cuerpo: `${info.DescripcionNegocio || nombreCliente} reportó un pago de S/ ${Number(solicitud.MontoTotal).toFixed(2)}. Revisa y confirma.`,
          datos: { tipo: 'PAGO_REPORTADO', idSolicitudPago: String(id) },
        });
      }
    } catch (_) {
      // Silencioso a propósito, ver comentario arriba.
    }

    return res.status(200).json({ mensaje: 'Pago reportado — el personal lo confirmará pronto' });
  } catch (err) {
    return next(err);
  }
}

/** Trae una solicitud de pago + valida que quien llama tenga acceso a la
 * tienda de los pedidos que cubre (todos comparten tienda, ver crear()). */
async function obtenerSolicitudConAcceso(req, res) {
  const { id } = req.params;
  const pool = await getPool();
  const result = await pool
    .request()
    .input('Id', sql.Int, id)
    .query(`
      SELECT TOP 1 s.IdSolicitudPago, s.IdCliente, s.Estado, s.MontoTotal, pd.IdTienda
      FROM SolicitudesPago s
      INNER JOIN SolicitudPagoPedidos spp ON spp.IdSolicitudPago = s.IdSolicitudPago
      INNER JOIN Pedidos pd ON pd.IdPedido = spp.IdPedido
      WHERE s.IdSolicitudPago = @Id
    `);

  if (result.recordset.length === 0) {
    res.status(404).json({ mensaje: 'Solicitud de pago no encontrada' });
    return null;
  }
  const solicitud = result.recordset[0];

  const acceso = await tieneAccesoATienda({ rol: req.usuario.rol, idPersona: req.usuario.idPersona, idTienda: solicitud.IdTienda });
  if (!acceso) {
    res.status(403).json({ mensaje: 'No tienes acceso a esta tienda' });
    return null;
  }

  return solicitud;
}

/** El personal confirma un pago reportado (o ya verificado antes del
 * reporte) — marca TODOS los pedidos que cubre como PAGADO de una vez. */
async function confirmar(req, res, next) {
  try {
    const solicitud = await obtenerSolicitudConAcceso(req, res);
    if (!solicitud) return;

    if (!['GENERADO', 'REPORTADO'].includes(solicitud.Estado)) {
      return res.status(400).json({ mensaje: 'Esta solicitud ya no se puede confirmar.' });
    }

    const pool = await getPool();
    await pool
      .request()
      .input('Id', sql.Int, solicitud.IdSolicitudPago)
      .query("UPDATE SolicitudesPago SET Estado = 'CONFIRMADO', FechaConfirmacion = SYSUTCDATETIME() WHERE IdSolicitudPago = @Id");

    await pool
      .request()
      .input('Id', sql.Int, solicitud.IdSolicitudPago)
      // "UPDATE <alias> SET ... FROM <tabla> JOIN ..." es sintaxis de T-SQL
      // — MariaDB exige el JOIN pegado directo al UPDATE, sin FROM aparte.
      .query(`
        UPDATE Pedidos pd
        INNER JOIN SolicitudPagoPedidos spp ON spp.IdPedido = pd.IdPedido
        SET pd.EstadoPago = 'PAGADO', pd.FechaPagoDeuda = SYSUTCDATETIME()
        WHERE spp.IdSolicitudPago = @Id
      `);

    await registrarAuditoria({
      idUsuario: req.usuario.idUsuario,
      accion: 'CONFIRMAR_PAGO',
      tablaAfectada: 'SolicitudesPago',
      registroAfectadoId: String(solicitud.IdSolicitudPago),
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    await notificarCliente(solicitud.IdCliente, {
      titulo: 'Pago confirmado',
      cuerpo: `Tu pago de S/ ${Number(solicitud.MontoTotal).toFixed(2)} quedó registrado como pagado. ¡Gracias!`,
      datos: { tipo: 'DEUDA_PAGADA', idSolicitudPago: String(solicitud.IdSolicitudPago) },
    });

    return res.status(200).json({ mensaje: 'Pago confirmado — las deudas quedaron saldadas' });
  } catch (err) {
    return next(err);
  }
}

/** El personal rechaza un pago reportado (ej. nunca llegó la plata) — el
 * cliente deberá generar una nueva solicitud si de verdad quiere pagar. */
async function rechazar(req, res, next) {
  try {
    const solicitud = await obtenerSolicitudConAcceso(req, res);
    if (!solicitud) return;

    if (!['GENERADO', 'REPORTADO'].includes(solicitud.Estado)) {
      return res.status(400).json({ mensaje: 'Esta solicitud ya no se puede rechazar.' });
    }

    const pool = await getPool();
    await pool
      .request()
      .input('Id', sql.Int, solicitud.IdSolicitudPago)
      .query("UPDATE SolicitudesPago SET Estado = 'CANCELADO' WHERE IdSolicitudPago = @Id");

    await registrarAuditoria({
      idUsuario: req.usuario.idUsuario,
      accion: 'RECHAZAR_PAGO',
      tablaAfectada: 'SolicitudesPago',
      registroAfectadoId: String(solicitud.IdSolicitudPago),
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    await notificarCliente(solicitud.IdCliente, {
      titulo: 'No pudimos confirmar tu pago',
      cuerpo: 'No encontramos tu transferencia/yapeo. Genera una nueva solicitud de pago o contáctanos.',
      datos: { tipo: 'PAGO_RECHAZADO', idSolicitudPago: String(solicitud.IdSolicitudPago) },
    });

    return res.status(200).json({ mensaje: 'Pago rechazado' });
  } catch (err) {
    return next(err);
  }
}

async function notificarCliente(idCliente, { titulo, cuerpo, datos }) {
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
    const tokens = result.recordset.map((f) => f.FcmToken);
    if (tokens.length === 0) return;
    const { tokensInvalidos } = await enviarPush({ tokens, titulo, cuerpo, datos });
    if (tokensInvalidos.length > 0) {
      await pool
        .request()
        .query(`DELETE FROM DispositivosNotificacion WHERE FcmToken IN (${tokensInvalidos.map((t) => `'${t.replace(/'/g, "''")}'`).join(',')})`);
    }
  } catch (_) {
    // Silencioso: el cambio de estado ya se guardó, notificar es un extra.
  }
}

/** Vista de personal: solicitudes de pago reportadas (o generadas) que
 * cubren pedidos de sus tiendas asignadas — para revisarlas y confirmar. */
async function listarPendientes(req, res, next) {
  try {
    const pool = await getPool();
    let filtroTienda = '';

    if (req.usuario.rol !== 'SUPERADMIN') {
      const idTrabajador = await obtenerIdTrabajador(req.usuario.idPersona);
      const idsTiendas = idTrabajador ? await obtenerTiendasAsignadas(idTrabajador) : [];
      if (idsTiendas.length === 0) {
        return res.status(200).json({ solicitudes: [] });
      }
      filtroTienda = `AND pd.IdTienda IN (${idsTiendas.join(',')})`;
    }

    const result = await pool.request().query(`
      SELECT DISTINCT s.IdSolicitudPago, s.CodigoReferencia, s.MontoTotal, s.Estado, s.FechaCreacion, s.FechaReporte,
             c.IdCliente, c.DescripcionNegocio, per.DNI, per.Nombres, per.ApellidoPaterno, per.ApellidoMaterno,
             mp.Tipo AS MedioPagoTipo, mp.Titular AS MedioPagoTitular, mp.NumeroDestino AS MedioPagoNumero
      FROM SolicitudesPago s
      INNER JOIN Clientes c ON c.IdCliente = s.IdCliente
      INNER JOIN Personas per ON per.IdPersona = c.IdPersona
      INNER JOIN MediosPagoTienda mp ON mp.IdMedioPago = s.IdMedioPago
      INNER JOIN SolicitudPagoPedidos spp ON spp.IdSolicitudPago = s.IdSolicitudPago
      INNER JOIN Pedidos pd ON pd.IdPedido = spp.IdPedido
      WHERE s.Estado IN ('GENERADO', 'REPORTADO') ${filtroTienda}
      ORDER BY s.FechaCreacion ASC
    `);

    const solicitudes = result.recordset.map((fila) => ({
      idSolicitudPago: fila.IdSolicitudPago,
      codigoReferencia: fila.CodigoReferencia,
      montoTotal: fila.MontoTotal,
      estado: fila.Estado,
      fechaCreacion: fila.FechaCreacion,
      fechaReporte: fila.FechaReporte,
      cliente: {
        dni: fila.DNI,
        nombres: fila.Nombres,
        apellidoPaterno: fila.ApellidoPaterno,
        apellidoMaterno: fila.ApellidoMaterno,
        descripcionNegocio: fila.DescripcionNegocio,
      },
      medioPago: {
        tipo: fila.MedioPagoTipo,
        titular: fila.MedioPagoTitular,
        numeroDestino: fila.MedioPagoNumero,
      },
    }));

    return res.status(200).json({ solicitudes });
  } catch (err) {
    return next(err);
  }
}

async function notificarPersonalDeTienda(idTienda, { titulo, cuerpo, datos }) {
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
    const tokens = result.recordset.map((f) => f.FcmToken);
    if (tokens.length === 0) return;
    const { tokensInvalidos } = await enviarPush({ tokens, titulo, cuerpo, datos });
    if (tokensInvalidos.length > 0) {
      await pool
        .request()
        .query(`DELETE FROM DispositivosNotificacion WHERE FcmToken IN (${tokensInvalidos.map((t) => `'${t.replace(/'/g, "''")}'`).join(',')})`);
    }
  } catch (_) {
    // Silencioso: la notificación es un extra, el reporte ya quedó guardado.
  }
}

module.exports = { misDeudas, crear, reportar, confirmar, rechazar, listarPendientes };
