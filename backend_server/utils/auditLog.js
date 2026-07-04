const { sql, getPool } = require('../config/db');

async function registrarAuditoria({
  idUsuario = null,
  accion,
  tablaAfectada = null,
  registroAfectadoId = null,
  datosAnteriores = null,
  datosNuevos = null,
  ip = null,
  userAgent = null,
}) {
  try {
    const pool = await getPool();
    await pool
      .request()
      .input('IdUsuario', sql.Int, idUsuario)
      .input('Accion', sql.VarChar(50), accion)
      .input('TablaAfectada', sql.VarChar(100), tablaAfectada)
      .input('RegistroAfectadoId', sql.VarChar(50), registroAfectadoId)
      .input('DatosAnteriores', sql.NVarChar(sql.MAX), datosAnteriores ? JSON.stringify(datosAnteriores) : null)
      .input('DatosNuevos', sql.NVarChar(sql.MAX), datosNuevos ? JSON.stringify(datosNuevos) : null)
      .input('DireccionIP', sql.VarChar(50), ip)
      .input('UserAgent', sql.VarChar(300), userAgent)
      .query(`
        INSERT INTO Auditoria_Log
          (IdUsuario, Accion, TablaAfectada, RegistroAfectadoId, DatosAnteriores, DatosNuevos, DireccionIP, UserAgent)
        VALUES
          (@IdUsuario, @Accion, @TablaAfectada, @RegistroAfectadoId, @DatosAnteriores, @DatosNuevos, @DireccionIP, @UserAgent)
      `);
  } catch (err) {
    // La auditoría nunca debe tumbar el flujo principal de la petición.
    console.error('No se pudo registrar la auditoría:', err.message);
  }
}

module.exports = { registrarAuditoria };
