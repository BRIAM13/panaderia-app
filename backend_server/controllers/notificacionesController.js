const { sql, getPool } = require('../config/db');

/**
 * Guarda (o actualiza) el token FCM del dispositivo desde el que se llama.
 * Se sobrescribe cada vez que la app arranca — así, si el mismo token migra
 * de un usuario a otro (ej. alguien cierra sesión y otro inicia sesión en
 * el mismo celular), queda asociado al usuario correcto.
 */
async function registrarToken(req, res, next) {
  const { fcmToken, plataforma } = req.body;
  const idUsuario = req.usuario.idUsuario;

  try {
    const pool = await getPool();
    const existente = await pool
      .request()
      .input('FcmToken', sql.VarChar(300), fcmToken)
      .query('SELECT IdDispositivo FROM DispositivosNotificacion WHERE FcmToken = @FcmToken');

    if (existente.recordset.length > 0) {
      await pool
        .request()
        .input('FcmToken', sql.VarChar(300), fcmToken)
        .input('IdUsuario', sql.Int, idUsuario)
        .input('Plataforma', sql.VarChar(20), plataforma || 'ANDROID')
        .query(`
          UPDATE DispositivosNotificacion
          SET IdUsuario = @IdUsuario, Plataforma = @Plataforma, FechaActualizacion = SYSUTCDATETIME()
          WHERE FcmToken = @FcmToken
        `);
    } else {
      await pool
        .request()
        .input('IdUsuario', sql.Int, idUsuario)
        .input('FcmToken', sql.VarChar(300), fcmToken)
        .input('Plataforma', sql.VarChar(20), plataforma || 'ANDROID')
        .query(`
          INSERT INTO DispositivosNotificacion (IdUsuario, FcmToken, Plataforma)
          VALUES (@IdUsuario, @FcmToken, @Plataforma)
        `);
    }

    return res.status(200).json({ mensaje: 'Token registrado correctamente' });
  } catch (err) {
    return next(err);
  }
}

module.exports = { registrarToken };
