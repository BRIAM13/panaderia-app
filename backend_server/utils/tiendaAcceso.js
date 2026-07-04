const { sql, getPool } = require('../config/db');

async function obtenerIdTrabajador(idPersona) {
  const pool = await getPool();
  const r = await pool
    .request()
    .input('IdPersona', sql.Int, idPersona)
    .query('SELECT IdTrabajador FROM Trabajadores WHERE IdPersona = @IdPersona AND Estado = 1');
  return r.recordset[0]?.IdTrabajador ?? null;
}

/** Tiendas donde el trabajador tiene acceso vigente (Estado = 1). */
async function obtenerTiendasAsignadas(idTrabajador) {
  const pool = await getPool();
  const r = await pool
    .request()
    .input('IdTrabajador', sql.Int, idTrabajador)
    .query('SELECT IdTienda FROM TrabajadorTiendas WHERE IdTrabajador = @IdTrabajador AND Estado = 1');
  return r.recordset.map((f) => f.IdTienda);
}

/**
 * SUPERADMIN tiene acceso implícito a todo, sin necesitar filas en
 * TrabajadorTiendas. TRABAJADOR/ADMIN solo si tienen una fila vigente para
 * esa tienda exacta.
 */
async function tieneAccesoATienda({ rol, idPersona, idTienda }) {
  if (rol === 'SUPERADMIN') return true;

  const idTrabajador = await obtenerIdTrabajador(idPersona);
  if (!idTrabajador) return false;

  const pool = await getPool();
  const r = await pool
    .request()
    .input('IdTrabajador', sql.Int, idTrabajador)
    .input('IdTienda', sql.Int, idTienda)
    .query('SELECT 1 FROM TrabajadorTiendas WHERE IdTrabajador = @IdTrabajador AND IdTienda = @IdTienda AND Estado = 1');
  return r.recordset.length > 0;
}

module.exports = { obtenerIdTrabajador, obtenerTiendasAsignadas, tieneAccesoATienda };
