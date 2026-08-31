const {
  validateConsultarPedidosPublico,
  validateSolicitarRecuperacion,
  validateConfirmarRecuperacion,
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
