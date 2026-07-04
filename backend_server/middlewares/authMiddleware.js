const { verifyAccessToken } = require('../utils/jwt');
const { tieneAccesoATienda } = require('../utils/tiendaAcceso');

function verificarToken(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ mensaje: 'Token de acceso no proporcionado' });
  }

  const token = authHeader.split(' ')[1];
  try {
    const payload = verifyAccessToken(token);
    req.usuario = payload;
    next();
  } catch (err) {
    return res.status(401).json({ mensaje: 'Token inválido o expirado' });
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
