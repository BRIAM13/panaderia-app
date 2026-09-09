/**
 * Las dos piezas puras del flujo de activación de cuenta: el token que
 * viaja en el enlace del correo y la URL que se arma con él. Todo lo demás
 * de activacionService (guardar el hash, mandar el correo) toca la base o
 * la Gmail API y se prueba a mano; esto sí se puede fijar acá y es
 * justamente lo que no puede degradarse sin que nadie se entere.
 */

describe('generarTokenActivacion', () => {
  const { generarTokenActivacion } = require('../services/activacionService');

  test('devuelve 43 caracteres: los 32 bytes aleatorios en base64url', () => {
    // 32 bytes -> ceil(32/3)*4 = 44 con relleno, 43 sin el "=" que
    // base64url no usa. Si esto baja, bajó la entropía del token.
    expect(generarTokenActivacion()).toHaveLength(43);
  });

  test('solo usa caracteres seguros para una URL (A-Z a-z 0-9 - _)', () => {
    // Sin esto, un "+" o un "/" del base64 clásico se rompería al viajar
    // en la query string del enlace del correo.
    for (let i = 0; i < 50; i += 1) {
      expect(generarTokenActivacion()).toMatch(/^[A-Za-z0-9_-]+$/);
    }
  });

  test('nunca repite un token', () => {
    const tokens = new Set();
    for (let i = 0; i < 500; i += 1) tokens.add(generarTokenActivacion());
    expect(tokens.size).toBe(500);
  });

  test('pasa el validador del endpoint de activación', () => {
    // El token generado y el token que el validador acepta tienen que ser
    // la misma cosa: si alguien cambia el largo en un lado y no en el
    // otro, TODOS los enlaces de activación empiezan a rebotar con 400.
    const { validateActivarCuenta } = require('../middlewares/validators');
    let paso = false;
    const req = { body: { idPersona: 12, token: generarTokenActivacion(), passwordNueva: 'clave-larga-1' } };
    const res = { status: () => ({ json: () => {} }) };
    validateActivarCuenta(req, res, () => {
      paso = true;
    });
    expect(paso).toBe(true);
  });
});

describe('armarUrlActivacion', () => {
  const ENV_ORIGINAL = process.env.URL_PAGINA_WEB;

  afterEach(() => {
    if (ENV_ORIGINAL === undefined) delete process.env.URL_PAGINA_WEB;
    else process.env.URL_PAGINA_WEB = ENV_ORIGINAL;
    jest.resetModules();
  });

  function cargarConBase(base) {
    jest.resetModules();
    if (base === undefined) delete process.env.URL_PAGINA_WEB;
    else process.env.URL_PAGINA_WEB = base;
    return require('../services/activacionService').armarUrlActivacion;
  }

  test('sin URL_PAGINA_WEB apunta al dominio real de la página pública', () => {
    const armarUrlActivacion = cargarConBase(undefined);
    expect(armarUrlActivacion(7, 'abc')).toBe('https://panaderiaronceros.com/activar-cuenta?p=7&t=abc');
  });

  test('respeta la base configurada (ej. el Vite local en desarrollo)', () => {
    const armarUrlActivacion = cargarConBase('http://localhost:5173');
    expect(armarUrlActivacion(7, 'abc')).toBe('http://localhost:5173/activar-cuenta?p=7&t=abc');
  });

  test('una base con barra final no produce una doble barra', () => {
    const armarUrlActivacion = cargarConBase('https://panaderiaronceros.com/');
    expect(armarUrlActivacion(7, 'abc')).toBe('https://panaderiaronceros.com/activar-cuenta?p=7&t=abc');
  });

  test('los nombres de los parámetros son los que lee la página web', () => {
    // `p` e `t` — si acá cambian, ActivarCuentaPage.tsx deja de encontrar
    // los datos y muestra "enlace incompleto" a todo el mundo.
    const armarUrlActivacion = cargarConBase(undefined);
    const url = new URL(armarUrlActivacion(31, 'tok-en_123'));
    expect(url.pathname).toBe('/activar-cuenta');
    expect(url.searchParams.get('p')).toBe('31');
    expect(url.searchParams.get('t')).toBe('tok-en_123');
  });
});
