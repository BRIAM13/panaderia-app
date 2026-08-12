const { sql, getPool } = require('../config/db');
const { registrarAuditoria } = require('../utils/auditLog');
const { tieneAccesoATienda } = require('../utils/tiendaAcceso');

function mapearFila(fila) {
  return {
    idMedioPago: fila.IdMedioPago,
    idTienda: fila.IdTienda,
    tipo: fila.Tipo,
    titular: fila.Titular,
    numeroDestino: fila.NumeroDestino,
    cci: fila.CCI,
    nombreBanco: fila.NombreBanco,
    notas: fila.Notas,
    imagenQrBase64: fila.ImagenQrBase64 || null,
    estado: !!fila.Estado,
  };
}

/**
 * Cualquier usuario autenticado puede VER los medios de pago activos de una
 * tienda (el cliente los necesita para elegir cómo pagar su deuda) — solo
 * crear/editar/desactivar está restringido a ADMIN/SUPERADMIN de esa
 * tienda.
 */
async function listarActivos(req, res, next) {
  try {
    const idTienda = Number(req.query.idTienda);
    if (!Number.isInteger(idTienda) || idTienda <= 0) {
      return res.status(400).json({ mensaje: 'Debes indicar una tienda válida.' });
    }

    const pool = await getPool();
    const result = await pool
      .request()
      .input('IdTienda', sql.Int, idTienda)
      .query('SELECT * FROM MediosPagoTienda WHERE IdTienda = @IdTienda AND Estado = 1 ORDER BY IdMedioPago');

    return res.status(200).json({ mediosPago: result.recordset.map(mapearFila) });
  } catch (err) {
    return next(err);
  }
}

/** Vista de gestión (ADMIN/SUPERADMIN de esa tienda): incluye también los
 * desactivados, para poder reactivarlos. */
async function listarPorTienda(req, res, next) {
  try {
    const idTienda = Number(req.params.idTienda);

    const acceso = await tieneAccesoATienda({ rol: req.usuario.rol, idPersona: req.usuario.idPersona, idTienda });
    if (!acceso) {
      return res.status(403).json({ mensaje: 'No tienes acceso a esta tienda' });
    }

    const pool = await getPool();
    const result = await pool
      .request()
      .input('IdTienda', sql.Int, idTienda)
      .query('SELECT * FROM MediosPagoTienda WHERE IdTienda = @IdTienda ORDER BY IdMedioPago');

    return res.status(200).json({ mediosPago: result.recordset.map(mapearFila) });
  } catch (err) {
    return next(err);
  }
}

async function crear(req, res, next) {
  try {
    const { idTienda, tipo, titular, numeroDestino, cci, nombreBanco, notas, imagenQrBase64 } = req.body;

    const acceso = await tieneAccesoATienda({ rol: req.usuario.rol, idPersona: req.usuario.idPersona, idTienda });
    if (!acceso) {
      return res.status(403).json({ mensaje: 'No tienes acceso a esta tienda' });
    }

    const pool = await getPool();
    const result = await pool
      .request()
      .input('IdTienda', sql.Int, idTienda)
      .input('Tipo', sql.VarChar(20), tipo)
      .input('Titular', sql.NVarChar(150), titular.trim().toUpperCase())
      .input('NumeroDestino', sql.VarChar(30), numeroDestino.trim())
      .input('CCI', sql.VarChar(20), cci ? cci.trim() : null)
      .input('NombreBanco', sql.NVarChar(100), nombreBanco ? nombreBanco.trim().toUpperCase() : null)
      .input('Notas', sql.NVarChar(200), notas ? notas.trim() : null)
      .input('ImagenQrBase64', sql.NVarChar(sql.MAX), imagenQrBase64 || null)
      .query(`
        INSERT INTO MediosPagoTienda (IdTienda, Tipo, Titular, NumeroDestino, CCI, NombreBanco, Notas, ImagenQrBase64)
        OUTPUT INSERTED.IdMedioPago, INSERTED.IdTienda, INSERTED.Tipo, INSERTED.Titular,
          INSERTED.NumeroDestino, INSERTED.CCI, INSERTED.NombreBanco, INSERTED.Notas,
          INSERTED.ImagenQrBase64, INSERTED.Estado
        VALUES (@IdTienda, @Tipo, @Titular, @NumeroDestino, @CCI, @NombreBanco, @Notas, @ImagenQrBase64)
      `);

    await registrarAuditoria({
      idUsuario: req.usuario.idUsuario,
      accion: 'CREAR_MEDIO_PAGO',
      tablaAfectada: 'MediosPagoTienda',
      registroAfectadoId: String(result.recordset[0].IdMedioPago),
      datosNuevos: { idTienda, tipo, titular, numeroDestino },
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    return res.status(201).json({ mensaje: 'Medio de pago registrado', medioPago: mapearFila(result.recordset[0]) });
  } catch (err) {
    return next(err);
  }
}

async function actualizar(req, res, next) {
  try {
    const { id } = req.params;
    const { titular, numeroDestino, cci, nombreBanco, notas, imagenQrBase64 } = req.body;

    const pool = await getPool();
    const existente = await pool.request().input('Id', sql.Int, id).query('SELECT IdTienda FROM MediosPagoTienda WHERE IdMedioPago = @Id');
    if (existente.recordset.length === 0) {
      return res.status(404).json({ mensaje: 'Medio de pago no encontrado' });
    }

    const acceso = await tieneAccesoATienda({
      rol: req.usuario.rol,
      idPersona: req.usuario.idPersona,
      idTienda: existente.recordset[0].IdTienda,
    });
    if (!acceso) {
      return res.status(403).json({ mensaje: 'No tienes acceso a esta tienda' });
    }

    // "OUTPUT INSERTED.*" solo tiene sentido en un INSERT — en un UPDATE
    // MariaDB lo rechaza (y aunque no lo rechazara, el shim de compatibilidad
    // solo sabe resolver OUTPUT contra el INSERT más reciente, no un UPDATE).
    // Se actualiza y se hace un SELECT aparte para devolver la fila.
    await pool
      .request()
      .input('Id', sql.Int, id)
      .input('Titular', sql.NVarChar(150), titular.trim().toUpperCase())
      .input('NumeroDestino', sql.VarChar(30), numeroDestino.trim())
      .input('CCI', sql.VarChar(20), cci ? cci.trim() : null)
      .input('NombreBanco', sql.NVarChar(100), nombreBanco ? nombreBanco.trim().toUpperCase() : null)
      .input('Notas', sql.NVarChar(200), notas ? notas.trim() : null)
      .input('ImagenQrBase64', sql.NVarChar(sql.MAX), imagenQrBase64 || null)
      .query(`
        UPDATE MediosPagoTienda
        SET Titular = @Titular, NumeroDestino = @NumeroDestino, CCI = @CCI, NombreBanco = @NombreBanco,
            Notas = @Notas, ImagenQrBase64 = @ImagenQrBase64, FechaActualizacion = SYSUTCDATETIME()
        WHERE IdMedioPago = @Id
      `);

    const result = await pool
      .request()
      .input('Id', sql.Int, id)
      .query('SELECT * FROM MediosPagoTienda WHERE IdMedioPago = @Id');

    await registrarAuditoria({
      idUsuario: req.usuario.idUsuario,
      accion: 'ACTUALIZAR_MEDIO_PAGO',
      tablaAfectada: 'MediosPagoTienda',
      registroAfectadoId: String(id),
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    return res.status(200).json({ mensaje: 'Medio de pago actualizado', medioPago: mapearFila(result.recordset[0]) });
  } catch (err) {
    return next(err);
  }
}

/** Activa/desactiva (nunca se borra, mismo patrón que TrabajadorTiendas). */
async function cambiarEstado(req, res, next) {
  try {
    const { id } = req.params;
    const { activo } = req.body;
    if (typeof activo !== 'boolean') {
      return res.status(400).json({ mensaje: 'Debes indicar el nuevo estado (activo: true/false).' });
    }

    const pool = await getPool();
    const existente = await pool.request().input('Id', sql.Int, id).query('SELECT IdTienda FROM MediosPagoTienda WHERE IdMedioPago = @Id');
    if (existente.recordset.length === 0) {
      return res.status(404).json({ mensaje: 'Medio de pago no encontrado' });
    }

    const acceso = await tieneAccesoATienda({
      rol: req.usuario.rol,
      idPersona: req.usuario.idPersona,
      idTienda: existente.recordset[0].IdTienda,
    });
    if (!acceso) {
      return res.status(403).json({ mensaje: 'No tienes acceso a esta tienda' });
    }

    await pool
      .request()
      .input('Id', sql.Int, id)
      .input('Estado', sql.Bit, activo)
      .query('UPDATE MediosPagoTienda SET Estado = @Estado, FechaActualizacion = SYSUTCDATETIME() WHERE IdMedioPago = @Id');

    await registrarAuditoria({
      idUsuario: req.usuario.idUsuario,
      accion: activo ? 'ACTIVAR_MEDIO_PAGO' : 'DESACTIVAR_MEDIO_PAGO',
      tablaAfectada: 'MediosPagoTienda',
      registroAfectadoId: String(id),
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    return res.status(200).json({ mensaje: activo ? 'Medio de pago activado' : 'Medio de pago desactivado' });
  } catch (err) {
    return next(err);
  }
}

module.exports = { listarActivos, listarPorTienda, crear, actualizar, cambiarEstado };
