const { instalarMockMysql, crearRes, crearReq } = require('./helpers/mysqlMock');

/**
 * `POST /publico/pedidos/:idPedido/pagar-culqi` — el cobro con tarjeta del
 * pedido web de Panadería.
 *
 * Mismo estilo que pagoAdelantoController.test.js: se mockea `mysql2/promise`
 * (no `config/db.js`) para que corra de verdad el shim que traduce el T-SQL,
 * que es donde se rompería algo en silencio.
 *
 * Y ADEMÁS se mockea `axios`: acá NUNCA se llama a la API real de Culqi. No
 * es solo por velocidad — un test que cobre de verdad movería plata real de
 * una cuenta real, y el token de un cargo es de un solo uso, así que el
 * segundo `npm test` fallaría de todas formas.
 */

/** La llave secreta que hace que `culqiConfigurado()` diga true. Es inventada
 * y nunca sale a la red: la única petición posible la intercepta el mock de
 * axios de abajo. */
const LLAVE_FALSA = 'sk_test_llave_de_prueba_no_real';

/** El pedido tal como lo devuelve el SELECT de `pagarPedidoCulqi`: ya creado
 * por el formulario, esperando que se le cobre. */
const PEDIDO_ESPERANDO_PAGO = {
  IdPedido: 900,
  NumeroPedidoDia: 3,
  IdTienda: 1,
  IdCliente: 5,
  Total: 50,
  Estado: 'SOLICITADO',
  EstadoPagoAdelanto: 'VERIFICANDO',
  TokenConfirmacionPago: 'tokenbueno123',
  DNI: '12345678',
};

/** Un token de tarjeta con la forma que emite Culqi.js en el navegador. */
const TOKEN_TARJETA = 'tkn_test_A1b2C3d4E5f6G7h8';

/** La respuesta de un cargo exitoso, recortada a lo que el controlador lee.
 * `amount` viene en CÉNTIMOS, como manda Culqi. */
function cargoExitoso({ amount = 5000, id = 'chr_test_abc123' } = {}) {
  return {
    data: {
      object: 'charge',
      id,
      amount,
      currency_code: 'PEN',
      outcome: { type: 'venta_exitosa', code: 'AUT0000', user_message: 'Su compra fue aprobada.' },
    },
  };
}

/** Un rechazo de Culqi: error HTTP con el cuerpo documentado en
 * https://docs.culqi.com/es/documentacion/pagos-online/denegaciones/ */
function rechazoCulqi({ declineCode = 'insufficient_funds', userMessage, status = 400 } = {}) {
  const error = new Error('Request failed with status code ' + status);
  error.response = {
    status,
    data: {
      object: 'error',
      type: 'card_error',
      charge_id: 'chr_test_rechazado',
      code: 'card_declined',
      decline_code: declineCode,
      merchant_message: 'Fondos insuficientes.',
      ...(userMessage !== undefined ? { user_message: userMessage } : {}),
    },
  };
  return error;
}

/**
 * Prepara el mock de base + el mock de axios y devuelve el controlador recién
 * importado. `axiosPost` es lo que va a hacer la llamada a Culqi: una función
 * de jest que resuelve (cobro exitoso) o rechaza (rechazo / caída de red).
 */
function preparar({ pedido = PEDIDO_ESPERANDO_PAGO, axiosPost, sinLlave = false, errorUpdate = false } = {}) {
  jest.resetModules();

  if (sinLlave) delete process.env.CULQI_SECRET_KEY;
  else process.env.CULQI_SECRET_KEY = LLAVE_FALSA;

  const post = axiosPost ?? jest.fn().mockResolvedValue(cargoExitoso());
  jest.doMock('axios', () => ({ post, create: () => ({ post }) }));

  const mock = instalarMockMysql();
  mock.responder(/FROM Pedidos pd\s+INNER JOIN Clientes c/i, pedido ? [pedido] : []);
  if (errorUpdate) {
    mock.responderConError(/UPDATE Pedidos\s+SET Estado = 'CONFIRMADO'/i, 'se cayó la base');
  }
  mock.responderInsert(/INSERT INTO AjustesPago/i, 77);
  mock.responder(/FROM DispositivosNotificacion|INSERT INTO Auditoria/i, []);

  const publico = require('../controllers/publicoController');
  return { mock, publico, post };
}

async function llamar(controller, req) {
  const res = crearRes();
  const next = jest.fn();
  await controller(req, res, next);
  return { res, next };
}

/** El body del camino feliz: token de pedido (de localStorage) + token de
 * tarjeta + correo para el comprobante. */
function body(extra = {}) {
  return {
    token: 'tokenbueno123',
    culqiTokenId: TOKEN_TARJETA,
    email: 'cliente@correo.com',
    ...extra,
  };
}

function req(cuerpo = body(), params = { idPedido: '900' }) {
  return crearReq({ body: cuerpo, params });
}

const LLAVE_ORIGINAL = process.env.CULQI_SECRET_KEY;
afterAll(() => {
  if (LLAVE_ORIGINAL === undefined) delete process.env.CULQI_SECRET_KEY;
  else process.env.CULQI_SECRET_KEY = LLAVE_ORIGINAL;
});

describe('pagarPedidoCulqi — el cobro sale bien', () => {
  test('cobra el monto exacto, deja el pedido CONFIRMADO y no crea ajuste', async () => {
    const { mock, publico, post } = preparar();
    const { res } = await llamar(publico.pagarPedidoCulqi, req());

    expect(res.statusCode).toBe(200);
    expect(res.body.estado).toBe('CONFIRMADO');
    expect(res.body.estadoPagoAdelanto).toBe('PAGADO');
    expect(res.body.ajuste).toBeNull();
    expect(res.body.culqiChargeId).toBe('chr_test_abc123');
    expect(mock.contar(/INSERT INTO AjustesPago/i)).toBe(0);
    expect(mock.transaccion.commit).toBe(1);

    const update = mock.consultasQueMatcheen(/UPDATE Pedidos\s+SET Estado = 'CONFIRMADO'/i);
    expect(update).toHaveLength(1);
    expect(update[0].valores).toEqual(['PAGADO', 50, 900]);
    // La guarda contra el doble cobro viaja en el propio UPDATE: si dos pagos
    // del mismo pedido se cruzan, el segundo no pisa al primero.
    expect(update[0].texto).toMatch(/EstadoPagoAdelanto = 'VERIFICANDO'/i);
  });

  test('le pide a Culqi CÉNTIMOS enteros, no soles — el error más caro posible', async () => {
    // S/ 50.00 -> 5000. Mandar `50` le cobraría S/ 0.50 a quien pidió S/ 50 de
    // pan, y el pedido quedaría marcado como pagado.
    const { publico, post } = preparar();
    await llamar(publico.pagarPedidoCulqi, req());

    expect(post).toHaveBeenCalledTimes(1);
    const [url, cuerpo, opciones] = post.mock.calls[0];
    expect(url).toBe('https://api.culqi.com/v2/charges');
    expect(cuerpo.amount).toBe(5000);
    expect(cuerpo.currency_code).toBe('PEN');
    expect(cuerpo.source_id).toBe(TOKEN_TARJETA);
    expect(cuerpo.email).toBe('cliente@correo.com');
    // La llave SECRETA va en el header, nunca en el cuerpo ni en la URL.
    expect(opciones.headers.Authorization).toBe(`Bearer ${LLAVE_FALSA}`);
  });

  test('un total con decimales se redondea al céntimo, sin perder ni uno', async () => {
    // 50.10 * 100 da 5009.999999999999 en punto flotante: truncar cobraría
    // S/ 50.09. Por eso la conversión redondea.
    const { publico, post } = preparar({
      pedido: { ...PEDIDO_ESPERANDO_PAGO, Total: 50.1 },
      axiosPost: jest.fn().mockResolvedValue(cargoExitoso({ amount: 5010 })),
    });
    await llamar(publico.pagarPedidoCulqi, req());

    expect(post.mock.calls[0][1].amount).toBe(5010);
  });

  test('el DNI del cliente sirve como segunda vía (otro celular, sin localStorage)', async () => {
    const { publico } = preparar();
    const { res } = await llamar(
      publico.pagarPedidoCulqi,
      req(body({ token: undefined, documento: '12345678' })),
    );

    expect(res.statusCode).toBe(200);
    expect(res.body.estadoPagoAdelanto).toBe('PAGADO');
  });

  test('si Culqi cobrara MENOS del total, queda DEUDA_PARCIAL con su ajuste', async () => {
    // No debería pasar nunca (se le pide un monto exacto), pero la lógica de
    // saldos se conserva del flujo de Yape para que un reembolso parcial o una
    // captura por otro monto no se pierda en silencio.
    const { mock, publico } = preparar({
      axiosPost: jest.fn().mockResolvedValue(cargoExitoso({ amount: 4800 })),
    });
    const { res } = await llamar(publico.pagarPedidoCulqi, req());

    expect(res.body.estadoPagoAdelanto).toBe('DEUDA_PARCIAL');
    expect(res.body.ajuste).toEqual({ idAjuste: 77, tipo: 'DEUDA', monto: 2, estado: 'PENDIENTE' });
    expect(mock.consultasQueMatcheen(/INSERT INTO AjustesPago/i)[0].valores).toEqual([900, 'DEUDA', 2]);
  });

  test('si Culqi cobrara MÁS del total, queda VUELTO_PENDIENTE con su ajuste', async () => {
    const { mock, publico } = preparar({
      axiosPost: jest.fn().mockResolvedValue(cargoExitoso({ amount: 5300 })),
    });
    const { res } = await llamar(publico.pagarPedidoCulqi, req());

    expect(res.body.estadoPagoAdelanto).toBe('VUELTO_PENDIENTE');
    expect(res.body.ajuste).toEqual({ idAjuste: 77, tipo: 'VUELTO', monto: 3, estado: 'PENDIENTE' });
    expect(mock.consultasQueMatcheen(/INSERT INTO AjustesPago/i)[0].valores).toEqual([900, 'VUELTO', 3]);
  });
});

describe('pagarPedidoCulqi — Culqi dice NO', () => {
  test('tarjeta sin fondos: 400 con el mensaje de Culqi y el pedido intacto', async () => {
    const { mock, publico } = preparar({
      axiosPost: jest.fn().mockRejectedValue(
        rechazoCulqi({ userMessage: 'Su tarjeta no tiene fondos suficientes.' }),
      ),
    });
    const { res, next } = await llamar(publico.pagarPedidoCulqi, req());

    // Un rechazo NO es un error inesperado: nunca debe escaparse al middleware
    // de errores como un 500.
    expect(next).not.toHaveBeenCalled();
    expect(res.statusCode).toBe(400);
    expect(res.body.mensaje).toMatch(/fondos suficientes/i);
    // El pedido se queda esperando: es lo que le permite reintentar con otra
    // tarjeta sin volver a llenar el formulario.
    expect(res.body.estadoPagoAdelanto).toBe('VERIFICANDO');
    expect(mock.contar(/UPDATE Pedidos\s+SET Estado = 'CONFIRMADO'/i)).toBe(0);
  });

  test('sin user_message, el decline_code se traduce a español entendible', async () => {
    const { publico } = preparar({
      axiosPost: jest.fn().mockRejectedValue(rechazoCulqi({ declineCode: 'expired_card' })),
    });
    const { res } = await llamar(publico.pagarPedidoCulqi, req());

    expect(res.statusCode).toBe(400);
    expect(res.body.mensaje).toMatch(/vencida/i);
    // Nunca se le muestra el merchant_message crudo: puede traer jerga de
    // procesador que no le sirve de nada.
    expect(res.body.mensaje).not.toMatch(/Fondos insuficientes\./);
  });

  test('un decline_code desconocido cae a un mensaje genérico, no a un 500', async () => {
    const { publico } = preparar({
      axiosPost: jest.fn().mockRejectedValue(rechazoCulqi({ declineCode: 'codigo_que_no_existe_todavia' })),
    });
    const { res, next } = await llamar(publico.pagarPedidoCulqi, req());

    expect(next).not.toHaveBeenCalled();
    expect(res.statusCode).toBe(400);
    expect(res.body.mensaje).toMatch(/otra tarjeta|tu pedido sigue guardado/i);
  });

  test('si Culqi no responde (timeout/red) es 502, no "tarjeta rechazada"', async () => {
    // La diferencia importa: acá NO se sabe si hubo cobro, y decirle "te la
    // rechazaron" a alguien a quien tal vez sí le cobraron sería mentirle.
    const { mock, publico } = preparar({
      axiosPost: jest.fn().mockRejectedValue(Object.assign(new Error('timeout of 20000ms exceeded'), { code: 'ECONNABORTED' })),
    });
    const { res } = await llamar(publico.pagarPedidoCulqi, req());

    expect(res.statusCode).toBe(502);
    expect(res.body.mensaje).toMatch(/pasarela de pago/i);
    expect(mock.contar(/UPDATE Pedidos\s+SET Estado = 'CONFIRMADO'/i)).toBe(0);
  });
});

describe('pagarPedidoCulqi — lo que se rechaza antes de tocar la tarjeta', () => {
  test('sin CULQI_SECRET_KEY responde 503 y NO toca la base', async () => {
    // El estado NORMAL del sistema hasta que el dueño termine el trámite de su
    // cuenta Culqi. Tiene que decirlo claro, no reventar.
    const { mock, publico, post } = preparar({ sinLlave: true });
    const { res } = await llamar(publico.pagarPedidoCulqi, req());

    expect(res.statusCode).toBe(503);
    expect(res.body.mensaje).toMatch(/no están configurados todavía/i);
    expect(post).not.toHaveBeenCalled();
    expect(mock.contar(/FROM Pedidos pd/i)).toBe(0);
  });

  test('sin token válido ni documento que coincida responde 404, no 403', async () => {
    // 404 a propósito: un 403 confirmaría que ese IdPedido existe, y los
    // IdPedido son correlativos.
    const { publico, post } = preparar();
    const { res } = await llamar(publico.pagarPedidoCulqi, req(body({ token: 'tokeninventado' })));

    expect(res.statusCode).toBe(404);
    expect(post).not.toHaveBeenCalled();
  });

  test('un pedido ya pagado no se vuelve a cobrar', async () => {
    const { publico, post } = preparar({
      pedido: { ...PEDIDO_ESPERANDO_PAGO, EstadoPagoAdelanto: 'PAGADO', Estado: 'CONFIRMADO' },
    });
    const { res } = await llamar(publico.pagarPedidoCulqi, req());

    expect(res.statusCode).toBe(400);
    expect(res.body.mensaje).toMatch(/ya está pagado/i);
    expect(post).not.toHaveBeenCalled();
  });

  test('un pedido de hamburguesa (NO_APLICA) no se puede pagar por acá', async () => {
    const { publico, post } = preparar({
      pedido: { ...PEDIDO_ESPERANDO_PAGO, EstadoPagoAdelanto: 'NO_APLICA', TokenConfirmacionPago: null },
    });
    const { res } = await llamar(publico.pagarPedidoCulqi, req(body({ token: undefined, documento: '12345678' })));

    expect(res.statusCode).toBe(400);
    expect(res.body.mensaje).toMatch(/no se paga por adelantado/i);
    expect(post).not.toHaveBeenCalled();
  });

  test('un pedido cancelado o rechazado no se cobra', async () => {
    for (const estado of ['CANCELADO', 'RECHAZADO']) {
      const { publico, post } = preparar({ pedido: { ...PEDIDO_ESPERANDO_PAGO, Estado: estado } });
      const { res } = await llamar(publico.pagarPedidoCulqi, req());

      expect(res.statusCode).toBe(400);
      expect(res.body.mensaje).toMatch(/ya no está activo/i);
      expect(post).not.toHaveBeenCalled();
    }
  });

  test('un token de tarjeta con forma inválida se corta antes de mirar el pedido', async () => {
    const { mock, publico, post } = preparar();
    const { res } = await llamar(publico.pagarPedidoCulqi, req(body({ culqiTokenId: 'no-es-un-token' })));

    expect(res.statusCode).toBe(400);
    expect(post).not.toHaveBeenCalled();
    expect(mock.contar(/FROM Pedidos pd/i)).toBe(0);
  });

  test('un correo mal escrito se rechaza acá, no en Culqi', async () => {
    // Culqi EXIGE el email (es a donde manda el comprobante). Dejar que lo
    // rechace la pasarela devolvería su texto, mucho menos claro que señalar
    // el campo.
    const { publico, post } = preparar();
    const { res } = await llamar(publico.pagarPedidoCulqi, req(body({ email: 'sin-arroba' })));

    expect(res.statusCode).toBe(400);
    expect(res.body.mensaje).toMatch(/correo válido/i);
    expect(post).not.toHaveBeenCalled();
  });

  test('un idPedido que no es un entero positivo no llega a la base', async () => {
    const { mock, publico } = preparar();
    const { res } = await llamar(publico.pagarPedidoCulqi, req(body(), { idPedido: 'abc' }));

    expect(res.statusCode).toBe(400);
    expect(mock.contar(/FROM Pedidos pd/i)).toBe(0);
  });
});

describe('pagarPedidoCulqi — el hueco: cobró Culqi pero falló la base', () => {
  test('se le dice la verdad con la referencia del cargo, y NO que reintente', async () => {
    // El único caso de todo el flujo donde el cliente pagó y el sistema no lo
    // refleja. No se puede devolver el dinero desde acá (eso es un reembolso,
    // que decide el dueño): lo que queda es dejar rastro del id de cargo y
    // decirle que NO vuelva a pagar.
    const { mock, publico } = preparar({ errorUpdate: true });
    const { res, next } = await llamar(publico.pagarPedidoCulqi, req());

    expect(next).not.toHaveBeenCalled();
    expect(res.statusCode).toBe(500);
    expect(res.body.mensaje).toMatch(/chr_test_abc123/);
    expect(res.body.mensaje).toMatch(/no vuelvas a pagar/i);
    // La transacción se deshace: el pedido no queda a medio confirmar.
    expect(mock.transaccion.rollback).toBe(1);
    expect(mock.transaccion.commit).toBe(0);
  });
});
