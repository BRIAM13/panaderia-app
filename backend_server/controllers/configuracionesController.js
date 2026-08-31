const { sql, getPool } = require('../config/db');
const { registrarAuditoria } = require('../utils/auditLog');

// Configuraciones que guardan un secreto/credencial, no un ajuste operativo
// (como el precio del paquete) — ni su lectura ni su edición deben quedar
// abiertas a cualquier ADMIN/personal autenticado, solo al SUPERADMIN.
const CLAVES_SOLO_SUPERADMIN = ['API_PERU_TOKEN'];

async function obtenerConfiguracion(req, res, next) {
  const { clave } = req.params;

  if (CLAVES_SOLO_SUPERADMIN.includes(clave) && req.usuario.rol !== 'SUPERADMIN') {
    return res.status(403).json({ mensaje: 'No tienes permiso para ver esta configuración.' });
  }

  try {
    const pool = await getPool();
    const result = await pool
      .request()
      .input('Clave', sql.VarChar(50), clave)
      .query('SELECT Clave, Valor, Descripcion, FechaActualizacion FROM Configuraciones WHERE Clave = @Clave');

    if (result.recordset.length === 0) {
      return res.status(404).json({ mensaje: 'Configuración no encontrada' });
    }

    const fila = result.recordset[0];
    return res.status(200).json({
      clave: fila.Clave,
      valor: fila.Valor,
      descripcion: fila.Descripcion,
      fechaActualizacion: fila.FechaActualizacion,
    });
  } catch (err) {
    return next(err);
  }
}

async function actualizarConfiguracion(req, res, next) {
  const { clave } = req.params;
  const { valor } = req.body;

  if (CLAVES_SOLO_SUPERADMIN.includes(clave) && req.usuario.rol !== 'SUPERADMIN') {
    return res.status(403).json({ mensaje: 'No tienes permiso para modificar esta configuración.' });
  }

  try {
    const pool = await getPool();
    const result = await pool
      .request()
      .input('Clave', sql.VarChar(50), clave)
      .input('Valor', sql.NVarChar(200), String(valor).trim())
      .query(`
        UPDATE Configuraciones
        SET Valor = @Valor, FechaActualizacion = SYSUTCDATETIME()
        WHERE Clave = @Clave
      `);

    if (result.rowsAffected[0] === 0) {
      return res.status(404).json({ mensaje: 'Configuración no encontrada' });
    }

    await registrarAuditoria({
      idUsuario: req.usuario.idUsuario,
      accion: 'ACTUALIZAR_CONFIGURACION',
      tablaAfectada: 'Configuraciones',
      registroAfectadoId: clave,
      // El token de apiperu.dev es una credencial: dejarlo escrito en claro
      // en Auditoria lo volvería legible desde una tabla pensada para
      // consultarse con otros criterios (y para exportarse). Se registra QUE
      // cambió y quién lo cambió, nunca el valor.
      datosNuevos: CLAVES_SOLO_SUPERADMIN.includes(clave) ? { valor: '***' } : { valor },
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    return res.status(200).json({ mensaje: 'Configuración actualizada correctamente' });
  } catch (err) {
    return next(err);
  }
}

module.exports = { obtenerConfiguracion, actualizarConfiguracion };
