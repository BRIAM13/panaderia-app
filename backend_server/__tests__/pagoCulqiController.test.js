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
/** Un token de Yape, tal como lo emite CulqiJS v4 a partir del celular + código
 * de aprobación: prefijo `ype_`, no `tkn_` (visto en vivo el 2026-09-27:
 * `ype_test_SJzb9dQhW2xXsKFS`, cobrado con `venta_exitosa`). */
const TOKEN_YAPE = 'ype_test_SJzb9dQhW2xXsKFS';

/**
 * Las tres cifras de plata de un cobro, calculadas con las MISMAS funciones que
 * usa el controlador.
 *
 * Los números están escritos a mano en cada test igual (S/ 50 -> 5179 céntimos),
 * pero estos helpers existen para los tests que comprueban una PROPIEDAD y no un
 * número: el día que el dueño pase a producción y la tarifa cambie, los que
 * afirman "se le cobra el monto CON comisión" tienen que seguir pasando, y los
 * que afirman "5179" tienen que ponerse rojos a propósito, para que alguien
 * vuelva a mirar la cuenta.
 */
const { calcularMontoConComision } = require('../utils/pagoCulqi');
const { montoMinimoAPagar } = require('../utils/pagoAdelanto');

/** Lo que se le pide a Culqi (céntimos) por un abono de `neto` soles al pedido. */
function centimosConComision(neto) {
  return Math.round(calcularMontoConComision(neto).montoACobrar * 100);
}

/** La respuesta de un cargo exitoso, recortada a lo que el controlador lee.
 * `amount` viene en CÉNTIMOS, como manda Culqi.
 *
 * Por defecto contesta el cargo del camino feliz: el 100% de un pedido de S/ 50
 * MÁS la comisión, que es lo que de verdad se le cobra desde el 2026-09-28. */
function cargoExitoso({ amount = centimosConComision(50), id = 'chr_test_abc123' } = {}) {
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
    // S/ 51.79 -> 5179. Mandar `51.79` le cobraría S/ 0.52 a quien pidió S/ 50
    // de pan, y el pedido quedaría marcado como pagado.
    const { publico, post } = preparar();
    await llamar(publico.pagarPedidoCulqi, req());

    expect(post).toHaveBeenCalledTimes(1);
    const [url, cuerpo, opciones] = post.mock.calls[0];
    expect(url).toBe('https://api.culqi.com/v2/charges');
    expect(cuerpo.amount).toBe(5179);
    expect(Number.isInteger(cuerpo.amount)).toBe(true);
    expect(cuerpo.currency_code).toBe('PEN');
    expect(cuerpo.source_id).toBe(TOKEN_TARJETA);
    expect(cuerpo.email).toBe('cliente@correo.com');
    // La llave SECRETA va en el header, nunca en el cuerpo ni en la URL.
    expect(opciones.headers.Authorization).toBe(`Bearer ${LLAVE_FALSA}`);
  });

  test('el cargo sale por el monto CON comisión, no por el del pedido', async () => {
    // EL punto de la parte 2 (2026-09-28): la comisión de la pasarela la paga el
    // CLIENTE. Se le cobra S/ 51.79 para que, después de que Culqi se quede sus
    // S/ 1.79, al dueño le lleguen los S/ 50.00 limpios del pedido. Cobrar
    // S/ 50.00 dejaría al dueño pagando la comisión de su propio bolsillo en
    // cada pedido — que es justo lo que decidió no hacer.
    const { publico, post } = preparar();
    const { res } = await llamar(publico.pagarPedidoCulqi, req());

    expect(post.mock.calls[0][1].amount).toBe(5179);
    // Y NO por el monto del pedido: el candado explícito contra la regresión.
    expect(post.mock.calls[0][1].amount).not.toBe(5000);
    expect(post.mock.calls[0][1].amount).toBe(centimosConComision(50));

    // El desglose que la página le muestra al cliente: las tres cifras, y las
    // dos primeras tienen que sumar la tercera o el cliente ve un cobro que no
    // cuadra con nada.
    expect(res.body.montoElegido).toBe(50);
    expect(res.body.comision).toBe(1.79);
    expect(res.body.montoCobrado).toBe(51.79);
    expect(res.body.montoElegido + res.body.comision).toBeCloseTo(res.body.montoCobrado, 10);
    // Pero el PEDIDO se salda con los S/ 50, sin comisión adentro: si la
    // comisión entrara en la cuenta de saldos, saldría un VUELTO_PENDIENTE
    // fantasma de S/ 1.79 que el dueño tendría que devolver sin haberlo cobrado.
    expect(res.body.estadoPagoAdelanto).toBe('PAGADO');
    expect(res.body.ajuste).toBeNull();
  });

  test('la metadata del cargo lleva el desglose, para entenderlo desde el panel de Culqi', async () => {
    // Sin esto, un cargo de S/ 51.79 contra un pedido de S/ 50.00 no se entiende
    // sin abrir la base.
    const { publico, post } = preparar();
    await llamar(publico.pagarPedidoCulqi, req(body({ montoElegido: 25 })));

    expect(post.mock.calls[0][1].metadata).toEqual({
      idPedido: '900',
      numeroPedidoDia: '3',
      montoElegido: '25.00',
      comisionCulqi: '1.49',
    });
  });

  test('un token de Yape (ype_…) se cobra por el mismo camino que uno de tarjeta', async () => {
    // Culqi acepta el token de Yape como `source_id` del mismo POST /charges
    // (comprobado con un cargo real de prueba). Lo único que podía frenarlo
    // era la validación de forma de acá, que antes solo conocía `tkn_`.
    const { publico, post } = preparar();
    const { res } = await llamar(publico.pagarPedidoCulqi, req(body({ culqiTokenId: TOKEN_YAPE })));

    expect(res.statusCode).toBe(200);
    expect(res.body.estadoPagoAdelanto).toBe('PAGADO');
    expect(post).toHaveBeenCalledTimes(1);
    expect(post.mock.calls[0][1].source_id).toBe(TOKEN_YAPE);
  });

  test('un total con decimales se redondea al céntimo, sin perder ni uno', async () => {
    // 50.10 * 100 da 5009.999999999999 en punto flotante: truncar cobraría
    // S/ 50.09. Por eso la conversión redondea. Con la comisión encima,
    // (5010 + 118) / 0.9882 = 5189.23… -> 5189 céntimos.
    const { publico, post } = preparar({
      pedido: { ...PEDIDO_ESPERANDO_PAGO, Total: 50.1 },
      axiosPost: jest.fn().mockResolvedValue(cargoExitoso({ amount: 5189 })),
    });
    const { res } = await llamar(publico.pagarPedidoCulqi, req());

    expect(post.mock.calls[0][1].amount).toBe(5189);
    expect(res.body.montoElegido).toBe(50.1);
    expect(res.body.estadoPagoAdelanto).toBe('PAGADO');
    // Y ni el desglose ni el pedido arrastran cola de punto flotante.
    expect(res.body.comision).toBe(Number(res.body.comision.toFixed(2)));
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

  test('lo que Culqi diga haber cobrado NO cambia el saldo del pedido', async () => {
    // Antes del 2026-09-28 la cuenta de saldos se hacía con el `amount` que
    // devolvía Culqi, y tenía sentido: se le pedía exactamente el total. Ahora
    // ese número INCLUYE la comisión, así que usarlo daría un VUELTO_PENDIENTE
    // fantasma en cada pedido. La cuenta se hace con `montoElegido` y nada más.
    //
    // Se simula un `amount` disparatado a propósito: aunque Culqi contestara
    // cualquier cosa, el saldo del pedido no se mueve.
    const { mock, publico } = preparar({
      axiosPost: jest.fn().mockResolvedValue(cargoExitoso({ amount: 9999 })),
    });
    const { res } = await llamar(publico.pagarPedidoCulqi, req());

    expect(res.body.estadoPagoAdelanto).toBe('PAGADO');
    expect(res.body.ajuste).toBeNull();
    expect(mock.contar(/INSERT INTO AjustesPago/i)).toBe(0);
  });
});

/**
 * EL pedido del dueño del 2026-09-28: pagar el 50% para "separar" el pedido, y
 * el saldo al recoger. El saldo usa el mecanismo que ya existía (DEUDA_PARCIAL
 * + AjustesPago tipo DEUDA), lo único nuevo es dejar de asumir el 100%.
 */
describe('pagarPedidoCulqi — el pago parcial para separar el pedido', () => {
  test('el mínimo exacto (50%) se acepta y deja el saldo como DEUDA_PARCIAL', async () => {
    // S/ 25.00 de un pedido de S/ 50.00. El cargo sale por 25 + comisión = 2649
    // céntimos, y el ajuste es por los S/ 25.00 que FALTAN del pedido — sin
    // comisión adentro, porque la comisión no es parte del pedido y no se cobra
    // al recoger.
    const { mock, publico, post } = preparar({
      axiosPost: jest.fn().mockResolvedValue(cargoExitoso({ amount: centimosConComision(25) })),
    });
    const { res } = await llamar(publico.pagarPedidoCulqi, req(body({ montoElegido: 25 })));

    expect(res.statusCode).toBe(200);
    expect(res.body.estado).toBe('CONFIRMADO');
    expect(res.body.estadoPagoAdelanto).toBe('DEUDA_PARCIAL');
    expect(res.body.montoElegido).toBe(25);
    expect(res.body.comision).toBe(1.49);
    expect(res.body.montoCobrado).toBe(26.49);
    expect(res.body.total).toBe(50);
    expect(res.body.ajuste).toEqual({ idAjuste: 77, tipo: 'DEUDA', monto: 25, estado: 'PENDIENTE' });

    // A Culqi se le pide el monto CON comisión.
    expect(post.mock.calls[0][1].amount).toBe(2649);
    // El ajuste en base: los S/ 25 del pedido, NO los S/ 26.49 cobrados.
    expect(mock.consultasQueMatcheen(/INSERT INTO AjustesPago/i)[0].valores).toEqual([900, 'DEUDA', 25]);
    // `MontoConfirmadoStaff` guarda lo que entró AL PEDIDO, no el cargo.
    expect(mock.consultasQueMatcheen(/UPDATE Pedidos\s+SET Estado = 'CONFIRMADO'/i)[0].valores).toEqual([
      'DEUDA_PARCIAL',
      25,
      900,
    ]);
    // Y la cuenta cierra: lo abonado + la deuda = el total del pedido.
    expect(res.body.montoElegido + res.body.ajuste.monto).toBe(res.body.total);
  });

  test('el máximo (el 100% del total) se acepta y da PAGADO sin ajuste', async () => {
    const { mock, publico } = preparar();
    const { res } = await llamar(publico.pagarPedidoCulqi, req(body({ montoElegido: 50 })));

    expect(res.statusCode).toBe(200);
    expect(res.body.estadoPagoAdelanto).toBe('PAGADO');
    expect(res.body.ajuste).toBeNull();
    expect(mock.contar(/INSERT INTO AjustesPago/i)).toBe(0);
  });

  test('un monto intermedio (campo libre, no dos botones) también vale', async () => {
    // El dueño pidió un campo libre entre el 50% y el 100%, no solo "mitad" o
    // "todo": el 70% tiene que pasar igual.
    const { mock, publico, post } = preparar({
      axiosPost: jest.fn().mockResolvedValue(cargoExitoso({ amount: centimosConComision(35) })),
    });
    const { res } = await llamar(publico.pagarPedidoCulqi, req(body({ montoElegido: 35 })));

    expect(res.statusCode).toBe(200);
    expect(res.body.estadoPagoAdelanto).toBe('DEUDA_PARCIAL');
    expect(res.body.ajuste.monto).toBe(15);
    expect(post.mock.calls[0][1].amount).toBe(centimosConComision(35));
    expect(mock.consultasQueMatcheen(/INSERT INTO AjustesPago/i)[0].valores).toEqual([900, 'DEUDA', 15]);
  });

  test('un céntimo por debajo del mínimo se rechaza con 400 y NO se le cobra nada', async () => {
    // S/ 24.99 de un pedido de S/ 50.00. Es el borde exacto: un `>=` mal puesto
    // acá dejaría separar un pedido con menos de lo que el dueño decidió.
    const { mock, publico, post } = preparar();
    const { res, next } = await llamar(publico.pagarPedidoCulqi, req(body({ montoElegido: 24.99 })));

    expect(next).not.toHaveBeenCalled();
    expect(res.statusCode).toBe(400);
    expect(res.body.mensaje).toMatch(/al menos S\/ 25\.00/);
    // La tarjeta no se toca: un rechazo de validación no puede cobrar nada.
    expect(post).not.toHaveBeenCalled();
    expect(mock.contar(/UPDATE Pedidos\s+SET Estado = 'CONFIRMADO'/i)).toBe(0);
    // El pedido sigue esperando pago, y el mínimo viaja en la respuesta para
    // que la página pueda corregir el campo sin hacer la cuenta de nuevo.
    expect(res.body.estadoPagoAdelanto).toBe('VERIFICANDO');
    expect(res.body.montoMinimo).toBe(25);
    expect(res.body.total).toBe(50);
  });

  test('un monto muy por debajo del mínimo se rechaza igual', async () => {
    const { publico, post } = preparar();
    const { res } = await llamar(publico.pagarPedidoCulqi, req(body({ montoElegido: 1 })));

    expect(res.statusCode).toBe(400);
    expect(post).not.toHaveBeenCalled();
  });

  test('pagar MÁS que el total se rechaza: el techo es el pedido', async () => {
    // El techo lo pone la base, no el body. Sin esto, un body con
    // montoElegido: 5000 haría un cargo de S/ 5000 y un VUELTO_PENDIENTE de
    // S/ 4950 que el dueño tendría que devolver de su bolsillo.
    const { publico, post } = preparar();
    const { res } = await llamar(publico.pagarPedidoCulqi, req(body({ montoElegido: 50.01 })));

    expect(res.statusCode).toBe(400);
    expect(res.body.mensaje).toMatch(/como máximo su total de S\/ 50\.00/);
    expect(post).not.toHaveBeenCalled();
  });

  test('VUELTO_PENDIENTE es imposible por este endpoint', async () => {
    // El techo de la validación es el total, así que el cliente no puede abonar
    // de más a su pedido por acá. Es la diferencia de fondo con el flujo de
    // Yape, donde el monto lo declaraba él.
    const { mock, publico } = preparar();
    for (const montoElegido of [50, 25, 37.5, undefined]) {
      const { res } = await llamar(publico.pagarPedidoCulqi, req(body({ montoElegido })));
      expect(res.body.estadoPagoAdelanto).not.toBe('VUELTO_PENDIENTE');
    }
    expect(mock.contar(/INSERT INTO AjustesPago.*VUELTO/is)).toBe(0);
  });

  test('un montoElegido basura se rechaza, no se cuela como NaN hasta la pasarela', async () => {
    // `Number('mucho')` es NaN, y NaN falla toda comparación en silencio: sin la
    // guarda de `Number.isFinite`, NaN pasaría los dos `<`/`>` y llegaría a
    // `aCentimosCulqi`, que sí lo corta — pero con un mensaje de "no se puede
    // cobrar", que no le dice al cliente qué escribir.
    for (const montoElegido of ['mucho', NaN, Infinity, -25, 0, {}, [], true]) {
      const { publico, post } = preparar();
      const { res, next } = await llamar(publico.pagarPedidoCulqi, req(body({ montoElegido })));

      expect(next).not.toHaveBeenCalled();
      expect(res.statusCode).toBe(400);
      expect(res.body.mensaje).toMatch(/al menos S\/ 25\.00/);
      expect(post).not.toHaveBeenCalled();
    }
  });

  test('sin montoElegido en el body se asume el 100% (la página anterior no lo mandaba)', async () => {
    // Compatibilidad hacia atrás: un cliente con la página vieja en caché no
    // puede empezar a recibir un 400 por un campo que su versión no conoce.
    for (const cuerpo of [body(), body({ montoElegido: undefined }), body({ montoElegido: null })]) {
      const { publico, post } = preparar();
      const { res } = await llamar(publico.pagarPedidoCulqi, req(cuerpo));

      expect(res.statusCode).toBe(200);
      expect(res.body.estadoPagoAdelanto).toBe('PAGADO');
      expect(res.body.montoElegido).toBe(50);
      expect(post.mock.calls[0][1].amount).toBe(centimosConComision(50));
    }
  });

  test('un montoElegido en texto (body JSON flojo) se trata como número', async () => {
    const { publico, post } = preparar({
      axiosPost: jest.fn().mockResolvedValue(cargoExitoso({ amount: centimosConComision(25) })),
    });
    const { res } = await llamar(publico.pagarPedidoCulqi, req(body({ montoElegido: '25.00' })));

    expect(res.statusCode).toBe(200);
    expect(res.body.montoElegido).toBe(25);
    expect(post.mock.calls[0][1].amount).toBe(2649);
  });

  test('el mínimo se compara EN CÉNTIMOS: un total impar no rechaza el mínimo que se mostró', async () => {
    // Total S/ 50.05 -> mínimo S/ 25.03 (redondeado hacia arriba). En soles
    // decimales, `25.03 >= 50.05 * 0.5` arrastra la cola de punto flotante y es
    // justo la comparación que rechazaría el monto exacto que la página le
    // mostró al cliente.
    const pedido = { ...PEDIDO_ESPERANDO_PAGO, Total: 50.05 };
    expect(montoMinimoAPagar(50.05)).toBe(25.03);

    const { publico, post } = preparar({
      pedido,
      axiosPost: jest.fn().mockResolvedValue(cargoExitoso({ amount: centimosConComision(25.03) })),
    });
    const { res } = await llamar(publico.pagarPedidoCulqi, req(body({ montoElegido: 25.03 })));

    expect(res.statusCode).toBe(200);
    expect(res.body.estadoPagoAdelanto).toBe('DEUDA_PARCIAL');
    expect(res.body.ajuste.monto).toBe(25.02);
    expect(post.mock.calls[0][1].amount).toBe(centimosConComision(25.03));

    // Y el céntimo de abajo (S/ 25.02, la mitad exacta hacia abajo) NO pasa.
    const { publico: p2, post: post2 } = preparar({ pedido });
    const { res: res2 } = await llamar(p2.pagarPedidoCulqi, req(body({ montoElegido: 25.02 })));
    expect(res2.statusCode).toBe(400);
    expect(post2).not.toHaveBeenCalled();
  });

  test('el mensaje va dirigido al CLIENTE, no al personal', async () => {
    // `describirResultadoPago` dice "falta S/ 25.00: cóbralo al entregar", que es
    // una orden para quien atiende. Mientras DEUDA_PARCIAL era raro casi no se
    // notaba; ahora es el camino normal de la mitad de los pedidos.
    const { publico } = preparar({
      axiosPost: jest.fn().mockResolvedValue(cargoExitoso({ amount: centimosConComision(25) })),
    });
    const { res } = await llamar(publico.pagarPedidoCulqi, req(body({ montoElegido: 25 })));

    expect(res.body.mensaje).toMatch(/quedó separado con S\/ 25\.00/);
    expect(res.body.mensaje).toMatch(/S\/ 25\.00 que faltan los pagas cuando lo recojas/);
    // Nada dirigido a otra persona.
    expect(res.body.mensaje).not.toMatch(/cóbralo|devuélvelo|Pago verificado/i);
  });

  test('pagado al 100%, el mensaje no habla de ningún saldo', async () => {
    const { publico } = preparar();
    const { res } = await llamar(publico.pagarPedidoCulqi, req(body({ montoElegido: 50 })));

    expect(res.body.mensaje).toMatch(/pagado por completo/i);
    expect(res.body.mensaje).not.toMatch(/falta|separado|recojas/i);
  });

  test('un pago parcial deja en auditoría las tres cifras, sin columnas nuevas en la base', async () => {
    // Es lo único que va a quedar de "cuánto pagó el cliente de más por la
    // comisión": no hay columna para eso, y el dueño decidió que no hacía falta.
    const { mock, publico } = preparar({
      axiosPost: jest.fn().mockResolvedValue(cargoExitoso({ amount: centimosConComision(25) })),
    });
    await llamar(publico.pagarPedidoCulqi, req(body({ montoElegido: 25 })));

    const auditorias = mock.consultasQueMatcheen(/INSERT INTO Auditoria/i);
    expect(auditorias).toHaveLength(1);
    const datos = JSON.parse(auditorias[0].valores.find((v) => typeof v === 'string' && v.startsWith('{')));
    expect(datos).toMatchObject({
      total: 50,
      montoElegido: 25,
      comision: 1.49,
      montoACobrar: 26.49,
      estadoPagoAdelanto: 'DEUDA_PARCIAL',
      culqiChargeId: 'chr_test_abc123',
    });
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
