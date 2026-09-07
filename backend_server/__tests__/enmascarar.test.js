const {
  enmascararEmail,
  enmascararTelefono,
  contactoEnmascarado,
  contactoVacio,
} = require('../utils/enmascarar');

describe('enmascararEmail', () => {
  test('deja el primer carácter y el dominio completo', () => {
    expect(enmascararEmail('juan.perez@gmail.com')).toBe('j***@gmail.com');
  });

  test('un usuario de una sola letra igual queda enmascarado', () => {
    expect(enmascararEmail('a@gmail.com')).toBe('a***@gmail.com');
  });

  test('el largo del usuario no se filtra: dos correos distintos dan la misma máscara', () => {
    expect(enmascararEmail('jo@hotmail.com')).toBe(enmascararEmail('josefina.ramirez@hotmail.com'));
  });

  test('null/vacío/sin arroba devuelven null (no hay nada que mostrar)', () => {
    expect(enmascararEmail(null)).toBeNull();
    expect(enmascararEmail('')).toBeNull();
    expect(enmascararEmail('   ')).toBeNull();
    expect(enmascararEmail('sinarroba.com')).toBeNull();
    expect(enmascararEmail('@gmail.com')).toBeNull();
    expect(enmascararEmail('juan@')).toBeNull();
  });
});

describe('enmascararTelefono', () => {
  test('celular peruano: primer dígito, 5 asteriscos y los últimos 3', () => {
    expect(enmascararTelefono('987654321')).toBe('9*****321');
  });

  test('un número de otro largo se enmascara con el mismo criterio', () => {
    expect(enmascararTelefono('012345')).toBe('0**345');
  });

  test('números muy cortos se tapan por completo', () => {
    expect(enmascararTelefono('123')).toBe('***');
  });

  test('null/vacío devuelven null', () => {
    expect(enmascararTelefono(null)).toBeNull();
    expect(enmascararTelefono('  ')).toBeNull();
  });
});

describe('contactoEnmascarado', () => {
  test('canal con dato guardado y verificado: enArchivo y verificado en true, con máscara', () => {
    const contacto = contactoEnmascarado({
      Email: 'juan.perez@gmail.com',
      Telefono: '987654321',
      EmailVerificado: 0,
      TelefonoVerificado: 1,
    });

    expect(contacto.email).toEqual({ enArchivo: true, verificado: false, mascara: 'j***@gmail.com' });
    expect(contacto.telefono).toEqual({ enArchivo: true, verificado: true, mascara: '9*****321' });
  });

  test('canal sin dato: enArchivo false y máscara null, aunque el flag venga en 1', () => {
    const contacto = contactoEnmascarado({
      Email: null,
      Telefono: '',
      EmailVerificado: 1,
      TelefonoVerificado: 1,
    });

    expect(contacto.email).toEqual({ enArchivo: false, verificado: false, mascara: null });
    expect(contacto.telefono).toEqual({ enArchivo: false, verificado: false, mascara: null });
  });

  test('nunca devuelve el valor real, ni siquiera parcialmente completable', () => {
    const contacto = contactoEnmascarado({
      Email: 'juan.perez@gmail.com',
      Telefono: '987654321',
      EmailVerificado: 1,
      TelefonoVerificado: 1,
    });

    expect(JSON.stringify(contacto)).not.toContain('juan.perez');
    expect(JSON.stringify(contacto)).not.toContain('987654321');
  });

  test('contactoVacio marca los dos canales como sin dato', () => {
    expect(contactoVacio()).toEqual({
      email: { enArchivo: false, verificado: false, mascara: null },
      telefono: { enArchivo: false, verificado: false, mascara: null },
    });
  });
});
