const {
  validateConsultarPedidosPublico,
  validateSolicitarRecuperacion,
  validateConfirmarRecuperacion,
  validarItemsPedido,
  MAXIMO_ITEMS_POR_PEDIDO,
} = require('../middlewares/validators');

/** Simula res.status(x).json(y) capturando lo que se llamó, sin necesitar
 * un servidor HTTP real — suficiente para un middleware que solo lee
 * req.query y responde 400 o llama next(). */
function crearResFalso() {
  const res = {};
  res.status = jest.fn().mockReturnValue(res);
  res.json = jest.fn().mockReturnValue(res);
  return res;
}

describe('validateConsultarPedidosPublico', () => {
  test('acepta un DNI válido de 8 dígitos', () => {
    const req = { query: { dni: '12345678' } };
    const res = crearResFalso();
    const next = jest.fn();

    validateConsultarPedidosPublico(req, res, next);

    expect(next).toHaveBeenCalledTimes(1);
    expect(res.status).not.toHaveBeenCalled();
  });

  test('acepta un RUC válido de 11 dígitos (agregado para el seguimiento público por RUC)', () => {
    const req = { query: { dni: '20123456789' } };
    const res = crearResFalso();
    const next = jest.fn();

    validateConsultarPedidosPublico(req, res, next);

    expect(next).toHaveBeenCalledTimes(1);
    expect(res.status).not.toHaveBeenCalled();
  });

  test('rechaza con 400 un documento que no tiene ni 8 ni 11 dígitos', () => {
    const req = { query: { dni: '123' } };
    const res = crearResFalso();
    const next = jest.fn();

    validateConsultarPedidosPublico(req, res, next);

    expect(next).not.toHaveBeenCalled();
    expect(res.status).toHaveBeenCalledWith(400);
  });

  test('rechaza con 400 cuando no viene ningún documento', () => {
    const req = { query: {} };
    const res = crearResFalso();
    const next = jest.fn();

    validateConsultarPedidosPublico(req, res, next);

    expect(next).not.toHaveBeenCalled();
    expect(res.status).toHaveBeenCalledWith(400);
  });
});

describe('validateSolicitarRecuperacion', () => {
  test('acepta un nombreUsuario no vacío (en la práctica, el DNI/RUC del login)', () => {
    const req = { body: { nombreUsuario: '12345678' } };
    const res = crearResFalso();
    const next = jest.fn();

    validateSolicitarRecuperacion(req, res, next);

    expect(next).toHaveBeenCalledTimes(1);
    expect(res.status).not.toHaveBeenCalled();
  });

  test('rechaza con 400 si no viene nombreUsuario', () => {
    const req = { body: {} };
    const res = crearResFalso();
    const next = jest.fn();

    validateSolicitarRecuperacion(req, res, next);

    expect(next).not.toHaveBeenCalled();
    expect(res.status).toHaveBeenCalledWith(400);
  });
});

describe('validateConfirmarRecuperacion', () => {
  test('acepta nombreUsuario + código de 6 dígitos + contraseña de al menos 8 caracteres', () => {
    const req = { body: { nombreUsuario: '12345678', codigo: '004821', passwordNueva: 'nuevaClave123' } };
    const res = crearResFalso();
    const next = jest.fn();

    validateConfirmarRecuperacion(req, res, next);

    expect(next).toHaveBeenCalledTimes(1);
    expect(res.status).not.toHaveBeenCalled();
  });

  test('rechaza con 400 un código que no tiene 6 dígitos', () => {
    const req = { body: { nombreUsuario: '12345678', codigo: '123', passwordNueva: 'nuevaClave123' } };
    const res = crearResFalso();
    const next = jest.fn();

    validateConfirmarRecuperacion(req, res, next);

    expect(next).not.toHaveBeenCalled();
    expect(res.status).toHaveBeenCalledWith(400);
  });

  test('rechaza con 400 una contraseña nueva de menos de 8 caracteres', () => {
    const req = { body: { nombreUsuario: '12345678', codigo: '004821', passwordNueva: 'corta' } };
    const res = crearResFalso();
    const next = jest.fn();

    validateConfirmarRecuperacion(req, res, next);

    expect(next).not.toHaveBeenCalled();
    expect(res.status).toHaveBeenCalledWith(400);
  });

  test('rechaza con 400 si falta nombreUsuario', () => {
    const req = { body: { codigo: '004821', passwordNueva: 'nuevaClave123' } };
    const res = crearResFalso();
    const next = jest.fn();

    validateConfirmarRecuperacion(req, res, next);

    expect(next).not.toHaveBeenCalled();
    expect(res.status).toHaveBeenCalledWith(400);
  });
});

/**
 * Regla compartida por las tres vías que crean pedidos de catálogo
 * (personal, autoservicio y página web): lo único que cambia entre ellas es
 * qué campos manda el cliente y cuáles deriva el controller.
 */
describe('validarItemsPedido', () => {
  const itemValido = { idProducto: 3, tipoPedido: 'UNIDADES', cantidad: 10, precioUnitario: 1.5 };

  test('un carrito válido no devuelve errores', () => {
    expect(validarItemsPedido([itemValido], { requierePrecio: true, requiereTipoPedido: true })).toEqual([]);
  });

  test('rechaza un carrito vacío o ausente', () => {
    expect(validarItemsPedido([])).toHaveLength(1);
    expect(validarItemsPedido(undefined)).toHaveLength(1);
    expect(validarItemsPedido(null)).toHaveLength(1);
    // Un objeto suelto no es un carrito: el body viejo (un producto plano)
    // tiene que fallar, no colarse como si fuera una línea.
    expect(validarItemsPedido(itemValido)).toHaveLength(1);
  });

  test('rechaza más líneas que el máximo permitido', () => {
    const muchos = Array.from({ length: MAXIMO_ITEMS_POR_PEDIDO + 1 }, () => itemValido);
    const errores = validarItemsPedido(muchos);
    expect(errores).toHaveLength(1);
    expect(errores[0]).toMatch(new RegExp(String(MAXIMO_ITEMS_POR_PEDIDO)));
  });

  test('acepta exactamente el máximo', () => {
    const justos = Array.from({ length: MAXIMO_ITEMS_POR_PEDIDO }, () => itemValido);
    expect(validarItemsPedido(justos)).toEqual([]);
  });

  test('el error dice QUÉ línea está mal, no solo que hay una mala', () => {
    const errores = validarItemsPedido([itemValido, { idProducto: 0, cantidad: 5 }]);
    expect(errores[0]).toMatch(/Producto 2:/);
  });

  test('exige precio solo cuando el llamador lo pide', () => {
    const sinPrecio = { idProducto: 3, cantidad: 10 };
    expect(validarItemsPedido([sinPrecio])).toEqual([]);
    expect(validarItemsPedido([sinPrecio], { requierePrecio: true })).toHaveLength(1);
  });

  test('exige tipoPedido solo cuando el llamador lo pide', () => {
    const sinTipo = { idProducto: 3, cantidad: 10 };
    expect(validarItemsPedido([sinTipo])).toEqual([]);
    expect(validarItemsPedido([sinTipo], { requiereTipoPedido: true })).toHaveLength(1);
    expect(validarItemsPedido([{ ...sinTipo, tipoPedido: 'CAJAS' }], { requiereTipoPedido: true })).toHaveLength(1);
  });

  test('la cantidad debe ser un entero positivo', () => {
    expect(validarItemsPedido([{ idProducto: 3, cantidad: 0 }])).toHaveLength(1);
    expect(validarItemsPedido([{ idProducto: 3, cantidad: -5 }])).toHaveLength(1);
    expect(validarItemsPedido([{ idProducto: 3, cantidad: 2.5 }])).toHaveLength(1);
    expect(validarItemsPedido([{ idProducto: 3, cantidad: '10' }])).toHaveLength(1);
  });

  test('cantidadMaxima solo aplica cuando se pasa (la usa la web pública)', () => {
    const enorme = [{ idProducto: 3, cantidad: 900 }];
    expect(validarItemsPedido(enorme)).toEqual([]);
    expect(validarItemsPedido(enorme, { cantidadMaxima: 500 })).toHaveLength(1);
    expect(validarItemsPedido([{ idProducto: 3, cantidad: 500 }], { cantidadMaxima: 500 })).toEqual([]);
  });

  test('un precio de 0 o negativo no pasa cuando se exige precio', () => {
    expect(validarItemsPedido([{ ...itemValido, precioUnitario: 0 }], { requierePrecio: true })).toHaveLength(1);
    expect(validarItemsPedido([{ ...itemValido, precioUnitario: -1 }], { requierePrecio: true })).toHaveLength(1);
    expect(validarItemsPedido([{ ...itemValido, precioUnitario: NaN }], { requierePrecio: true })).toHaveLength(1);
  });

  test('una línea que no es un objeto se reporta sin reventar', () => {
    expect(validarItemsPedido([null])).toHaveLength(1);
    expect(validarItemsPedido(['pan'])).toHaveLength(1);
    expect(validarItemsPedido([[]])).toHaveLength(1);
  });
});
