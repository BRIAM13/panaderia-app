const {
  ESTADO_NO_APLICA,
  ESTADO_VERIFICANDO,
  ESTADO_PAGADO,
  ESTADO_DEUDA_PARCIAL,
  ESTADO_VUELTO_PENDIENTE,
  AJUSTE_DEUDA,
  AJUSTE_VUELTO,
  LARGO_MAXIMO_CODIGO,
  CLAVE_EXIGE_PAGO_ADELANTADO,
  esCandidatoAPagoAdelanto,
  requierePagoAdelanto,
  normalizarCodigoOperacion,
  codigoOperacionValido,
  validarMontoDeclarado,
  resolverPagoAdelanto,
  describirResultadoPago,
} = require('../utils/pagoAdelanto');

/**
 * Pruebas del pago por adelantado del pedido web de Panadería (hoy con
 * tarjeta vía Culqi; antes con código de operación de Yape).
 *
 * Casi todo acá es puro, igual que descuentosCliente.test.js /
 * horariosPanaderia.test.js: la cuenta que decide si a un cliente le queda un
 * saldo o un vuelto es la parte del feature donde un error se traduce en
 * plata. La excepción es `requierePagoAdelanto`, que desde que el dueño puede
 * encender y apagar el cobro desde la app necesita leer la base — se le pasa
 * un `pool` de mentira (abajo) en vez de levantar nada.
 */

/**
 * Un `pool` mínimo con la forma que usa la capa de compatibilidad:
 * `pool.request().input(...).query(texto)` -> `{ recordset }`.
 *
 * Se arma a mano y no con `instalarMockMysql` a propósito: lo que se prueba
 * acá es la DECISIÓN (¿exige pago?), no la traducción de T-SQL, y un pool de
 * 10 líneas deja ver de un vistazo qué responde cada consulta.
 */
function poolFalso({ valorConfig, pideSinPagarAdelanto = false, fallaConfig = false, fallaCliente = false } = {}) {
  const consultas = [];
  return {
    consultas,
    request() {
      return {
        input() {
          return this;
        },
        async query(texto) {
          consultas.push(texto);
          if (/FROM Configuraciones/i.test(texto)) {
            if (fallaConfig) throw new Error('base caída');
            return { recordset: valorConfig === undefined ? [] : [{ Valor: valorConfig }] };
          }
          if (/FROM Clientes/i.test(texto)) {
            if (fallaCliente) throw new Error('Unknown column PideSinPagarAdelanto');
            return { recordset: [{ PideSinPagarAdelanto: pideSinPagarAdelanto ? 1 : 0 }] };
          }
          return { recordset: [] };
        },
      };
    },
  };
}

/** Panadería con pan por unidad: el pedido que SÍ es candidato. El resto de
 * los parámetros cambia según lo que cada caso quiera probar. */
const CANDIDATO = { tiendaSlug: 'panaderia', hayPanPorUnidad: true, idCliente: 5 };

describe('esCandidatoAPagoAdelanto — el filtro puro de tienda + producto', () => {
  test('Panadería con pan por unidad es candidata', () => {
    // Volvió a la lista con la integración de Culqi (estuvo vacía mientras el
    // pago con código de Yape estaba dado de baja). Ser candidata NO significa
    // que se cobre: eso lo decide la configuración, ver el describe siguiente.
    expect(esCandidatoAPagoAdelanto({ tiendaSlug: 'panaderia', hayPanPorUnidad: true })).toBe(true);
  });

  test('Hamburguesas NUNCA entra, ni aunque llegara con pan por unidad', () => {
    // Es el punto del alcance acordado: el pan de hamburguesa es otro
    // negocio y se sigue cobrando al recoger, pase lo que pase con la
    // configuración global.
    expect(esCandidatoAPagoAdelanto({ tiendaSlug: 'hamburguesas', hayPanPorUnidad: true })).toBe(false);
    expect(esCandidatoAPagoAdelanto({ tiendaSlug: 'hamburguesas', hayPanPorUnidad: false })).toBe(false);
  });

  test('Panadería sin pan por unidad (solo paquetes) no es candidata', () => {
    expect(esCandidatoAPagoAdelanto({ tiendaSlug: 'panaderia', hayPanPorUnidad: false })).toBe(false);
  });

  test('una tienda desconocida, vacía o ausente no es candidata', () => {
    expect(esCandidatoAPagoAdelanto({ tiendaSlug: 'horneados', hayPanPorUnidad: true })).toBe(false);
    expect(esCandidatoAPagoAdelanto({ tiendaSlug: '', hayPanPorUnidad: true })).toBe(false);
    expect(esCandidatoAPagoAdelanto({ tiendaSlug: undefined, hayPanPorUnidad: true })).toBe(false);
  });
});

describe('requierePagoAdelanto — el interruptor del dueño + la excepción por cliente', () => {
  test(`con ${CLAVE_EXIGE_PAGO_ADELANTADO} en '1', Panadería exige pagar antes`, async () => {
    const pool = poolFalso({ valorConfig: '1' });
    await expect(requierePagoAdelanto({ pool, ...CANDIDATO })).resolves.toBe(true);
  });

  test("con la clave en '0', se vuelve a pagar al recoger", async () => {
    const pool = poolFalso({ valorConfig: '0' });
    await expect(requierePagoAdelanto({ pool, ...CANDIDATO })).resolves.toBe(false);
  });

  test('si la clave todavía no existe en Configuraciones, falla APAGADO', async () => {
    // Con la cuenta Culqi del dueño en trámite, encendido por defecto dejaría
    // a TODO pedido de pan exigiendo una tarjeta que el backend no puede
    // cobrar (503): nadie podría pedir pan. Lo peor que puede pasar apagado
    // es seguir cobrando al recoger, como siempre.
    const pool = poolFalso({ valorConfig: undefined });
    await expect(requierePagoAdelanto({ pool, ...CANDIDATO })).resolves.toBe(false);
  });

  test('un valor raro escrito a mano NO cuenta como encendido', async () => {
    for (const valor of ['true', 'SI', '2', '', '  ']) {
      const pool = poolFalso({ valorConfig: valor });
      await expect(requierePagoAdelanto({ pool, ...CANDIDATO })).resolves.toBe(false);
    }
  });

  test('si la consulta de configuración revienta, falla APAGADO', async () => {
    const pool = poolFalso({ valorConfig: '1', fallaConfig: true });
    await expect(requierePagoAdelanto({ pool, ...CANDIDATO })).resolves.toBe(false);
  });

  test('un cliente con la excepción pide sin pagar AUNQUE el toggle esté encendido', async () => {
    // El caso que pidió el dueño: las bodegas que le pagan la semana o el mes
    // completos. Es la razón de existir de `Clientes.PideSinPagarAdelanto`.
    const pool = poolFalso({ valorConfig: '1', pideSinPagarAdelanto: true });
    await expect(requierePagoAdelanto({ pool, ...CANDIDATO })).resolves.toBe(false);
  });

  test('un visitante sin IdCliente todavía (null) sí tiene que pagar', async () => {
    // Sin fila en Clientes no hay excepción posible: no se le puede fiar a
    // alguien que el sistema todavía no conoce.
    const pool = poolFalso({ valorConfig: '1' });
    await expect(requierePagoAdelanto({ pool, ...CANDIDATO, idCliente: null })).resolves.toBe(true);
  });

  test('si la columna de la excepción no existe todavía, se exige pagar igual', async () => {
    // O sea: la migración 2026_09_excepcion_pago_adelanto no se corrió. Falla
    // CERRADO al revés que el toggle — regalar la excepción por un error de
    // base sería regalar pan al fiado.
    const pool = poolFalso({ valorConfig: '1', fallaCliente: true });
    await expect(requierePagoAdelanto({ pool, ...CANDIDATO })).resolves.toBe(true);
  });

  test('un pedido que no es candidato no gasta NI UNA consulta', async () => {
    // El orden de las condiciones importa por costo: el filtro puro descarta
    // todos los pedidos de hamburguesa sin tocar la base.
    const pool = poolFalso({ valorConfig: '1' });
    await expect(
      requierePagoAdelanto({ pool, tiendaSlug: 'hamburguesas', hayPanPorUnidad: true, idCliente: 5 }),
    ).resolves.toBe(false);
    expect(pool.consultas).toHaveLength(0);
  });

  test('con el toggle apagado NO se consulta el flag del cliente', async () => {
    // Si no se cobra por adelantado, la excepción es irrelevante.
    const pool = poolFalso({ valorConfig: '0' });
    await requierePagoAdelanto({ pool, ...CANDIDATO });
    expect(pool.consultas.filter((t) => /FROM Clientes/i.test(t))).toHaveLength(0);
  });

  test('sin pool no exige nada (no se puede consultar la configuración)', async () => {
    await expect(requierePagoAdelanto({ ...CANDIDATO, pool: undefined })).resolves.toBe(false);
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
