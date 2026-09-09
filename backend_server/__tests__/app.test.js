const request = require('supertest');
const app = require('../app');

describe('GET /api/health', () => {
  test('responde 200 sin tocar la base de datos', async () => {
    const respuesta = await request(app).get('/api/health');
    expect(respuesta.status).toBe(200);
    expect(respuesta.body.estado).toBe('ok');
  });
});

describe('POST /api/auth/login', () => {
  test('rechaza con 400 si faltan las credenciales, antes de tocar la base de datos', async () => {
    const respuesta = await request(app).post('/api/auth/login').send({});
    expect(respuesta.status).toBe(400);
    expect(respuesta.body.errores).toEqual(
      expect.arrayContaining(['Nombre de usuario requerido.', 'Contraseña requerida.'])
    );
  });

  test('rechaza con 400 una contraseña vacía aunque venga un usuario válido', async () => {
    const respuesta = await request(app)
      .post('/api/auth/login')
      .send({ nombreUsuario: '12345678', password: '' });
    expect(respuesta.status).toBe(400);
  });
});

describe('POST /api/auth/recuperar/solicitar', () => {
  test('rechaza con 400 si falta nombreUsuario, antes de tocar la base de datos', async () => {
    const respuesta = await request(app).post('/api/auth/recuperar/solicitar').send({});
    expect(respuesta.status).toBe(400);
  });
});

describe('POST /api/auth/activar-cuenta', () => {
  // Token con forma válida (43 caracteres base64url) para que el caso bajo
  // prueba sea SIEMPRE el campo que se está probando y no el token.
  const TOKEN_VALIDO = 'a'.repeat(43);

  test('rechaza con 400 un body vacío, antes de tocar la base de datos', async () => {
    const respuesta = await request(app).post('/api/auth/activar-cuenta').send({});
    expect(respuesta.status).toBe(400);
  });

  test('rechaza con 400 una contraseña de menos de 8 caracteres', async () => {
    const respuesta = await request(app)
      .post('/api/auth/activar-cuenta')
      .send({ idPersona: 5, token: TOKEN_VALIDO, passwordNueva: 'corta' });
    expect(respuesta.status).toBe(400);
    expect(respuesta.body.errores).toEqual(
      expect.arrayContaining(['La contraseña debe tener al menos 8 caracteres.'])
    );
  });

  test('rechaza con 400 un token con caracteres fuera del alfabeto base64url', async () => {
    const respuesta = await request(app)
      .post('/api/auth/activar-cuenta')
      .send({ idPersona: 5, token: '../../etc/passwd', passwordNueva: 'clave-larga-1' });
    expect(respuesta.status).toBe(400);
  });

  test('rechaza con 400 un idPersona que no es un entero positivo', async () => {
    const respuesta = await request(app)
      .post('/api/auth/activar-cuenta')
      .send({ idPersona: 0, token: TOKEN_VALIDO, passwordNueva: 'clave-larga-1' });
    expect(respuesta.status).toBe(400);
  });
});

describe('POST /api/auth/recuperar/confirmar', () => {
  test('rechaza con 400 si el código no tiene 6 dígitos, antes de tocar la base de datos', async () => {
    const respuesta = await request(app)
      .post('/api/auth/recuperar/confirmar')
      .send({ nombreUsuario: '12345678', codigo: '123', passwordNueva: 'nuevaClave123' });
    expect(respuesta.status).toBe(400);
  });

  test('rechaza con 400 una contraseña nueva corta, antes de tocar la base de datos', async () => {
    const respuesta = await request(app)
      .post('/api/auth/recuperar/confirmar')
      .send({ nombreUsuario: '12345678', codigo: '004821', passwordNueva: 'corta' });
    expect(respuesta.status).toBe(400);
  });
});

describe('Ruta inexistente', () => {
  test('responde 404 en vez de colgarse o tirar un error 500', async () => {
    const respuesta = await request(app).get('/api/esto-no-existe');
    expect(respuesta.status).toBe(404);
  });
});
