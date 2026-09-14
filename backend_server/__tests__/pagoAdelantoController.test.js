const { instalarMockMysql, crearRes, crearReq } = require('./helpers/mysqlMock');

/**
 * Los caminos del pago por adelantado que NO son cuenta pura y por lo tanto
 * no caben en pagoAdelanto.test.js: el rechazo del código repetido (que lo
 * decide un UNIQUE de la base, no el código), el rechazo del monto menor al
 * total, la máquina de estados, y que un pedido de hamburguesa siga
 * pasando por el flujo de siempre sin rozar nada de esto.
 *
 * Se mockea `mysql2/promise` y no `config/db.js`, igual que
 * pedidosController.test.js: así corre de verdad el shim que traduce el
 * T-SQL, que es donde se rompería algo en silencio.
 */

/** El pedido web de Panadería tal como lo devuelve el SELECT de
 * registrarCodigoPagoPublico: ya creado, esperando su código. */
const PEDIDO_ESPERANDO_CODIGO = {
  IdPedido: 900,
  NumeroPedidoDia: 3,
  IdTienda: 1,
  Total: 50,
  Estado: 'SOLICITADO',
  EstadoPagoAdelanto: 'VERIFICANDO',
  CodigoOperacionYape: null,
  TokenConfirmacionPago: 'tokenbueno123',
  DNI: '12345678',
};

function prepararPublico(mock, { pedido = PEDIDO_ESPERANDO_CODIGO } = {}) {
  mock.responder(/FROM Pedidos pd\s+INNER JOIN Clientes c/i, pedido ? [pedido] : []);
  mock.responder(/FROM DispositivosNotificacion|INSERT INTO Auditoria/i, []);
  return mock;
}

async function llamar(controller, req) {
  const res = crearRes();
  const next = jest.fn();
  await controller(req, res, next);
  return { res, next };
}

describe('registrarCodigoPagoPublico', () => {
  let mock;
  let publico;

  beforeEach(() => {
    jest.resetModules();
    mock = instalarMockMysql();
    prepararPublico(mock);
    publico = require('../controllers/publicoController');
  });

  function req(body, params = { idPedido: '900' }) {
    return crearReq({ body, params });
  }

  test('el camino feliz guarda código y monto y deja el estado en VERIFICANDO', async () => {
    const { res } = await llamar(
      publico.registrarCodigoPagoPublico,
      req({ token: 'tokenbueno123', codigoOperacionYape: '1234567', montoDeclaradoCliente: 50 }),
    );

    expect(res.statusCode).toBe(200);
    // El estado NO cambia acá: solo el personal puede moverlo, verificando
    // el movimiento real en Yape.
    expect(res.body.estadoPagoAdelanto).toBe('VERIFICANDO');
    expect(res.body.codigoOperacionYape).toBe('1234567');

    const update = mock.consultasQueMatcheen(/UPDATE Pedidos\s+SET CodigoOperacionYape/i);
    expect(update).toHaveLength(1);
    expect(update[0].valores).toEqual(['1234567', 50, 900]);
    // La guarda `AND CodigoOperacionYape IS NULL` viaja en el UPDATE: si dos
    // envíos del mismo cliente se cruzan, el segundo no pisa al primero.
    expect(update[0].texto).toMatch(/CodigoOperacionYape IS NULL/i);
  });

  test('un código ya usado en otro pedido se rechaza con 400, no con un 500 genérico', async () => {
    // El rechazo lo produce UQ_Pedidos_CodigoOperacionYape en la base — es
    // el único mecanismo que aguanta dos envíos simultáneos del mismo
    // código. Acá se comprueba que ese error se traduce a algo que el
    // cliente pueda entender y no se escape como error inesperado.
    const duplicado = Object.assign(new Error('Duplicate entry'), { code: 'ER_DUP_ENTRY', errno: 1062 });
    mock.responder(/UPDATE Pedidos\s+SET CodigoOperacionYape/i, duplicado);

    const { res, next } = await llamar(
      publico.registrarCodigoPagoPublico,
      req({ token: 'tokenbueno123', codigoOperacionYape: '1234567', montoDeclaradoCliente: 50 }),
    );

    expect(next).not.toHaveBeenCalled();
    expect(res.statusCode).toBe(400);
    expect(res.body.mensaje).toMatch(/ya fue usado en otro pedido/i);
  });

  test('declarar menos que el total se rechaza y no se escribe nada', async () => {
    const { res } = await llamar(
      publico.registrarCodigoPagoPublico,
      req({ token: 'tokenbueno123', codigoOperacionYape: '1234567', montoDeclaradoCliente: 5 }),
    );

    expect(res.statusCode).toBe(400);
    expect(res.body.mensaje).toMatch(/menor que el total/i);
    expect(mock.contar(/UPDATE Pedidos\s+SET CodigoOperacionYape/i)).toBe(0);
  });

  test('un código con letras se rechaza antes de tocar la base', async () => {
    const { res } = await llamar(
      publico.registrarCodigoPagoPublico,
      req({ token: 'tokenbueno123', codigoOperacionYape: 'ABC1234', montoDeclaradoCliente: 50 }),
    );

    expect(res.statusCode).toBe(400);
    expect(mock.contar(/FROM Pedidos pd\s+INNER JOIN Clientes c/i)).toBe(0);
  });

  test('sin token válido ni documento que coincida responde 404, no 403', async () => {
    // 404 a propósito: un 403 confirmaría que ese IdPedido existe, y los
    // IdPedido son correlativos.
    const { res } = await llamar(
      publico.registrarCodigoPagoPublico,
      req({ token: 'tokeninventado', codigoOperacionYape: '1234567', montoDeclaradoCliente: 50 }),
    );

    expect(res.statusCode).toBe(404);
    expect(mock.contar(/UPDATE Pedidos\s+SET CodigoOperacionYape/i)).toBe(0);
  });

  test('el DNI del propio cliente sirve como segunda vía (otro dispositivo, sin localStorage)', async () => {
    const { res } = await llamar(
      publico.registrarCodigoPagoPublico,
      req({ documento: '12345678', codigoOperacionYape: '7654321', montoDeclaradoCliente: 50 }),
    );

    expect(res.statusCode).toBe(200);
    expect(mock.contar(/UPDATE Pedidos\s+SET CodigoOperacionYape/i)).toBe(1);
  });

  test('un pedido que ya mandó su código no acepta otro', async () => {
    jest.resetModules();
    mock = instalarMockMysql();
    prepararPublico(mock, {
      pedido: { ...PEDIDO_ESPERANDO_CODIGO, CodigoOperacionYape: '1111111' },
    });
    publico = require('../controllers/publicoController');

    const { res } = await llamar(
      publico.registrarCodigoPagoPublico,
      req({ token: 'tokenbueno123', codigoOperacionYape: '2222222', montoDeclaradoCliente: 50 }),
    );

    expect(res.statusCode).toBe(400);
    expect(res.body.mensaje).toMatch(/ya registramos un código/i);
    expect(mock.contar(/UPDATE Pedidos\s+SET CodigoOperacionYape/i)).toBe(0);
  });

  test('un pedido de hamburguesa (NO_APLICA) no acepta códigos de pago', async () => {
    jest.resetModules();
    mock = instalarMockMysql();
    prepararPublico(mock, {
      pedido: { ...PEDIDO_ESPERANDO_CODIGO, EstadoPagoAdelanto: 'NO_APLICA', TokenConfirmacionPago: null },
    });
    publico = require('../controllers/publicoController');

    const { res } = await llamar(
      publico.registrarCodigoPagoPublico,
      req({ documento: '12345678', codigoOperacionYape: '1234567', montoDeclaradoCliente: 50 }),
    );

    expect(res.statusCode).toBe(400);
    expect(res.body.mensaje).toMatch(/no se paga por adelantado/i);
  });

  test('un pago ya verificado por la tienda no se puede volver a reportar', async () => {
    jest.resetModules();
    mock = instalarMockMysql();
    prepararPublico(mock, {
      pedido: { ...PEDIDO_ESPERANDO_CODIGO, EstadoPagoAdelanto: 'PAGADO', Estado: 'CONFIRMADO' },
    });
    publico = require('../controllers/publicoController');

    const { res } = await llamar(
      publico.registrarCodigoPagoPublico,
      req({ token: 'tokenbueno123', codigoOperacionYape: '1234567', montoDeclaradoCliente: 50 }),
    );

    expect(res.statusCode).toBe(400);
    expect(res.body.mensaje).toMatch(/ya fue verificado/i);
  });
});

describe('confirmarPagoAdelanto (personal)', () => {
  let mock;
  let pagoAdelanto;

  function prepararPersonal({ pedido }) {
    jest.resetModules();
    mock = instalarMockMysql();
    // obtenerPedidoConAcceso, reexportado desde pedidosController.
    mock.responder(/SELECT IdPedido, NumeroPedidoDia, IdCliente, IdTienda, Estado, Total, EstadoPagoAdelanto/i, [pedido]);
    mock.responderInsert(/INSERT INTO AjustesPago/i, 77);
    mock.responder(/FROM DispositivosNotificacion|INSERT INTO Auditoria/i, []);
    pagoAdelanto = require('../controllers/pagoAdelantoController');
    return mock;
  }

  const PEDIDO = {
    IdPedido: 900,
    NumeroPedidoDia: 3,
    IdCliente: 5,
    IdTienda: 1,
    Estado: 'SOLICITADO',
    Total: 50,
    EstadoPagoAdelanto: 'VERIFICANDO',
  };

  // SUPERADMIN tiene acceso implícito a cualquier tienda: así no hace falta
  // simular TrabajadorTiendas para probar lo que estos casos sí miran.
  function reqPersonal(body) {
    return crearReq({ body, params: { id: '900' }, usuario: { rol: 'SUPERADMIN' } });
  }

  test('monto exacto: PAGADO, pedido CONFIRMADO y NINGÚN ajuste creado', async () => {
    prepararPersonal({ pedido: PEDIDO });
    const { res } = await llamar(pagoAdelanto.confirmarPagoAdelanto, reqPersonal({ montoConfirmado: 50 }));

    expect(res.statusCode).toBe(200);
    expect(res.body.estadoPagoAdelanto).toBe('PAGADO');
    expect(res.body.estado).toBe('CONFIRMADO');
    expect(res.body.ajuste).toBeNull();
    expect(mock.contar(/INSERT INTO AjustesPago/i)).toBe(0);
    expect(mock.transaccion.commit).toBe(1);
  });

  test('pagó de menos: DEUDA_PARCIAL + un ajuste DEUDA por la diferencia', async () => {
    prepararPersonal({ pedido: PEDIDO });
    const { res } = await llamar(pagoAdelanto.confirmarPagoAdelanto, reqPersonal({ montoConfirmado: 48 }));

    expect(res.body.estadoPagoAdelanto).toBe('DEUDA_PARCIAL');
    expect(res.body.ajuste).toEqual({ idAjuste: 77, tipo: 'DEUDA', monto: 2, estado: 'PENDIENTE' });
    const insert = mock.consultasQueMatcheen(/INSERT INTO AjustesPago/i);
    expect(insert).toHaveLength(1);
    expect(insert[0].valores).toEqual([900, 'DEUDA', 2]);
  });

  test('pagó de más: VUELTO_PENDIENTE + un ajuste VUELTO por la diferencia', async () => {
    prepararPersonal({ pedido: PEDIDO });
    const { res } = await llamar(pagoAdelanto.confirmarPagoAdelanto, reqPersonal({ montoConfirmado: 53 }));

    expect(res.body.estadoPagoAdelanto).toBe('VUELTO_PENDIENTE');
    expect(res.body.ajuste).toEqual({ idAjuste: 77, tipo: 'VUELTO', monto: 3, estado: 'PENDIENTE' });
    expect(mock.consultasQueMatcheen(/INSERT INTO AjustesPago/i)[0].valores).toEqual([900, 'VUELTO', 3]);
  });

  test('un pedido que NO se pagó por adelantado no se puede confirmar por acá', async () => {
    prepararPersonal({ pedido: { ...PEDIDO, EstadoPagoAdelanto: 'NO_APLICA' } });
    const { res } = await llamar(pagoAdelanto.confirmarPagoAdelanto, reqPersonal({ montoConfirmado: 50 }));

    expect(res.statusCode).toBe(400);
    expect(res.body.mensaje).toMatch(/no se pagó por adelantado/i);
    expect(mock.contar(/UPDATE Pedidos/i)).toBe(0);
  });

  test('no se puede verificar dos veces el mismo pago', async () => {
    prepararPersonal({ pedido: { ...PEDIDO, EstadoPagoAdelanto: 'PAGADO', Estado: 'CONFIRMADO' } });
    const { res } = await llamar(pagoAdelanto.confirmarPagoAdelanto, reqPersonal({ montoConfirmado: 50 }));

    expect(res.statusCode).toBe(400);
    expect(res.body.mensaje).toMatch(/ya fue verificado/i);
  });

  test('sin monto (o con uno absurdo) se rechaza antes de mirar el pedido', async () => {
    prepararPersonal({ pedido: PEDIDO });
    const sinMonto = await llamar(pagoAdelanto.confirmarPagoAdelanto, reqPersonal({}));
    expect(sinMonto.res.statusCode).toBe(400);

    prepararPersonal({ pedido: PEDIDO });
    const negativo = await llamar(pagoAdelanto.confirmarPagoAdelanto, reqPersonal({ montoConfirmado: -5 }));
    expect(negativo.res.statusCode).toBe(400);
    expect(mock.contar(/UPDATE Pedidos/i)).toBe(0);
  });
});

describe('los pedidos de hamburguesa quedan fuera de todo esto', () => {
  test('aprobar un pedido de hamburguesa sigue funcionando igual que siempre', async () => {
    jest.resetModules();
    const mock = instalarMockMysql();
    mock.responder(/SELECT IdPedido, NumeroPedidoDia, IdCliente, IdTienda, Estado, Total, EstadoPagoAdelanto/i, [
      {
        IdPedido: 901,
        NumeroPedidoDia: 4,
        IdCliente: 5,
        IdTienda: 2,
        Estado: 'SOLICITADO',
        Total: 30,
        // Es el valor por defecto de la columna: todo pedido que no venga
        // del flujo web de Panadería lo tiene.
        EstadoPagoAdelanto: 'NO_APLICA',
      },
    ]);
    mock.responder(/FROM DispositivosNotificacion|INSERT INTO Auditoria/i, []);
    const pedidos = require('../controllers/pedidosController');

    const { res } = await llamar(
      pedidos.aprobarPedido,
      crearReq({ params: { id: '901' }, usuario: { rol: 'SUPERADMIN' } }),
    );

    expect(res.statusCode).toBe(200);
    expect(mock.contar(/SET Estado = 'PENDIENTE'/i)).toBe(1);
  });

  test('un pedido de Panadería esperando verificación NO se puede aprobar a mano', async () => {
    jest.resetModules();
    const mock = instalarMockMysql();
    mock.responder(/SELECT IdPedido, NumeroPedidoDia, IdCliente, IdTienda, Estado, Total, EstadoPagoAdelanto/i, [
      {
        IdPedido: 900,
        NumeroPedidoDia: 3,
        IdCliente: 5,
        IdTienda: 1,
        Estado: 'SOLICITADO',
        Total: 50,
        EstadoPagoAdelanto: 'VERIFICANDO',
      },
    ]);
    mock.responder(/FROM DispositivosNotificacion|INSERT INTO Auditoria/i, []);
    const pedidos = require('../controllers/pedidosController');

    const { res } = await llamar(
      pedidos.aprobarPedido,
      crearReq({ params: { id: '900' }, usuario: { rol: 'SUPERADMIN' } }),
    );

    expect(res.statusCode).toBe(400);
    expect(res.body.mensaje).toMatch(/verifica el pago/i);
    expect(mock.contar(/SET Estado = 'PENDIENTE'/i)).toBe(0);
  });

  test('entregar un pedido pagado por adelantado NUNCA lo deja como DEUDA', async () => {
    // `EstadoPago = 'DEUDA'` significa, en todos los reportes del sistema,
    // que se debe el Total COMPLETO. Un pedido que ya adelantó su plata no
    // puede entrar ahí ni aunque el personal toque "queda como deuda": lo
    // que falte vive en su fila de AjustesPago.
    jest.resetModules();
    const mock = instalarMockMysql();
    mock.responder(/SELECT IdPedido, NumeroPedidoDia, IdCliente, IdTienda, Estado, Total, EstadoPagoAdelanto/i, [
      {
        IdPedido: 900,
        NumeroPedidoDia: 3,
        IdCliente: 5,
        IdTienda: 1,
        Estado: 'CONFIRMADO',
        Total: 50,
        EstadoPagoAdelanto: 'DEUDA_PARCIAL',
      },
    ]);
    mock.responder(/CLIENTES_SOLES_POR_PUNTO/i, [{ Valor: '10' }]);
    mock.responder(/FROM DispositivosNotificacion|INSERT INTO Auditoria/i, []);
    const pedidos = require('../controllers/pedidosController');

    const { res } = await llamar(
      pedidos.entregarPedido,
      crearReq({ body: { pagado: false }, params: { id: '900' }, usuario: { rol: 'SUPERADMIN' } }),
    );

    expect(res.statusCode).toBe(200);
    const update = mock.consultasQueMatcheen(/SET Estado = 'ENTREGADO'/i);
    expect(update).toHaveLength(1);
    expect(update[0].valores[0]).toBe('PAGADO');
  });

  test('un pedido normal SIN adelanto sí puede quedar como DEUDA al entregarse', async () => {
    jest.resetModules();
    const mock = instalarMockMysql();
    mock.responder(/SELECT IdPedido, NumeroPedidoDia, IdCliente, IdTienda, Estado, Total, EstadoPagoAdelanto/i, [
      {
        IdPedido: 901,
        NumeroPedidoDia: 4,
        IdCliente: 5,
        IdTienda: 2,
        Estado: 'PENDIENTE',
        Total: 30,
        EstadoPagoAdelanto: 'NO_APLICA',
      },
    ]);
    mock.responder(/CLIENTES_SOLES_POR_PUNTO/i, [{ Valor: '10' }]);
    mock.responder(/FROM DispositivosNotificacion|INSERT INTO Auditoria/i, []);
    const pedidos = require('../controllers/pedidosController');

    const { res } = await llamar(
      pedidos.entregarPedido,
      crearReq({ body: { pagado: false }, params: { id: '901' }, usuario: { rol: 'SUPERADMIN' } }),
    );

    expect(res.statusCode).toBe(200);
    expect(mock.consultasQueMatcheen(/SET Estado = 'ENTREGADO'/i)[0].valores[0]).toBe('DEUDA');
  });
});
