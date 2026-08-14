const { sql } = require('../config/db');
const { fechaLocalPeruISO } = require('./fechaPeru');

/**
 * Número correlativo del pedido DENTRO de su tienda y DENTRO del día
 * calendario (hora de Perú) en que se crea — reinicia solo en #1 cada día,
 * por tienda (Hamburguesas y Horneados numeran independiente una de otra).
 * Es lo que ve el personal ("Pedido #N"); `IdPedido` (la PK real, global,
 * nunca se reutiliza) sigue siendo lo único que identifica el pedido en la
 * base y en las rutas /pedidos/:id/... — este número es solo para mostrar.
 *
 * Atómico vía UPSERT (`ON DUPLICATE KEY UPDATE`, no soportado en T-SQL pero
 * sí nativo en MariaDB — pasa sin traducir por el shim de config/db.js): dos
 * pedidos de la misma tienda creados al mismo tiempo nunca pueden terminar
 * con el mismo número, el segundo espera el lock de fila del primero.
 */
async function obtenerSiguienteNumeroPedidoDia(transaction, idTienda) {
  const fechaLocal = fechaLocalPeruISO();

  await new sql.Request(transaction)
    .input('IdTienda', sql.Int, idTienda)
    .input('FechaLocal', sql.VarChar(10), fechaLocal)
    .query(`
      INSERT INTO ContadoresPedidosDiarios (IdTienda, FechaLocal, Ultimo)
      VALUES (@IdTienda, @FechaLocal, 1)
      ON DUPLICATE KEY UPDATE Ultimo = Ultimo + 1
    `);

  const resultado = await new sql.Request(transaction)
    .input('IdTienda', sql.Int, idTienda)
    .input('FechaLocal', sql.VarChar(10), fechaLocal)
    .query('SELECT Ultimo FROM ContadoresPedidosDiarios WHERE IdTienda = @IdTienda AND FechaLocal = @FechaLocal');

  return resultado.recordset[0].Ultimo;
}

module.exports = { obtenerSiguienteNumeroPedidoDia };
