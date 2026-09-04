const { inicioDeSemanaPeru, inicioDeMesAnteriorPeru, inicioDeMesPeru } = require('../utils/fechaPeru');

/**
 * Perú es UTC-5 fijo (sin horario de verano), así que "medianoche en Perú"
 * es siempre las 05:00 UTC del mismo día calendario. Todos los `expect` de
 * abajo comparan contra esa hora a propósito: si alguna de estas funciones
 * devolviera medianoche UTC en vez de medianoche peruana, el rango de la
 * consulta se correría 5 horas y contaría ventas del día equivocado.
 */
describe('inicioDeSemanaPeru', () => {
  afterEach(() => {
    jest.useRealTimers();
  });

  function congelar(iso) {
    jest.useFakeTimers().setSystemTime(new Date(iso));
  }

  test('un miércoles devuelve el lunes de esa misma semana', () => {
    // Miércoles 2 de setiembre de 2026, 15:00 en Perú (20:00 UTC).
    congelar('2026-09-02T20:00:00.000Z');
    expect(inicioDeSemanaPeru().toISOString()).toBe('2026-08-31T05:00:00.000Z');
  });

  test('el propio lunes devuelve ese lunes (no retrocede una semana)', () => {
    congelar('2026-08-31T18:00:00.000Z');
    expect(inicioDeSemanaPeru().toISOString()).toBe('2026-08-31T05:00:00.000Z');
  });

  test('un domingo devuelve el lunes ANTERIOR, no el del día siguiente', () => {
    // La semana peruana empieza el lunes: el domingo es su último día, no
    // el primero (getUTCDay() lo numera 0, de ahí el ajuste a 6 días).
    congelar('2026-09-06T16:00:00.000Z');
    expect(inicioDeSemanaPeru().toISOString()).toBe('2026-08-31T05:00:00.000Z');
  });

  test('cruza el fin de mes hacia atrás sin romperse', () => {
    // Martes 1 de setiembre: el lunes de su semana cae en agosto.
    congelar('2026-09-01T14:00:00.000Z');
    expect(inicioDeSemanaPeru().toISOString()).toBe('2026-08-31T05:00:00.000Z');
  });

  test('de madrugada en Perú sigue siendo el mismo día peruano, no el anterior', () => {
    // 01:00 del miércoles en Perú son las 06:00 UTC del miércoles: si se
    // calculara en UTC directamente el resultado sería el mismo, pero a las
    // 20:00 del martes en Perú (01:00 UTC del miércoles) NO debe saltar a
    // la semana siguiente — ese es el caso que revienta sin el offset.
    congelar('2026-09-07T01:00:00.000Z'); // domingo 6, 20:00 en Perú
    expect(inicioDeSemanaPeru().toISOString()).toBe('2026-08-31T05:00:00.000Z');
  });
});

describe('inicioDeMesAnteriorPeru', () => {
  afterEach(() => {
    jest.useRealTimers();
  });

  function congelar(iso) {
    jest.useFakeTimers().setSystemTime(new Date(iso));
  }

  test('en setiembre devuelve el 1 de agosto', () => {
    congelar('2026-09-02T20:00:00.000Z');
    expect(inicioDeMesAnteriorPeru().toISOString()).toBe('2026-08-01T05:00:00.000Z');
  });

  test('en enero retrocede a diciembre del AÑO ANTERIOR', () => {
    congelar('2026-01-15T12:00:00.000Z');
    expect(inicioDeMesAnteriorPeru().toISOString()).toBe('2025-12-01T05:00:00.000Z');
  });

  test('el 1 del mes a medianoche peruana ya cuenta como el mes nuevo', () => {
    // 2026-03-01T05:00Z es exactamente la medianoche del 1 de marzo en
    // Perú: el mes anterior debe ser febrero, no enero.
    congelar('2026-03-01T05:00:00.000Z');
    expect(inicioDeMesAnteriorPeru().toISOString()).toBe('2026-02-01T05:00:00.000Z');
  });

  test('la última hora del mes en Perú todavía pertenece a ese mes', () => {
    // 2026-03-01T04:59Z son las 23:59 del 28 de febrero en Perú.
    congelar('2026-03-01T04:59:00.000Z');
    expect(inicioDeMesPeru().toISOString()).toBe('2026-02-01T05:00:00.000Z');
    expect(inicioDeMesAnteriorPeru().toISOString()).toBe('2026-01-01T05:00:00.000Z');
  });

  test('funciona con meses de 31 días seguidos de uno de 30', () => {
    congelar('2026-07-10T15:00:00.000Z');
    expect(inicioDeMesAnteriorPeru().toISOString()).toBe('2026-06-01T05:00:00.000Z');
  });
});
