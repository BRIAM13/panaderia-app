const mysql = require('mysql2/promise');

// Migración de Azure SQL (SQL Server) a MariaDB: en vez de reescribir a mano
// cada controlador (461 usos de la API de `mssql` repartidos en 18
// archivos), esta capa reproduce la misma API (`pool.request().input().query()`,
// `sql.Transaction`, `sql.Int`/`sql.VarChar(n)` como marcadores de tipo) sobre
// mysql2, traduciendo la sintaxis T-SQL de cada texto de consulta al vuelo.
// La lógica de cada consulta no cambia — solo el transporte.
const pool = mysql.createPool({
  host: process.env.DB_SERVER,
  port: Number(process.env.DB_PORT) || 3306,
  database: process.env.DB_DATABASE,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  waitForConnections: true,
  connectionLimit: 10,
  connectTimeout: 20000,
  charset: 'utf8mb4_unicode_ci',
  // Sin esto, mysql2 devuelve las columnas DECIMAL (dinero, ej. SUM() en los
  // resúmenes de tienda) como string en vez de number — a diferencia de
  // `mssql`, que sí las mandaba como number. La app Flutter espera number.
  decimalNumbers: true,
});

// Marcadores de tipo: mysql2 no necesita el tipo explícito por parámetro
// (basta el valor JS), así que `.input('X', sql.Int, valor)` solo necesita
// que `sql.Int` exista y no rompa nada al invocarlo/usarlo como valor.
const tipoIgnorado = Symbol('tipo-ignorado');
const marcador = () => tipoIgnorado;
const sql = {
  Int: tipoIgnorado,
  BigInt: tipoIgnorado,
  SmallInt: tipoIgnorado,
  TinyInt: tipoIgnorado,
  Bit: tipoIgnorado,
  Float: tipoIgnorado,
  Date: tipoIgnorado,
  DateTime: tipoIgnorado,
  DateTime2: tipoIgnorado,
  VarChar: marcador,
  NVarChar: marcador,
  Char: marcador,
  NChar: marcador,
  Text: tipoIgnorado,
  NText: tipoIgnorado,
  Decimal: marcador,
  Numeric: marcador,
};

/** Traduce funciones/cláusulas T-SQL usadas literalmente en el texto de las consultas. */
function traducirSintaxis(textoOriginal) {
  let texto = textoOriginal;

  texto = texto.replace(/\bSYSUTCDATETIME\(\)/gi, 'UTC_TIMESTAMP(3)');
  texto = texto.replace(/\bISNULL\(/gi, 'IFNULL(');

  // DATEADD(HOUR, -5, Expr) -> DATE_SUB(Expr, INTERVAL 5 HOUR) (o DATE_ADD si es positivo)
  texto = texto.replace(
    /DATEADD\(\s*HOUR\s*,\s*(-?\d+)\s*,\s*([^()]+(?:\([^()]*\)[^()]*)*)\)/gi,
    (_, horas, expr) => {
      const h = Number(horas);
      const fn = h < 0 ? 'DATE_SUB' : 'DATE_ADD';
      return `${fn}(${expr.trim()}, INTERVAL ${Math.abs(h)} HOUR)`;
    }
  );

  // SELECT TOP N ... -> SELECT ... LIMIT N (al final del texto)
  const topMatch = texto.match(/\bSELECT\s+TOP\s*\(?\s*(\d+)\s*\)?\s+/i);
  if (topMatch) {
    texto = texto.replace(/\bSELECT\s+TOP\s*\(?\s*\d+\s*\)?\s+/i, 'SELECT ');
    texto = texto.trimEnd() + ` LIMIT ${topMatch[1]}`;
  }

  return texto;
}

/**
 * SQL Server: `INSERT ... OUTPUT INSERTED.Col1[, INSERTED.Col2...] VALUES ...`
 * devuelve la(s) columna(s) de la fila recién insertada en el mismo round-trip.
 * MySQL no tiene equivalente: se separa la cláusula, se usa `insertId` para
 * la primera columna (siempre la identidad/PK en este código) y, si se piden
 * columnas extra (ej. una fecha con default de la base), se hace un SELECT
 * de vuelta por esa PK.
 */
function extraerOutputInserted(texto) {
  const m = texto.match(/OUTPUT\s+INSERTED\.\w+(?:\s*,\s*INSERTED\.\w+)*/i);
  if (!m) return { texto, columnas: null };
  const columnas = [...m[0].matchAll(/INSERTED\.(\w+)/gi)].map((c) => c[1]);
  const limpio = texto.replace(m[0], '').replace(/\n\s*\n/g, '\n');
  return { texto: limpio, columnas };
}

function extraerTablaInsert(texto) {
  const m = texto.match(/INSERT\s+INTO\s+(\w+)/i);
  return m ? m[1] : null;
}

class RequestCompat {
  constructor(runner) {
    this._runner = runner; // objeto con `.query(sql, params)`: el pool o una conexión de transacción
    this._params = new Map();
  }

  input(nombre, tipoOValor, valorSiHayTipo) {
    const valor = arguments.length >= 3 ? valorSiHayTipo : tipoOValor;
    this._params.set(nombre, valor === undefined ? null : valor);
    return this;
  }

  async query(textoOriginal) {
    const { texto: sinOutput, columnas } = extraerOutputInserted(textoOriginal);
    let texto = traducirSintaxis(sinOutput);

    const valores = [];
    texto = texto.replace(/@(\w+)/g, (coincide, nombre) => {
      if (!this._params.has(nombre)) {
        throw new Error(`Parámetro @${nombre} no fue provisto con .input() en la consulta`);
      }
      valores.push(this._params.get(nombre));
      return '?';
    });

    const [resultado] = await this._runner.query(texto, valores);

    if (columnas) {
      const tabla = extraerTablaInsert(textoOriginal);
      const fila = { [columnas[0]]: resultado.insertId };
      const extras = columnas.slice(1);
      if (extras.length > 0 && tabla) {
        const [filasExtra] = await this._runner.query(
          `SELECT ${extras.map((c) => `\`${c}\``).join(', ')} FROM \`${tabla}\` WHERE \`${columnas[0]}\` = ?`,
          [resultado.insertId]
        );
        Object.assign(fila, filasExtra[0]);
      }
      return { recordset: [fila], recordsets: [[fila]], rowsAffected: [1] };
    }

    if (Array.isArray(resultado)) {
      return { recordset: resultado, recordsets: [resultado], rowsAffected: [resultado.length] };
    }

    return { recordset: [], recordsets: [[]], rowsAffected: [resultado.affectedRows ?? 0] };
  }
}

class TransactionCompat {
  constructor() {
    this._conn = null;
  }
  async begin() {
    this._conn = await pool.getConnection();
    await this._conn.beginTransaction();
  }
  async commit() {
    await this._conn.commit();
    this._conn.release();
  }
  async rollback() {
    if (!this._conn) return;
    try {
      await this._conn.rollback();
    } catch (_) {
      // La conexión ya pudo haberse perdido; no hay más que hacer acá.
    }
    this._conn.release();
  }
}

sql.Transaction = TransactionCompat;
sql.Request = function (runnerOTransaccion) {
  const runner = runnerOTransaccion instanceof TransactionCompat ? runnerOTransaccion._conn : runnerOTransaccion;
  return new RequestCompat(runner);
};

const poolCompat = {
  request: () => new RequestCompat(pool),
};

let poolPromise = null;

function getPool() {
  if (!poolPromise) {
    poolPromise = pool
      .getConnection()
      .then((conn) => {
        conn.release();
        console.log('Conectado a MariaDB:', process.env.DB_DATABASE);
        return poolCompat;
      })
      .catch((err) => {
        poolPromise = null;
        throw err;
      });
  }
  return poolPromise;
}

module.exports = { sql, getPool };
