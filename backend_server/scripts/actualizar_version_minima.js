// Actualiza VERSION_MINIMA_ANDROID (y de paso asegura URL_DESCARGA_APK) en
// Configuraciones directo por conexión a la base — lo usa
// scripts/publicar_actualizacion.ps1 al final de cada release, así no hace
// falta entrar a la pantalla "Versión de la app" a mano cada vez.
// Uso: node actualizar_version_minima.js <version, ej. 1.1.0>
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const { getPool } = require('../config/db');

const URL_DESCARGA_APK =
  'https://corporacionronceros.vercel.app/downloads/CorporacionRonceros-latest.apk';

async function main() {
  const version = process.argv[2];
  if (!version || !/^\d+\.\d+\.\d+$/.test(version)) {
    console.error('Uso: node actualizar_version_minima.js <version, ej. 1.1.0>');
    process.exit(1);
  }

  const pool = await getPool();

  await pool
    .request()
    .input('Valor', version)
    .query(
      "UPDATE Configuraciones SET Valor = @Valor, FechaActualizacion = SYSUTCDATETIME() WHERE Clave = 'VERSION_MINIMA_ANDROID'"
    );

  await pool
    .request()
    .input('Valor', URL_DESCARGA_APK)
    .query(
      "UPDATE Configuraciones SET Valor = @Valor, FechaActualizacion = SYSUTCDATETIME() WHERE Clave = 'URL_DESCARGA_APK'"
    );

  console.log(`VERSION_MINIMA_ANDROID -> ${version}`);
  console.log(`URL_DESCARGA_APK -> ${URL_DESCARGA_APK}`);
  console.log('Listo: quien abra la app con una versión menor verá el bloqueo de actualización.');
  process.exit(0);
}

main().catch((err) => {
  console.error('ERROR:', err.message);
  process.exit(1);
});
