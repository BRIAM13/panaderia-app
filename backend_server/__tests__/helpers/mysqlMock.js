/**
 * Mock de `mysql2/promise` — a propósito NO se mockea `config/db.js`: así
 * los tests ejercitan de verdad el shim que traduce la sintaxis T-SQL
 * (OUTPUT INSERTED, ISNULL, TOP N…) y arma los parámetros `?`, que es donde
 * de verdad se puede romper algo silenciosamente.
 *
 * Uso típico (con `jest.resetModules()` en un beforeEach, porque
 * `config/db.js` crea su pool al importarse):
 *
 *   const { instalarMockMysql } = require('./helpers/mysqlMock');
 *   const mock = instalarMockMysql();
 *   mock.responder(/SELECT IdTrabajador FROM Trabajadores/i, [{ IdTrabajador: 7 }]);
 *   const controller = require('../controllers/pedidosController');
 */

function crearMock() {
  // Reglas en orden de registro: gana la PRIMERA que matchea, así un test
  // puede sobrescribir un caso puntual registrándolo antes del genérico.
  const reglas = [];
  const consultas = [];
  const transacciones = [];

  function resolver(texto, valores) {
    for (const regla of reglas) {
      // Los patrones son /g-less a propósito: un regex global recuerda
      // lastIndex entre llamadas y fallaría en la segunda consulta igual.
      if (regla.patron.test(texto)) {
        return typeof regla.respuesta === 'function' ? regla.respuesta(texto, valores) : regla.respuesta;
      }
    }
    return [];
  }

  /**
   * Devuelve lo que mysql2 devolvería: `[filas, campos]`. Para un INSERT se
   * responde con `{ insertId }` (objeto, no arreglo) — es lo que
   * RequestCompat usa para resolver `OUTPUT INSERTED.Id...`.
   */
  async function ejecutar(texto, valores) {
    consultas.push({ texto, valores });
    const respuesta = resolver(texto, valores);
    if (respuesta instanceof Error) throw respuesta;
    return [respuesta, []];
  }

  function crearConexion() {
    const registro = { begin: 0, commit: 0, rollback: 0, released: 0 };
    transacciones.push(registro);
    return {
      query: ejecutar,
      beginTransaction: async () => {
        registro.begin += 1;
      },
      commit: async () => {
        registro.commit += 1;
      },
      rollback: async () => {
        registro.rollback += 1;
      },
      release: () => {
        registro.released += 1;
      },
      _registro: registro,
    };
  }

  const pool = {
    query: ejecutar,
    getConnection: async () => crearConexion(),
    end: async () => {},
  };

  return {
    createPool: () => pool,
    _api: {
      /** Registra qué debe devolver una consulta que matchee [patron]. */
      responder(patron, respuesta) {
        reglas.push({ patron, respuesta });
        return this;
      },
      /** Registra un INSERT: la capa de compat lee `insertId`. */
      responderInsert(patron, insertId) {
        reglas.push({ patron, respuesta: { insertId, affectedRows: 1 } });
        return this;
      },
      /** Hace que una consulta reviente, para probar el rollback. */
      responderConError(patron, mensaje) {
        reglas.push({ patron, respuesta: new Error(mensaje) });
        return this;
      },
      /** Todas las consultas ejecutadas, en orden. */
      consultas,
      /** Cuántas consultas matchean [patron]. */
      contar(patron) {
        return consultas.filter((c) => patron.test(c.texto)).length;
      },
      consultasQueMatcheen(patron) {
        return consultas.filter((c) => patron.test(c.texto));
      },
      /**
       * La transacción real (la primera que llamó a `beginTransaction`) con
       * sus contadores. Se busca por `begin > 0` y no por posición porque
       * `getPool()` también saca una conexión del pool al arrancar, solo
       * para comprobar que la base responde, y esa nunca abre transacción.
       */
      get transaccion() {
        return transacciones.find((t) => t.begin > 0) ?? { begin: 0, commit: 0, rollback: 0, released: 0 };
      },
      transacciones,
    },
  };
}

/**
 * Instala el mock en el registro de módulos de Jest y devuelve su API.
 * Llamar ANTES de requerir cualquier controller.
 */
function instalarMockMysql() {
  const mock = crearMock();
  jest.doMock('mysql2/promise', () => ({ createPool: mock.createPool }));
  return mock._api;
}

/** Un `res` de Express falso que guarda status y body. */
function crearRes() {
  const res = {
    statusCode: null,
    body: null,
    status(codigo) {
      res.statusCode = codigo;
      return res;
    },
    json(cuerpo) {
      res.body = cuerpo;
      return res;
    },
  };
  return res;
}

function crearReq({ body = {}, usuario = {}, params = {}, query = {} } = {}) {
  return {
    body,
    params,
    query,
    usuario: { idPersona: 1, idUsuario: 10, rol: 'ADMIN', ...usuario },
    ip: '127.0.0.1',
    headers: { 'user-agent': 'jest' },
  };
}

module.exports = { instalarMockMysql, crearRes, crearReq };
