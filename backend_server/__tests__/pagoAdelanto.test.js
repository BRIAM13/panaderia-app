const {
  ESTADO_NO_APLICA,
  ESTADO_VERIFICANDO,
  ESTADO_PAGADO,
  ESTADO_DEUDA_PARCIAL,
  ESTADO_VUELTO_PENDIENTE,
  AJUSTE_DEUDA,
  AJUSTE_VUELTO,
  LARGO_MAXIMO_CODIGO,
  requierePagoAdelanto,
  normalizarCodigoOperacion,
  codigoOperacionValido,
  validarMontoDeclarado,
  resolverPagoAdelanto,
  describirResultadoPago,
} = require('../utils/pagoAdelanto');

/**
 * Pruebas puras del pago por adelantado con Yape — ni una consulta, igual
 * que descuentosCliente.test.js / horariosPanaderia.test.js. Lo que se
 * cubre acá es la cuenta que decide si a un cliente le queda un saldo o un
 * vuelto, que es la parte del feature donde un error se traduce en plata.
 */

describe('requierePagoAdelanto — apagado (se dio de baja el pago con código de Yape)', () => {
  test('Panadería con pan por unidad YA NO exige pagar por adelantado', () => {
    // SLUGS_PAGO_ADELANTO quedó vacía a propósito: el pago con código de
    // operación de Yape se dio de baja. Panadería vuelve a "paga al
    // recoger" hasta que se integre Culqi.
    expect(requierePagoAdelanto({ tiendaSlug: 'panaderia', hayPanPorUnidad: true })).toBe(false);
  });

  test('Hamburguesas NUNCA entra, ni aunque llegara con pan por unidad', () => {
    // Es el punto del alcance acordado: el pan de hamburguesa es otro
    // negocio y se sigue cobrando al recoger.
    expect(requierePagoAdelanto({ tiendaSlug: 'hamburguesas', hayPanPorUnidad: true })).toBe(false);
    expect(requierePagoAdelanto({ tiendaSlug: 'hamburguesas', hayPanPorUnidad: false })).toBe(false);
  });

  test('Panadería sin pan por unidad (solo paquetes) tampoco exige adelanto', () => {
    expect(requierePagoAdelanto({ tiendaSlug: 'panaderia', hayPanPorUnidad: false })).toBe(false);
  });

  test('una tienda desconocida, vacía o ausente no exige adelanto', () => {
    expect(requierePagoAdelanto({ tiendaSlug: 'horneados', hayPanPorUnidad: true })).toBe(false);
    expect(requierePagoAdelanto({ tiendaSlug: '', hayPanPorUnidad: true })).toBe(false);
    expect(requierePagoAdelanto({ tiendaSlug: undefined, hayPanPorUnidad: true })).toBe(false);
  });
});

describe('código de operación', () => {
  test('se le quitan los espacios que mete la app de Yape al copiar', () => {
    expect(normalizarCodigoOperacion('  1234567  ')).toBe('1234567');
    expect(normalizarCodigoOperacion('123 4567')).toBe('1234567');
  });

  test('cualquier cosa que no sea texto/número se normaliza a vacío', () => {
    expect(normalizarCodigoOperacion(null)).toBe('');
    expect(normalizarCodigoOperacion(undefined)).toBe('');
    expect(normalizarCodigoOperacion({})).toBe('');
  });

  test('solo dígitos: una letra invalida el código', () => {
    expect(codigoOperacionValido('1234567')).toBe(true);
    expect(codigoOperacionValido('12A4567')).toBe(false);
    expect(codigoOperacionValido('')).toBe(false);
    expect(codigoOperacionValido('   ')).toBe(false);
  });

  test('no se exige un largo exacto: 6, 7 y 8 dígitos pasan igual', () => {
    // A propósito. El largo real ronda los 7 dígitos, pero exigir el número
    // exacto dejaría fuera un pago legítimo si alguna constancia trae uno
    // más. El tope solo corta basura.
    expect(codigoOperacionValido('123456')).toBe(true);
    expect(codigoOperacionValido('1234567')).toBe(true);
    expect(codigoOperacionValido('12345678')).toBe(true);
    expect(codigoOperacionValido('9'.repeat(LARGO_MAXIMO_CODIGO))).toBe(true);
    expect(codigoOperacionValido('9'.repeat(LARGO_MAXIMO_CODIGO + 1))).toBe(false);
  });
});

describe('validarMontoDeclarado — red blanda contra el error honesto', () => {
  test('pagar exactamente el total es válido', () => {
    expect(validarMontoDeclarado(50, 50).valido).toBe(true);
  });

  test('pagar de más es válido: termina en vuelto, no en rechazo', () => {
    expect(validarMontoDeclarado(50, 60).valido).toBe(true);
  });

  test('declarar MENOS que el total se rechaza con las dos cifras a la vista', () => {
    const revision = validarMontoDeclarado(50, 5);
    expect(revision.valido).toBe(false);
    expect(revision.mensaje).toContain('S/ 5.00');
    expect(revision.mensaje).toContain('S/ 50.00');
  });

  test('un centavo de menos también se rechaza (la comparación es en céntimos)', () => {
    expect(validarMontoDeclarado(50.1, 50.09).valido).toBe(false);
    expect(validarMontoDeclarado(50.1, 50.1).valido).toBe(true);
  });

  test('un monto ausente, cero, negativo o no numérico se rechaza', () => {
    expect(validarMontoDeclarado(50, undefined).valido).toBe(false);
    expect(validarMontoDeclarado(50, 0).valido).toBe(false);
    expect(validarMontoDeclarado(50, -10).valido).toBe(false);
    expect(validarMontoDeclarado(50, 'mucho').valido).toBe(false);
  });
});

describe('resolverPagoAdelanto — las tres salidas de la verificación', () => {
  test('monto exacto -> PAGADO y sin ajuste', () => {
    expect(resolverPagoAdelanto(50, 50)).toEqual({ estadoPagoAdelanto: ESTADO_PAGADO, ajuste: null });
  });

  test('pagó de menos -> DEUDA_PARCIAL con un ajuste DEUDA por la diferencia', () => {
    expect(resolverPagoAdelanto(50, 48)).toEqual({
      estadoPagoAdelanto: ESTADO_DEUDA_PARCIAL,
      ajuste: { tipo: AJUSTE_DEUDA, monto: 2 },
    });
  });

  test('pagó de más -> VUELTO_PENDIENTE con un ajuste VUELTO por la diferencia', () => {
    expect(resolverPagoAdelanto(47, 50)).toEqual({
      estadoPagoAdelanto: ESTADO_VUELTO_PENDIENTE,
      ajuste: { tipo: AJUSTE_VUELTO, monto: 3 },
    });
  });

  test('el monto del ajuste SIEMPRE es positivo: el signo lo dice el tipo', () => {
    // CK_AjustesPago_Monto exige Monto > 0. Un negativo tiraría abajo la
    // confirmación entera al insertar.
    expect(resolverPagoAdelanto(50, 48).ajuste.monto).toBeGreaterThan(0);
    expect(resolverPagoAdelanto(48, 50).ajuste.monto).toBeGreaterThan(0);
  });

  test('la cuenta es en céntimos: 50.10 pagado contra 50.10 no inventa un ajuste', () => {
    // En punto flotante, 48.10 + 2 !== 50.10. Sin redondear a céntimos, esto
    // devolvería un ajuste fantasma de una fracción de céntimo — que además
    // violaría CK_AjustesPago_Monto.
    expect(resolverPagoAdelanto(50.1, 50.1)).toEqual({ estadoPagoAdelanto: ESTADO_PAGADO, ajuste: null });
    expect(resolverPagoAdelanto(0.1 + 0.2, 0.3)).toEqual({ estadoPagoAdelanto: ESTADO_PAGADO, ajuste: null });
  });

  test('diferencias de centavos se reportan con 2 decimales exactos', () => {
    expect(resolverPagoAdelanto(50.1, 50).ajuste).toEqual({ tipo: AJUSTE_DEUDA, monto: 0.1 });
    expect(resolverPagoAdelanto(17.5, 20).ajuste).toEqual({ tipo: AJUSTE_VUELTO, monto: 2.5 });
  });

  test('un monto que llega como texto (body JSON flojo) se trata como número', () => {
    expect(resolverPagoAdelanto('50', '48')).toEqual({
      estadoPagoAdelanto: ESTADO_DEUDA_PARCIAL,
      ajuste: { tipo: AJUSTE_DEUDA, monto: 2 },
    });
  });
});

describe('describirResultadoPago', () => {
  test('cada salida tiene su frase, con la cifra cuando hay diferencia', () => {
    expect(describirResultadoPago(resolverPagoAdelanto(50, 50))).toContain('coincide');
    expect(describirResultadoPago(resolverPagoAdelanto(50, 48))).toContain('S/ 2.00');
    expect(describirResultadoPago(resolverPagoAdelanto(50, 53))).toContain('S/ 3.00');
  });
});

describe('los valores de estado son los que acepta la base', () => {
  test('coinciden exactamente con CK_Pedidos_EstadoPagoAdelanto', () => {
    // Si alguien renombra uno de estos, el INSERT/UPDATE rebota contra el
    // CHECK en producción y no en ninguna prueba — de ahí este candado.
    expect([
      ESTADO_NO_APLICA,
      ESTADO_VERIFICANDO,
      ESTADO_PAGADO,
      ESTADO_DEUDA_PARCIAL,
      ESTADO_VUELTO_PENDIENTE,
    ]).toEqual(['NO_APLICA', 'VERIFICANDO', 'PAGADO', 'DEUDA_PARCIAL', 'VUELTO_PENDIENTE']);
  });

  test('los tipos de ajuste coinciden con CK_AjustesPago_Tipo', () => {
    expect([AJUSTE_DEUDA, AJUSTE_VUELTO]).toEqual(['DEUDA', 'VUELTO']);
  });
});
