// Siembra las 4 claves de Configuraciones que controlan el delivery del
// pedido web de Panadería (solo Pisco): la tarifa de envío, el centro de la
// zona de reparto (la panadería) y el radio en km. Editables sin redeploy:
// el backend las relee en cada pedido (ver utils/delivery.js). Idempotente:
// si la clave ya existe, no la pisa, solo confirma el valor actual — así no
// se le deshace un ajuste que el dueño ya hizo.
//
// Correr DESPUÉS de database_migrations/2026_10_delivery_panaderia.sql.
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const { getPool, sql } = require('../config/db');
const {
  CLAVE_COSTO_DELIVERY,
  CLAVE_LATITUD_CENTRO,
  CLAVE_LONGITUD_CENTRO,
  CLAVE_RADIO_KM,
} = require('../utils/delivery');

const DEFAULTS = [
  {
    clave: CLAVE_COSTO_DELIVERY,
    valor: '4',
    descripcion: 'Costo del delivery (soles) del pedido web de Panaderia dentro de Pisco. Se suma al Total del pedido.',
  },
  {
    // Coordenadas REALES de la panadería, confirmadas por el dueño el
    // 2026-10-05. Se guardan como texto, sin redondear.
    clave: CLAVE_LATITUD_CENTRO,
    valor: '-13.706622640097475',
    descripcion: 'Latitud del centro de la zona de delivery (la panaderia). El radio se mide desde aca.',
  },
  {
    clave: CLAVE_LONGITUD_CENTRO,
    valor: '-76.20123704674447',
    descripcion: 'Longitud del centro de la zona de delivery (la panaderia). El radio se mide desde aca.',
  },
  {
    clave: CLAVE_RADIO_KM,
    valor: '8',
    descripcion: 'Radio (km, en linea recta desde la panaderia) dentro del cual se acepta delivery. Ajustar si rechaza direcciones validas de Pisco o acepta algunas muy lejanas.',
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
