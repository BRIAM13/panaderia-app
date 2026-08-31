const request = require('supertest');
const app = require('../app');

describe('GET /api/prediccion-demanda/:idTienda/:idProducto', () => {
  test('sin token, se rechaza con 401 antes de intentar nada más', async () => {
    const respuesta = await request(app).get('/api/prediccion-demanda/3/3?fechas=2026-09-05');
    expect(respuesta.status).toBe(401);
  });
});
