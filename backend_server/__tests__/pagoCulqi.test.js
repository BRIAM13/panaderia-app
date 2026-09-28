const {
  COMISION_FIJA_SOLES,
  TASA_COMISION_VARIABLE,
  MENSAJE_RECHAZO_GENERICO,
  aCentimosCulqi,
  aSolesCulqi,
  calcularMontoConComision,
  tokenCulqiValido,
  traducirErrorCulqi,
  montoCobradoEnSoles,
} = require('../utils/pagoCulqi');

/**
 * Pruebas PURAS de `utils/pagoCulqi.js` — toda la cuenta y todo el texto del
 * cobro con Culqi, sin red y sin base.
 *
 * `crearCargoCulqi` (lo único que sale a internet) NO se prueba acá: se prueba
 * a través del controlador, con axios mockeado, en pagoCulqiController.test.js.
 * Este archivo es el que tiene que atrapar un error de aritmética de plata, que
 * es la clase de error que no da ningún síntoma visible: nadie ve un mensaje,
 * solo al dueño le llega un poco menos de lo que creía por cada pedido.
 */

describe('aCentimosCulqi — la conversión que evita cobrar S/ 0.50 en vez de S/ 50', () => {
  test('soles enteros y con decimales pasan a céntimos enteros', () => {
    expect(aCentimosCulqi(50)).toBe(5000);
    expect(aCentimosCulqi(45.5)).toBe(4550);
    expect(aCentimosCulqi(0.01)).toBe(1);
  });

  test('redondea y no trunca: 50.10 * 100 da 5009.999… en punto flotante', () => {
    // Truncar acá cobraría S/ 50.09 — un céntimo de menos en cada pedido con
    // decimales, que es todos los pedidos de pan por unidad.
    expect(aCentimosCulqi(50.1)).toBe(5010);
    expect(aCentimosCulqi(8.2)).toBe(820);
    expect(aCentimosCulqi(1.1 + 2.2)).toBe(330);
  });

  test('lo que no es un monto cobrable devuelve null, para cortar antes de la red', () => {
    expect(aCentimosCulqi(0)).toBeNull();
    expect(aCentimosCulqi(-5)).toBeNull();
    expect(aCentimosCulqi('mucho')).toBeNull();
    expect(aCentimosCulqi(null)).toBeNull();
    expect(aCentimosCulqi(undefined)).toBeNull();
    expect(aCentimosCulqi(NaN)).toBeNull();
    // Un monto tan chico que redondea a 0 céntimos tampoco es cobrable.
    expect(aCentimosCulqi(0.004)).toBeNull();
  });
});

describe('aSolesCulqi', () => {
  test('céntimos enteros vuelven a soles con 2 decimales exactos', () => {
    expect(aSolesCulqi(5000)).toBe(50);
    expect(aSolesCulqi(4724)).toBe(47.24);
    expect(aSolesCulqi(1)).toBe(0.01);
  });
});

describe('calcularMontoConComision — el gross-up que paga el cliente', () => {
  /**
   * La comisión que Culqi le va a descontar a un cargo de `cobradoSoles`,
   * calculada desde las constantes tal como está la tarifa. Se recalcula acá
   * a propósito, en vez de comparar contra números pegados a mano: así el día
   * que el dueño pase a producción y cambie la tarifa, estas pruebas siguen
   * comprobando la PROPIEDAD (al dueño le llega lo que eligió el cliente) y no
   * una tabla de números que quedaría obsoleta y roja sin que nada esté mal.
   */
  function comisionQueSeQuedaCulqi(cobradoSoles) {
    return COMISION_FIJA_SOLES + cobradoSoles * TASA_COMISION_VARIABLE;
  }

  test('el caso medido a mano: S/ 45.50 netos se cobran como S/ 47.24', () => {
    // (4550 + 118) / (1 - 0.0118) = 5118... no: 4668 / 0.9882 = 4723.74 -> 4724.
    // Es el mismo monto del cargo real de prueba con el que se midió la tarifa
    // de esta cuenta (2026-09-28, `venta_exitosa`, amount 4550).
    expect(calcularMontoConComision(45.5)).toEqual({ montoACobrar: 47.24, comision: 1.74 });
  });

  test('`comision` es exactamente la diferencia, o sea lo que el cliente paga de más', () => {
    // Es la cifra que la página le muestra en el desglose: si no fuera
    // exactamente montoACobrar - montoElegido, las tres líneas que ve el
    // cliente no sumarían y parecería un cobro mal hecho.
    for (const neto of [45.5, 50, 25, 1, 0.01, 33.33, 1234.56]) {
      const { montoACobrar, comision } = calcularMontoConComision(neto);
      expect(comision).toBe(Number((montoACobrar - neto).toFixed(2)));
    }
  });

  test('LA PROPIEDAD del feature: después de la comisión, al dueño le llega lo que el cliente eligió', () => {
    // Esto es lo que el gross-up promete y lo único que de verdad importa: se
    // cobra `montoACobrar`, Culqi se queda con su tarifa, y lo que queda es
    // `neto` con un margen de medio céntimo (el del único redondeo de la cuenta).
    for (const neto of [0.01, 1, 3.33, 25, 25.03, 45.5, 50, 50.1, 100, 1234.56]) {
      const { montoACobrar } = calcularMontoConComision(neto);
      const llegaAlDueno = montoACobrar - comisionQueSeQuedaCulqi(montoACobrar);
      expect(Math.abs(llegaAlDueno - neto)).toBeLessThanOrEqual(0.005);
    }
  });

  test('siempre cobra MÁS que el neto: cobrar de menos sería el dueño pagando la comisión', () => {
    for (const neto of [0.01, 1, 25, 45.5, 1234.56]) {
      const { montoACobrar, comision } = calcularMontoConComision(neto);
      expect(montoACobrar).toBeGreaterThan(neto);
      // La comisión nunca puede bajar de la parte fija, que se cobra igual en
      // el cargo más chico posible.
      expect(comision).toBeGreaterThanOrEqual(COMISION_FIJA_SOLES);
    }
  });

  test('montos chicos: la comisión fija pesa muchísimo y eso es correcto, no un bug', () => {
    // S/ 1.00 + IGV se cobra igual sea el cargo de S/ 0.01 o de S/ 1000. En un
    // cargo mínimo la comisión es más grande que el pedido — es la tarifa real
    // de Culqi, no un error de la cuenta.
    expect(calcularMontoConComision(0.01)).toEqual({ montoACobrar: 1.2, comision: 1.19 });
    expect(calcularMontoConComision(1)).toEqual({ montoACobrar: 2.21, comision: 1.21 });
  });

  test('montos que no dan céntimos redondos quedan igual en 2 decimales cobrables', () => {
    // 3.33 -> (333 + 118) / 0.9882 = 456.39… -> 456 céntimos. Un monto con más
    // de 2 decimales no se le puede pedir a Culqi (solo acepta céntimos
    // enteros), así que el redondeo tiene que pasar ACÁ y una sola vez.
    for (const neto of [3.33, 19.99, 7.77, 50.05, 66.66]) {
      const { montoACobrar, comision } = calcularMontoConComision(neto);
      expect(montoACobrar).toBe(Number(montoACobrar.toFixed(2)));
      expect(comision).toBe(Number(comision.toFixed(2)));
      // Y el resultado tiene que seguir siendo cobrable por Culqi.
      expect(aCentimosCulqi(montoACobrar)).toBe(Math.round(montoACobrar * 100));
    }
    expect(calcularMontoConComision(3.33)).toEqual({ montoACobrar: 4.56, comision: 1.23 });
  });

  test('un solo redondeo al final: la fórmula en céntimos, no la comisión por separado', () => {
    // El error que esto vigila: calcular la comisión aparte, redondearla, y
    // sumarla. Ese camino arrastra el error y deja al neto un céntimo corto —
    // justo el céntimo que el dueño no quería regalar.
    for (const neto of [45.5, 25.03, 19.99, 100]) {
      const netoCentimos = Math.round(neto * 100);
      const esperado = Math.round((netoCentimos + Math.round(COMISION_FIJA_SOLES * 100)) / (1 - TASA_COMISION_VARIABLE));
      expect(calcularMontoConComision(neto).montoACobrar).toBe(Number((esperado / 100).toFixed(2)));
    }
  });

  test('crece de forma monótona: más neto nunca da menos cobrado', () => {
    let anterior = 0;
    for (const neto of [0.01, 0.5, 1, 10, 25, 50, 100, 500, 1000]) {
      const { montoACobrar } = calcularMontoConComision(neto);
      expect(montoACobrar).toBeGreaterThan(anterior);
      anterior = montoACobrar;
    }
  });

  test('un neto que no es cobrable devuelve null, igual que aCentimosCulqi', () => {
    expect(calcularMontoConComision(0)).toBeNull();
    expect(calcularMontoConComision(-45.5)).toBeNull();
    expect(calcularMontoConComision('mucho')).toBeNull();
    expect(calcularMontoConComision(null)).toBeNull();
    expect(calcularMontoConComision(undefined)).toBeNull();
    expect(calcularMontoConComision(NaN)).toBeNull();
  });

  test('un neto que llega como texto (body JSON flojo) se trata como número', () => {
    expect(calcularMontoConComision('45.50')).toEqual({ montoACobrar: 47.24, comision: 1.74 });
  });
});

describe('las constantes de comisión — las dos que hay que reconfirmar en producción', () => {
  test('son la tarifa medida en la cuenta de prueba de este comercio', () => {
    // S/ 1.00 + IGV fija y 1% + IGV variable, medidas con un cargo real de
    // prueba el 2026-09-28. NO son una tarifa universal de Culqi: cuando el
    // comercio pase a producción hay que leer la real en CulqiPanel ->
    // Desarrollo -> "Ver comisión producto" y corregirlas.
    //
    // Este test NO defiende que 1.18 sea correcto para siempre — defiende que
    // el IGV esté aplicado. La trampa real es escribir 1.00 y 0.01 (la tarifa
    // SIN IGV, que es como la publica Culqi), y perder el 18% en cada pedido.
    expect(COMISION_FIJA_SOLES).toBeCloseTo(1 * 1.18, 10);
    expect(TASA_COMISION_VARIABLE).toBeCloseTo(0.01 * 1.18, 10);
  });

  test('la tasa variable es una fracción, no un porcentaje', () => {
    // Un 1.18 en vez de 0.0118 haría que (1 - tasa) fuera negativo y el
    // gross-up devolviera un monto negativo: el cargo entero se rompería.
    expect(TASA_COMISION_VARIABLE).toBeGreaterThan(0);
    expect(TASA_COMISION_VARIABLE).toBeLessThan(1);
  });
});

describe('tokenCulqiValido — tarjeta y Yape entran por el mismo camino', () => {
  test('acepta los tokens de tarjeta (tkn_) y los de Yape (ype_)', () => {
    expect(tokenCulqiValido('tkn_test_A1b2C3d4E5f6G7h8')).toBe(true);
    expect(tokenCulqiValido('tkn_live_A1b2C3d4E5f6G7h8')).toBe(true);
    // El que faltaba antes del 2026-09-27: sin esto, todo pago por Yape se
    // rechazaba con un 400 sin que Culqi llegara a enterarse.
    expect(tokenCulqiValido('ype_test_SJzb9dQhW2xXsKFS')).toBe(true);
    expect(tokenCulqiValido('ype_live_SJzb9dQhW2xXsKFS')).toBe(true);
  });

  test('rechaza lo que obviamente no es un token, sin gastar una llamada a la red', () => {
    expect(tokenCulqiValido('no-es-un-token')).toBe(false);
    expect(tokenCulqiValido('tkn_prod_A1b2C3d4E5f6')).toBe(false);
    expect(tokenCulqiValido('tkn_test_corto')).toBe(false);
    expect(tokenCulqiValido('')).toBe(false);
    expect(tokenCulqiValido(null)).toBe(false);
    expect(tokenCulqiValido(12345)).toBe(false);
  });
});

describe('traducirErrorCulqi — el cliente siempre entiende qué hacer después', () => {
  test('prefiere el user_message de Culqi, que su equipo mantiene al día', () => {
    const { mensaje } = traducirErrorCulqi({
      user_message: 'Su tarjeta no tiene fondos suficientes.',
      decline_code: 'insufficient_funds',
    });
    expect(mensaje).toBe('Su tarjeta no tiene fondos suficientes.');
  });

  test('sin user_message cae a la tabla por decline_code, en español', () => {
    expect(traducirErrorCulqi({ decline_code: 'expired_card' }).mensaje).toMatch(/vencida/i);
    expect(traducirErrorCulqi({ decline_code: 'insufficient_funds' }).mensaje).toMatch(/saldo suficiente/i);
  });

  test('un decline_code que Culqi agregue mañana cae al genérico, no a undefined', () => {
    expect(traducirErrorCulqi({ decline_code: 'codigo_que_no_existe' }).mensaje).toBe(MENSAJE_RECHAZO_GENERICO);
    expect(traducirErrorCulqi({}).mensaje).toBe(MENSAJE_RECHAZO_GENERICO);
    expect(traducirErrorCulqi(null).mensaje).toBe(MENSAJE_RECHAZO_GENERICO);
  });

  test('los códigos viajan para la auditoría, aunque no se le muestren al cliente', () => {
    expect(traducirErrorCulqi({ code: 'card_declined', decline_code: 'fraudulent' })).toMatchObject({
      codigo: 'card_declined',
      declineCode: 'fraudulent',
    });
    expect(traducirErrorCulqi({}).codigo).toBeNull();
  });
});

describe('montoCobradoEnSoles — la constancia de lo que Culqi dijo haber cobrado', () => {
  test('lee el amount del cargo, que viene en céntimos', () => {
    expect(montoCobradoEnSoles({ amount: 4724 })).toBe(47.24);
  });

  test('sin un amount utilizable devuelve null, y quien llama cae al monto pedido', () => {
    expect(montoCobradoEnSoles({})).toBeNull();
    expect(montoCobradoEnSoles({ amount: 0 })).toBeNull();
    expect(montoCobradoEnSoles(null)).toBeNull();
    expect(montoCobradoEnSoles(undefined)).toBeNull();
  });
});
