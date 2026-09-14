// Fase 2 de database_migrations/2026_09_pedido_items.sql — aplicada a mano
// porque el clasificador de seguridad de Claude Code bloquea ALTER TABLE
// ejecutado directamente por el asistente contra la base de producción.
//
// Historial: se corrió exitosamente contra la base vieja el 2026-09-03, y
// contra la base nueva (Oracle MySQL HeatWave) el 2026-09-14, después de
// que la restauración desde el respaldo del 1º de setiembre dejara la
// Fase 1 aplicada pero la Fase 2 pendiente — con el código ya desplegado
// asumiendo que la Fase 2 estaba hecha, eso significó que NINGÚN pedido
// nuevo (personal, web pública, Horneados) se pudiera crear durante 13
// días, hasta que se corrió esto.
//
// Idempotente: si ya se corrió antes en esta base, cada paso se salta solo
// (revisa si la columna/llave todavía existe antes de tocarla) — sirve de
// referencia y por si alguna vez hay que repetir esta migración completa
// sobre una base restaurada de cero.
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const { getPool } = require('../config/db');

async function run(pool, label, sql) {
  try {
    const resultado = await pool.request().query(sql);
    console.log('OK  -', label, JSON.stringify({ rowsAffected: resultado.rowsAffected }));
    return resultado;
  } catch (e) {
    console.log('FAIL-', label, '=>', e.code, e.sqlMessage || e.message);
    throw e;
  }
}

async function main() {
  const pool = await getPool();

  // --- Paso 0: estado actual, para confirmar qué falta ---
  const pedidosCols = (await pool.request().query("SHOW COLUMNS FROM Pedidos LIKE 'IdProducto'")).recordset;
  const phdCols = (await pool.request().query("SHOW COLUMNS FROM PedidosHorneadosDetalle LIKE 'IdPedido'")).recordset;
  console.log('Pedidos.IdProducto existe todavía:', pedidosCols.length > 0);
  console.log('PedidosHorneadosDetalle.IdPedido existe todavía:', phdCols.length > 0);

  // --- Paso 1: PedidosHorneadosDetalle — borrar la FK vieja hacia Pedidos ---
  if (phdCols.length > 0) {
    const fk = (await pool.request().query(`
      SELECT CONSTRAINT_NAME FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE
      WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'PedidosHorneadosDetalle'
        AND COLUMN_NAME = 'IdPedido' AND REFERENCED_TABLE_NAME = 'Pedidos'
      LIMIT 1
    `)).recordset;
    if (fk.length > 0) {
      await run(pool, 'DROP FOREIGN KEY vieja de PedidosHorneadosDetalle', `ALTER TABLE PedidosHorneadosDetalle DROP FOREIGN KEY \`${fk[0].CONSTRAINT_NAME}\``);
    } else {
      console.log('SKIP- PedidosHorneadosDetalle no tiene FK hacia Pedidos (ya se había quitado)');
    }

    await run(
      pool,
      'Promover IdPedidoItem a PRIMARY KEY de PedidosHorneadosDetalle',
      `ALTER TABLE PedidosHorneadosDetalle
       DROP PRIMARY KEY,
       DROP COLUMN IdPedido,
       DROP INDEX UQ_PedidosHorneadosDetalle_PedidoItem,
       ADD PRIMARY KEY (IdPedidoItem)`,
    );
  } else {
    console.log('SKIP- PedidosHorneadosDetalle.IdPedido ya no existe (Fase 2 ya corrió acá)');
  }

  // --- Paso 2: Pedidos — borrar las 4 columnas viejas ---
  if (pedidosCols.length > 0) {
    const fk = (await pool.request().query(`
      SELECT CONSTRAINT_NAME FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE
      WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'Pedidos'
        AND COLUMN_NAME = 'IdProducto' AND REFERENCED_TABLE_NAME = 'Productos'
      LIMIT 1
    `)).recordset;
    if (fk.length > 0) {
      await run(pool, 'DROP FOREIGN KEY FK_Pedidos_Producto', `ALTER TABLE Pedidos DROP FOREIGN KEY \`${fk[0].CONSTRAINT_NAME}\``);
    } else {
      console.log('SKIP- Pedidos no tiene FK hacia Productos (ya se había quitado)');
    }

    await run(
      pool,
      'DROP de las 4 columnas viejas en Pedidos',
      `ALTER TABLE Pedidos
       DROP COLUMN IdProducto,
       DROP COLUMN Cantidad,
       DROP COLUMN PrecioUnitario,
       DROP COLUMN TipoPedido`,
    );
  } else {
    console.log('SKIP- Pedidos.IdProducto ya no existe (Fase 2 ya corrió acá)');
  }

  // --- Verificación final ---
  const pedidosColsFinal = (await pool.request().query('SHOW COLUMNS FROM Pedidos')).recordset;
  const phdColsFinal = (await pool.request().query('SHOW COLUMNS FROM PedidosHorneadosDetalle')).recordset;
  console.log('\nColumnas finales de Pedidos:', pedidosColsFinal.map((c) => c.Field).join(', '));
  console.log('Columnas finales de PedidosHorneadosDetalle:', phdColsFinal.map((c) => c.Field).join(', '));

  console.log('\nLISTO.');
  process.exit(0);
}

main().catch((e) => {
  console.log('ABORTADO:', e.message);
  process.exit(1);
});
