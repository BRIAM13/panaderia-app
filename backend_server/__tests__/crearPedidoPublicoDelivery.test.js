const { instalarMockMysql, crearRes, crearReq } = require('./helpers/mysqlMock');

/**
 * `POST /publico/pedidos` (crearPedidoPublico) con el delivery de Pisco
 * (2026-10-05).
 *
 * Mismo estilo que pagoCulqiController.test.js: se mockea `mysql2/promise` y
 * no `config/db.js`, así corre de verdad el shim que traduce el T-SQL y arma
 * los `?` — que es donde se rompería en silencio el INSERT con las columnas
 * nuevas (un @Param sin `.input()` revienta ahí).
 *
 * Cliente ya existente en la base, con celular guardado: así nunca se llama a
 * RENIEC/SUNAT (API paga) desde un test.
 */

/** La panadería (coordenadas reales confirmadas por el dueño). */
const PANADERIA = { lat: -13.706622640097475, lon: -76.20123704674447 };
const UN_KM_EN_GRADOS = 1 / ((Math.PI * 6371) / 180);

const PRODUCTO_PAN = { IdProducto: 1, Nombre: 'PAN FRANCES', PrecioUnitario: 0.2, IdTienda: 2, Slug: 'panaderia' };
const PRODUCTO_HAMBURGUESA = { IdProducto: 7, Nombre: 'PAN HAMBURGUESA', PrecioUnitario: 1, IdTienda: 1, Slug: 'hamburguesas' };

/** Pasado mañana a las 10:00 (hora Perú, UTC-5): siempre dentro del horario y nunca "muy pronto". */
function fechaRecojoValida() {
  const enPeru = new Date(Date.now() - 5 * 60 * 60 * 1000 + 2 * 24 * 60 * 60 * 1000);
  return `${enPeru.toISOString().slice(0, 10)}T10:00`;
}

/**
 * Prepara el mock. `config` son las claves de Configuraciones que se leen de
 * a una (`WHERE Clave = @Clave`): delivery y el interruptor de pago.
 */
function preparar({ productos = [PRODUCTO_PAN], config = {} } = {}) {
  jest.resetModules();
  const mock = instalarMockMysql();
  const porId = Object.fromEntries(productos.map((p) => [p.IdProducto, p]));

  // Preview de slugs (antes de la transacción).
  mock.responder(/SELECT p\.IdProducto, t\.Slug\s+FROM Productos/i, (texto) =>
    productos.filter((p) => new RegExp(`IN \\([^)]*\\b${p.IdProducto}\\b`).test(texto)).map(({ IdProducto, Slug }) => ({ IdProducto, Slug })),
  );
  // Producto por línea, dentro de la transacción.
  mock.responder(/SELECT p\.IdProducto, p\.Nombre, p\.PrecioUnitario, c\.IdTienda, t\.Slug/i, (_t, valores) =>
    porId[valores[0]] ? [porId[valores[0]]] : [],
  );
  mock.responder(/FROM Configuraciones WHERE Clave = \?/i, (_t, valores) =>
    valores[0] in config ? [{ Valor: config[valores[0]] }] : [],
  );
  mock.responder(/FROM Personas WHERE DNI/i, [
    {
      IdPersona: 40,
      Nombres: 'CLIENTE',
      ApellidoPaterno: 'PRUEBA',
      Email: null,
      Telefono: '987654321',
      EmailVerificado: 0,
      TelefonoVerificado: 0,
    },
  ]);
  mock.responder(/SELECT IdCliente FROM Clientes WHERE IdPersona/i, [{ IdCliente: 5 }]);
  mock.responder(/SELECT Ultimo FROM ContadoresPedidosDiarios/i, [{ Ultimo: 3 }]);
  mock.responderInsert(/INSERT INTO Pedidos\s*\(/i, 900);
  mock.responderInsert(/INSERT INTO PedidoItems/i, 1);
  mock.responder(/FROM DispositivosNotificacion|INSERT INTO Auditoria/i, []);

  const publico = require('../controllers/publicoController');
  return { mock, publico };
}

let ipSecuencial = 0;
async function llamar(publico, body) {
  const req = crearReq({ body });
  // El controlador limita 5 pedidos / 15 min por IP: una IP por llamada.
  ipSecuencial += 1;
  req.ip = `10.0.0.${ipSecuencial}`;
  const res = crearRes();
  const next = jest.fn();
  await publico.crearPedidoPublico(req, res, next);
  return { res, next };
}

function bodyPan(extra = {}) {
  return {
    documento: '00000000',
    items: [{ idProducto: 1, cantidad: 100 }],
    fechaEntrega: fechaRecojoValida(),
    ...extra,
  };
}

function bodyDelivery(extra = {}) {
  return bodyPan({
    tipoEntrega: 'DELIVERY',
    direccionEntrega: 'Calle Comercio 456, Pisco — portón verde al lado de la botica',
    latitudEntrega: PANADERIA.lat + 2 * UN_KM_EN_GRADOS,
    longitudEntrega: PANADERIA.lon,
    ...extra,
  });
}

/** Los valores del INSERT de Pedidos, por nombre (mismo orden que los @Param del texto). */
function valoresInsertPedido(mock) {
  const [insert] = mock.consultasQueMatcheen(/INSERT INTO Pedidos\s*\(/i);
  const columnas = insert.texto.match(/INSERT INTO Pedidos\s*\(([^)]*)\)/i)[1].split(',').map((c) => c.trim());
  // IdTrabajador va literal NULL y Estado literal 'SOLICITADO': no son `?`.
  const conParametro = columnas.filter((c) => !['IdTrabajador', 'Estado'].includes(c));
  return Object.fromEntries(conParametro.map((c, i) => [c, insert.valores[i]]));
}

describe('crearPedidoPublico — recojo sigue igual que siempre', () => {
  test('sin tipoEntrega: RECOJO, sin envío, el total es solo el pan', async () => {
    const { mock, publico } = preparar();
    const { res, next } = await llamar(publico, bodyPan());

    expect(next).not.toHaveBeenCalled();
    expect(res.statusCode).toBe(201);
    expect(res.body.total).toBe(20);
    expect(res.body.subtotal).toBe(20);
    expect(res.body.tipoEntrega).toBe('RECOJO');
    expect(res.body.costoEnvio).toBe(0);
    expect(res.body.direccionEntrega).toBeNull();

    const v = valoresInsertPedido(mock);
    expect(v).toMatchObject({
      Total: 20,
      TipoEntrega: 'RECOJO',
      DireccionEntrega: null,
      LatitudEntrega: null,
      LongitudEntrega: null,
      CostoEnvio: 0,
    });
    // Ni se consulta la configuración de delivery.
    expect(mock.consultasQueMatcheen(/WHERE Clave = \?/i).map((c) => c.valores[0])).not.toEqual(
      expect.arrayContaining(['COSTO_DELIVERY_PANADERIA']),
    );
  });

  test('tipoEntrega "RECOJO" explícito da exactamente lo mismo', async () => {
    const { publico } = preparar();
    const { res } = await llamar(publico, bodyPan({ tipoEntrega: 'RECOJO', direccionEntrega: 'ignorada por completo' }));
    expect(res.statusCode).toBe(201);
    expect(res.body.total).toBe(20);
    expect(res.body.direccionEntrega).toBeNull();
  });

  test('hamburguesa de recojo sigue sin fecha y sin envío', async () => {
    const { mock, publico } = preparar({ productos: [PRODUCTO_HAMBURGUESA] });
    const { res } = await llamar(publico, { documento: '00000000', items: [{ idProducto: 7, cantidad: 2 }] });
    expect(res.statusCode).toBe(201);
    expect(res.body.tipoEntrega).toBe('RECOJO');
    expect(valoresInsertPedido(mock).CostoEnvio).toBe(0);
  });

  test('un tipoEntrega inventado se rechaza con 400 antes de tocar la base', async () => {
    const { mock, publico } = preparar();
    const { res } = await llamar(publico, bodyPan({ tipoEntrega: 'DRON' }));
    expect(res.statusCode).toBe(400);
    expect(mock.contar(/INSERT INTO Pedidos\s*\(/i)).toBe(0);
  });
});

describe('crearPedidoPublico — delivery dentro de Pisco', () => {
  test('suma el envío al Total y guarda las 5 columnas', async () => {
    const { mock, publico } = preparar();
    const { res, next } = await llamar(publico, bodyDelivery());

    expect(next).not.toHaveBeenCalled();
    expect(res.statusCode).toBe(201);
    // 100 panes × S/ 0.20 = S/ 20 + S/ 4 de envío (default, sin clave sembrada).
    expect(res.body.subtotal).toBe(20);
    expect(res.body.costoEnvio).toBe(4);
    expect(res.body.total).toBe(24);
    expect(res.body.tipoEntrega).toBe('DELIVERY');
    expect(res.body.direccionEntrega).toBe('Calle Comercio 456, Pisco — portón verde al lado de la botica');

    const v = valoresInsertPedido(mock);
    expect(v.Total).toBe(24);
    expect(v.TipoEntrega).toBe('DELIVERY');
    expect(v.DireccionEntrega).toBe('Calle Comercio 456, Pisco — portón verde al lado de la botica');
    expect(v.LatitudEntrega).toBeCloseTo(PANADERIA.lat + 2 * UN_KM_EN_GRADOS, 7);
    expect(v.LongitudEntrega).toBeCloseTo(PANADERIA.lon, 7);
    expect(v.CostoEnvio).toBe(4);
    expect(mock.transaccion.commit).toBe(1);
  });

  test('la tarifa sale de Configuraciones (editable sin redeploy)', async () => {
    const { mock, publico } = preparar({ config: { COSTO_DELIVERY_PANADERIA: '5.5' } });
    const { res } = await llamar(publico, bodyDelivery());
    expect(res.body.costoEnvio).toBe(5.5);
    expect(res.body.total).toBe(25.5);
    expect(valoresInsertPedido(mock).CostoEnvio).toBe(5.5);
  });

  test('con el cobro por adelantado encendido, el Total a pagar ya incluye el envío', async () => {
    const { mock, publico } = preparar({ config: { EXIGE_PAGO_ADELANTADO_PANADERIA: '1' } });
    const { res } = await llamar(publico, bodyDelivery());
    expect(res.body.estadoPagoAdelanto).toBe('VERIFICANDO');
    expect(res.body.total).toBe(24);
    expect(valoresInsertPedido(mock).Total).toBe(24);
  });
});

describe('crearPedidoPublico — delivery rechazado', () => {
  test('fuera del radio: 400 con el motivo y fueraDeZona, sin convertirlo a recojo', async () => {
    const { mock, publico } = preparar();
    const { res } = await llamar(
      publico,
      bodyDelivery({ latitudEntrega: PANADERIA.lat + 9 * UN_KM_EN_GRADOS }),
    );
    expect(res.statusCode).toBe(400);
    expect(res.body.fueraDeZona).toBe(true);
    expect(res.body.mensaje).toMatch(/solo hacemos delivery dentro de Pisco/);
    expect(mock.contar(/INSERT INTO Pedidos\s*\(/i)).toBe(0);
    expect(mock.transaccion.begin).toBe(0);
  });

  test('el radio también se lee de Configuraciones', async () => {
    // A 2 km de la panadería, con el radio achicado a 1 km: fuera.
    const { publico } = preparar({ config: { DELIVERY_RADIO_KM: '1' } });
    const { res } = await llamar(publico, bodyDelivery());
    expect(res.statusCode).toBe(400);
    expect(res.body.fueraDeZona).toBe(true);
  });

  test('pan de hamburguesa con delivery: 400 "solo pan de agua y pan francés"', async () => {
    const { mock, publico } = preparar({ productos: [PRODUCTO_HAMBURGUESA] });
    const { res } = await llamar(publico, {
      documento: '00000000',
      items: [{ idProducto: 7, cantidad: 2 }],
      tipoEntrega: 'DELIVERY',
      direccionEntrega: 'Calle Comercio 456, Pisco',
      latitudEntrega: PANADERIA.lat,
      longitudEntrega: PANADERIA.lon,
    });
    expect(res.statusCode).toBe(400);
    expect(res.body.mensaje).toBe('El delivery solo está disponible para pan de agua y pan francés por ahora.');
    expect(res.body.fueraDeZona).toBe(false);
    expect(mock.contar(/INSERT INTO Pedidos\s*\(/i)).toBe(0);
  });

  test('sin dirección escrita: 400 aunque el pin esté bien', async () => {
    const { publico } = preparar();
    const { res } = await llamar(publico, bodyDelivery({ direccionEntrega: '  ' }));
    expect(res.statusCode).toBe(400);
    expect(res.body.mensaje).toMatch(/dirección completa y una referencia/);
    expect(res.body.fueraDeZona).toBe(false);
  });

  test('sin pin: 400 pidiendo marcarlo en el mapa', async () => {
    const { publico } = preparar();
    const { res } = await llamar(publico, bodyDelivery({ latitudEntrega: undefined, longitudEntrega: undefined }));
    expect(res.statusCode).toBe(400);
    expect(res.body.mensaje).toMatch(/Marca en el mapa/);
  });
});
