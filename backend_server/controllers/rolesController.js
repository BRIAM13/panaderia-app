const { sql, getPool } = require('../config/db');

/**
 * Roles que el usuario autenticado puede ASIGNAR a otra persona al
 * crear/editar un trabajador — nunca hardcodeado en el frontend, siempre
 * leído de la tabla Roles: un ADMIN puede asignar TRABAJADOR o ADMIN (ej.
 * ascender a alguien de su confianza para que lo apoye en su tienda —
 * sigue conservando control sobre esa persona, ver
 * trabajadoresController.js → puedeModificarA), nunca SUPERADMIN. Un
 * SUPERADMIN puede asignar cualquiera de los 3. CLIENTE nunca aparece acá
 * — ese rol se asigna solo, no se "asciende" a nadie a cliente.
 *
 * Misma regla que rolesQuePuedeAsignar() en trabajadoresController.js —
 * duplicada acá porque esta responde específicamente qué mostrar en el
 * selector de rol del formulario, sin acoplar ambos controladores.
 */
async function listarAsignables(req, res, next) {
  try {
    const nombresPermitidos =
      req.usuario.rol === 'SUPERADMIN'
        ? ['TRABAJADOR', 'ADMIN', 'SUPERADMIN', 'VISITOR']
        : req.usuario.rol === 'ADMIN'
        ? ['TRABAJADOR', 'ADMIN']
        : [];

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
