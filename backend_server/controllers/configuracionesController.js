const { sql, getPool } = require('../config/db');
const { registrarAuditoria } = require('../utils/auditLog');

async function obtenerConfiguracion(req, res, next) {
  const { clave } = req.params;

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
      datosNuevos: { valor },
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    return res.status(200).json({ mensaje: 'Configuración actualizada correctamente' });
  } catch (err) {
    return next(err);
  }
}

module.exports = { obtenerConfiguracion, actualizarConfiguracion };
