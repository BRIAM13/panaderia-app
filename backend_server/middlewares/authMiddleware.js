const { verifyAccessToken } = require('../utils/jwt');
const { tieneAccesoATienda } = require('../utils/tiendaAcceso');
const { getPool, sql } = require('../config/db');

/**
 * Verifica la firma/vencimiento del access token y, a propósito, además
 * consulta el Estado y Rol ACTUALES del usuario en la base de datos en cada
 * petición (no confía en el rol que trae el propio token) — así, si un
 * SUPERADMIN desactiva a un trabajador o le cambia el rol, el corte de
 * acceso es inmediato en su siguiente petición, sin esperar a que su access
 * token vigente (hasta 1h) venza solo. Es una decisión consciente de
 * cambiar algo de velocidad (una consulta liviana extra por petición) por
 * revocación instantánea de verdad.
 */
async function verificarToken(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ mensaje: 'Token de acceso no proporcionado' });
  }

  const token = authHeader.split(' ')[1];
  let payload;
  try {
    payload = verifyAccessToken(token);
  } catch (err) {
    return res.status(401).json({ mensaje: 'Token inválido o expirado' });
  }

  try {
    const pool = await getPool();
    const resultado = await pool
      .request()
      .input('IdUsuario', sql.Int, payload.idUsuario)
      .query(`
        SELECT u.Estado, r.NombreRol
        FROM Usuarios u
        INNER JOIN Roles r ON r.IdRol = u.IdRol
        WHERE u.IdUsuario = @IdUsuario
      `);

    if (resultado.recordset.length === 0 || !resultado.recordset[0].Estado) {
      return res.status(401).json({ mensaje: 'Usuario no encontrado o deshabilitado' });
    }

    const rolActual = resultado.recordset[0].NombreRol;

    // El rol guardado DENTRO del token es el que tenía al momento del login
    // (o del último refresh) — si ya no coincide con el rol actual en la
    // base de datos, alguien lo ascendió/cambió de rol mientras tenía la
    // sesión abierta (ej. cliente promovido a trabajador). No basta con
    // seguir la petición con el rol nuevo en silencio: la app del usuario
    // sigue armada en memoria con las pantallas de su rol VIEJO, así que se
    // le pide explícitamente volver a iniciar sesión para recargar todo
    // correctamente en vez de dejarlo en un estado inconsistente.
    if (rolActual !== payload.rol) {
      return res.status(401).json({
        mensaje:
          'Tu cuenta fue actualizada con nuevos permisos. Vuelve a iniciar sesión para continuar.',
        tipo: 'ROL_CAMBIADO',
      });
    }

    req.usuario = { ...payload, rol: rolActual };
    next();
  } catch (err) {
    next(err);
  }
}

function autorizarRoles(...rolesPermitidos) {
  return (req, res, next) => {
    if (!req.usuario || !rolesPermitidos.includes(req.usuario.rol)) {
      return res.status(403).json({ mensaje: 'No tiene permisos para acceder a este recurso' });
    }
    next();
  };
}

/**
 * Exige que el usuario (TRABAJADOR/ADMIN) tenga acceso vigente a la tienda
 * en cuestión — SUPERADMIN siempre pasa. `obtenerIdTiendaDesdeRequest` deja
 * a cada ruta decidir de dónde sacar el id (params, body o query).
 */
function autorizarTienda(obtenerIdTiendaDesdeRequest) {
  return async (req, res, next) => {
    try {
      const idTienda = Number(obtenerIdTiendaDesdeRequest(req));
      if (!idTienda) {
        return res.status(400).json({ mensaje: 'Debes indicar una tienda válida' });
      }
      const acceso = await tieneAccesoATienda({
        rol: req.usuario.rol,
        idPersona: req.usuario.idPersona,
        idTienda,
      });
      if (!acceso) {
        return res.status(403).json({ mensaje: 'No tienes acceso a esta tienda' });
      }
      next();
    } catch (err) {
      next(err);
    }
  };
}

module.exports = { verificarToken, autorizarRoles, autorizarTienda };
