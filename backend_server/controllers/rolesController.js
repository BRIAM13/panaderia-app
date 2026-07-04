const { sql, getPool } = require('../config/db');

/**
 * Roles que el usuario autenticado puede ASIGNAR a otra persona al
 * crear/editar un trabajador — nunca hardcodeado en el frontend, siempre
 * leído de la tabla Roles: un ADMIN solo puede asignar TRABAJADOR; un
 * SUPERADMIN puede asignar TRABAJADOR, ADMIN o SUPERADMIN. CLIENTE nunca
 * aparece acá — ese rol se asigna solo, no se "asciende" a nadie a cliente.
 */
async function listarAsignables(req, res, next) {
  try {
    const nombresPermitidos = req.usuario.rol === 'SUPERADMIN' ? ['TRABAJADOR', 'ADMIN', 'SUPERADMIN'] : ['TRABAJADOR'];

    const pool = await getPool();
    const result = await pool
      .request()
      .query(`SELECT IdRol, NombreRol FROM Roles WHERE NombreRol IN ('${nombresPermitidos.join("','")}') ORDER BY IdRol`);

    return res.status(200).json({
      roles: result.recordset.map((f) => ({ idRol: f.IdRol, nombreRol: f.NombreRol })),
    });
  } catch (err) {
    return next(err);
  }
}

module.exports = { listarAsignables };
