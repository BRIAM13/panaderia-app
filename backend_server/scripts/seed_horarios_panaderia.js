// Siembra las 3 claves de Configuraciones que controlan el horario de
// pedido/recojo de Panadería (pan de agua y francés, vendidos por unidad)
// — editables desde la app en "Horarios de pedido" (ADMIN/SUPERADMIN, ver
// horarios_pedido_page.dart). Idempotente: si la clave ya existe, no la
// pisa, solo confirma el valor actual.
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const { getPool, sql } = require('../config/db');
const {
  CLAVE_HORA_LIMITE,
  CLAVE_HORA_MISMO_DIA,
  CLAVE_HORA_DIA_SIGUIENTE,
} = require('../utils/horariosPanaderia');

const DEFAULTS = [
  {
    clave: CLAVE_HORA_LIMITE,
    valor: '10:00',
    descripcion: 'Hora límite para que un pedido de pan de agua/francés se recoja el mismo día (formato HH:mm, hora de Perú).',
  },
  {
    clave: CLAVE_HORA_MISMO_DIA,
    valor: '15:30',
    descripcion: 'Hora desde la que se puede recoger un pedido registrado el mismo día, dentro del plazo (formato HH:mm).',
  },
  {
    clave: CLAVE_HORA_DIA_SIGUIENTE,
    valor: '04:00',
    descripcion: 'Hora desde la que se puede recoger un pedido registrado fuera de plazo, o para cualquier día posterior (formato HH:mm).',
  },
];

async function main() {
  const pool = await getPool();
  for (const { clave, valor, descripcion } of DEFAULTS) {
    const existente = await pool.request()
      .input('Clave', sql.VarChar(50), clave)
      .query('SELECT Valor FROM Configuraciones WHERE Clave = @Clave');

    if (existente.recordset.length > 0) {
      console.log(`Ya existe ${clave} = ${existente.recordset[0].Valor} (sin cambios)`);
      continue;
    }

    await pool.request()
      .input('Clave', sql.VarChar(50), clave)
      .input('Valor', sql.NVarChar(200), valor)
      .input('Descripcion', sql.NVarChar(300), descripcion)
      .query(`
        INSERT INTO Configuraciones (Clave, Valor, Descripcion, FechaActualizacion)
        VALUES (@Clave, @Valor, @Descripcion, SYSUTCDATETIME())
      `);
    console.log(`Creado ${clave} = ${valor}`);
  }
  process.exit(0);
}
main().catch((e) => { console.error('ERROR:', e.message); process.exit(1); });
