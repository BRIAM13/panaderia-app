const sql = require('mssql');

const dbConfig = {
  server: process.env.DB_SERVER,
  port: Number(process.env.DB_PORT) || 1433,
  database: process.env.DB_DATABASE,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  // Azure SQL (oferta gratuita) pausa la base de datos sola tras un rato de
  // inactividad, y no deja configurar ese retraso de pausa (el control ni
  // aparece en el portal con la oferta gratuita activada). La primera
  // conexión tras una pausa puede tardar bastante en "despertar" la base de
  // datos — el valor por defecto de mssql (15s) no alcanza, así que se
  // amplía para que esa primera conexión no falle antes de que Azure
  // termine de reanudarla.
  connectionTimeout: 60000,
  requestTimeout: 60000,
  options: {
    encrypt: process.env.DB_ENCRYPT === 'true',
    trustServerCertificate: process.env.DB_TRUST_SERVER_CERTIFICATE === 'true',
  },
  pool: {
    max: 10,
    min: 0,
    idleTimeoutMillis: 30000,
  },
};

let poolPromise = null;

function getPool() {
  if (!poolPromise) {
    poolPromise = new sql.ConnectionPool(dbConfig)
      .connect()
      .then((pool) => {
        console.log('Conectado a SQL Server:', dbConfig.database);
        return pool;
      })
      .catch((err) => {
        poolPromise = null;
        throw err;
      });
  }
  return poolPromise;
}

module.exports = { sql, getPool };
