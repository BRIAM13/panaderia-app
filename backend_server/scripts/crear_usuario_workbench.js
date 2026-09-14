// Crea (o resetea) un usuario MySQL dedicado para conectarse desde
// MySQL Workbench u otro cliente de escritorio, con permisos completos
// sobre la base de la panadería. Separado de `superAdmin` a propósito:
// una contraseña simple, fácil de escribir sin margen de error, en vez
// de compartir la cuenta de administración real.
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const { getPool } = require('../config/db');

const USUARIO = 'briam_workbench';
const PASSWORD = 'Panaderia2026';

async function main() {
  const pool = await getPool();

  await pool.request().query(`DROP USER IF EXISTS '${USUARIO}'@'%'`);
  console.log('Usuario anterior (si existía) eliminado.');

  await pool.request().query(`CREATE USER '${USUARIO}'@'%' IDENTIFIED BY '${PASSWORD}'`);
  console.log('Usuario creado.');

  await pool.request().query(`GRANT ALL PRIVILEGES ON corporacionRonceros.* TO '${USUARIO}'@'%'`);
  await pool.request().query('FLUSH PRIVILEGES');
  console.log('Permisos otorgados sobre corporacionRonceros.');

  const verificacion = await pool.request().query(`SELECT user, host, plugin FROM mysql.user WHERE user = '${USUARIO}'`);
  console.log('\nUsuario final:', verificacion.recordset);

  console.log(`\nDatos para MySQL Workbench:`);
  console.log(`  Usuario:  ${USUARIO}`);
  console.log(`  Password: ${PASSWORD}`);

  console.log('\nLISTO.');
  process.exit(0);
}

main().catch((e) => {
  console.log('ABORTADO:', e.message);
  process.exit(1);
});
