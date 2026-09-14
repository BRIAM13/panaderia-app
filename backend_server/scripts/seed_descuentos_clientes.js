// Siembra las 6 claves de Configuraciones que controlan el descuento por
// fidelidad del cliente en la página web pública: los 5 porcentajes por
// segmento del CRM y la lista de tiendas donde el descuento está activo.
// Editables desde la app en "Descuentos por cliente" (ADMIN/SUPERADMIN,
// ver descuentos_clientes_page.dart). Idempotente: si la clave ya existe,
// no la pisa, solo confirma el valor actual.
//
// Correr DESPUÉS de database_migrations/2026_09_descuento_clientes.sql.
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const { getPool, sql } = require('../config/db');
const {
  CLAVE_DESCUENTO_NUEVO,
  CLAVE_DESCUENTO_REGULAR,
  CLAVE_DESCUENTO_EN_RIESGO,
  CLAVE_DESCUENTO_FRECUENTE,
  CLAVE_DESCUENTO_VIP,
  CLAVE_TIENDAS_HABILITADAS,
} = require('../utils/descuentosCliente');

const DEFAULTS = [
  {
    clave: CLAVE_DESCUENTO_NUEVO,
    valor: '5',
    descripcion: 'Descuento (%) para un cliente del segmento NUEVO — su primer pedido también recibe descuento.',
  },
  {
    clave: CLAVE_DESCUENTO_REGULAR,
    valor: '5',
    descripcion: 'Descuento (%) para un cliente del segmento REGULAR (ya compró, sin llegar a frecuente ni VIP).',
  },
  {
    clave: CLAVE_DESCUENTO_EN_RIESGO,
    valor: '5',
    descripcion: 'Descuento (%) para un cliente del segmento EN_RIESGO (hace tiempo que no compra).',
  },
  {
    clave: CLAVE_DESCUENTO_FRECUENTE,
    valor: '10',
    descripcion: 'Descuento (%) para un cliente del segmento FRECUENTE (llegó al umbral de pedidos entregados).',
  },
  {
    clave: CLAVE_DESCUENTO_VIP,
    valor: '15',
    descripcion: 'Descuento (%) para un cliente del segmento VIP (llegó al umbral de gasto acumulado).',
  },
  {
    clave: CLAVE_TIENDAS_HABILITADAS,
    valor: 'panaderia',
    descripcion: 'Slugs de tienda, separados por coma, donde aplica el descuento por fidelidad (vacío = ninguna).',
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
