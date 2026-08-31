const {
  franjaAjustada,
  fueraDeHorarioAtencion,
  calcularMinimoRecojo,
  validarFechaEntrega,
  esMuyProntoParaHoy,
  esMuyTardeParaHoy,
  hayVentanaHoy,
} = require('../utils/horariosPanaderia');

// Mismos valores por defecto que devuelve obtenerHorariosPanaderia() cuando
// una clave todavía no existe en Configuraciones — así los tests no
// dependen de ninguna base de datos.
const HORARIOS_DEFECTO = {
  horaLimitePedido: '10:00',
  horaRecojoMismoDia: '15:30',
  horaRecojoDiaSiguiente: '04:00',
  minutosTolerancia: 30,
  horaTopeRecojo: '22:00',
  horaApertura: '04:00',
  horaCierre: '22:00',
  horaInicioPedidoTarde: '18:00',
  domingoHoraLimitePedido: '07:00',
  franjaMananaActiva: true,
  franjaTardeActiva: true,
};

/** Fija la hora del sistema a una hora de Perú específica, en un día fijo
 * (2026-08-30). Perú es UTC-5 todo el año (sin horario de verano), así que
 * "hora de Perú" = "hora UTC" + 5. */
function fijarHoraPeru(horaPeru, minutoPeru = 0) {
  const horaUtc = horaPeru + 5;
  jest.useFakeTimers().setSystemTime(new Date(Date.UTC(2026, 7, 30, horaUtc, minutoPeru, 0)));
}

afterEach(() => {
  jest.useRealTimers();
});

describe('franjaAjustada', () => {
  test('con las dos franjas activas, el rango es todo el horario de atención', () => {
    expect(franjaAjustada(HORARIOS_DEFECTO)).toEqual({ piso: '04:00', tope: '22:00' });
  });

  test('con solo la franja de mañana activa, el tope baja a la hora de recojo del mismo día', () => {
    const horarios = { ...HORARIOS_DEFECTO, franjaTardeActiva: false };
    expect(franjaAjustada(horarios)).toEqual({ piso: '04:00', tope: '15:30' });
  });

  test('con solo la franja de tarde activa, el piso sube a la hora de recojo del mismo día', () => {
    const horarios = { ...HORARIOS_DEFECTO, franjaMananaActiva: false };
    expect(franjaAjustada(horarios)).toEqual({ piso: '15:30', tope: '22:00' });
  });

  test('con las dos franjas apagadas, no queda ningún rango válido', () => {
    const horarios = { ...HORARIOS_DEFECTO, franjaMananaActiva: false, franjaTardeActiva: false };
    expect(franjaAjustada(horarios)).toBeNull();
  });
});

describe('fueraDeHorarioAtencion', () => {
  test('una hora dentro del rango de atención no está fuera de horario', () => {
    expect(fueraDeHorarioAtencion({ hora: 10, minuto: 0 }, HORARIOS_DEFECTO)).toBe(false);
  });

  test('antes de la apertura sí está fuera de horario', () => {
    expect(fueraDeHorarioAtencion({ hora: 3, minuto: 0 }, HORARIOS_DEFECTO)).toBe(true);
  });

  test('después del cierre sí está fuera de horario', () => {
    expect(fueraDeHorarioAtencion({ hora: 23, minuto: 0 }, HORARIOS_DEFECTO)).toBe(true);
  });

  test('si se apagó la franja de la tarde, una hora que antes era válida ahora queda fuera', () => {
    const horarios = { ...HORARIOS_DEFECTO, franjaTardeActiva: false };
    expect(fueraDeHorarioAtencion({ hora: 16, minuto: 0 }, horarios)).toBe(true);
  });

  test('sin ninguna franja activa, cualquier hora está fuera de horario', () => {
    const horarios = { ...HORARIOS_DEFECTO, franjaMananaActiva: false, franjaTardeActiva: false };
    expect(fueraDeHorarioAtencion({ hora: 10, minuto: 0 }, horarios)).toBe(true);
  });
});

describe('calcularMinimoRecojo', () => {
  test('antes de la hora límite, el mínimo es hoy a la hora de recojo del mismo día', () => {
    fijarHoraPeru(9, 0); // 09:00 Perú, antes del límite (10:00)
    const resultado = calcularMinimoRecojo(HORARIOS_DEFECTO);
    expect(resultado.esMismoDia).toBe(true);
    expect(resultado.horaMinima).toBe('15:30');
    expect(resultado.fechaMinima).toBe(Date.UTC(2026, 7, 30));
  });

  test('después de la hora límite, el mínimo salta a mañana a la hora de recojo del día siguiente', () => {
    fijarHoraPeru(11, 0); // 11:00 Perú, después del límite (10:00)
    const resultado = calcularMinimoRecojo(HORARIOS_DEFECTO);
    expect(resultado.esMismoDia).toBe(false);
    expect(resultado.horaMinima).toBe('04:00');
    expect(resultado.fechaMinima).toBe(Date.UTC(2026, 7, 31));
  });

  test('justo en la hora límite todavía cuenta como dentro de plazo', () => {
    fijarHoraPeru(10, 0);
    expect(calcularMinimoRecojo(HORARIOS_DEFECTO).esMismoDia).toBe(true);
  });
});

describe('validarFechaEntrega', () => {
  test('rechaza una fecha anterior al mínimo permitido', () => {
    fijarHoraPeru(9, 0);
    const ayer = { anio: 2026, mes: 8, dia: 29, hora: 16, minuto: 0 };
    expect(validarFechaEntrega(ayer, HORARIOS_DEFECTO)).toBe(false);
  });

  test('dentro de plazo, hoy antes de la hora de recojo del mismo día se rechaza', () => {
    fijarHoraPeru(9, 0);
    const hoyTemprano = { anio: 2026, mes: 8, dia: 30, hora: 12, minuto: 0 };
    expect(validarFechaEntrega(hoyTemprano, HORARIOS_DEFECTO)).toBe(false);
  });

  test('dentro de plazo, hoy en o después de la hora de recojo del mismo día se acepta', () => {
    fijarHoraPeru(9, 0);
    const hoyTarde = { anio: 2026, mes: 8, dia: 30, hora: 15, minuto: 30 };
    expect(validarFechaEntrega(hoyTarde, HORARIOS_DEFECTO)).toBe(true);
  });

  test('una fecha futura siempre usa la hora de recojo del día siguiente como piso, aunque sea antes de la hora límite', () => {
    fijarHoraPeru(9, 0);
    const pasadoMananaTemprano = { anio: 2026, mes: 9, dia: 1, hora: 3, minuto: 0 };
    expect(validarFechaEntrega(pasadoMananaTemprano, HORARIOS_DEFECTO)).toBe(false);

    const pasadoMananaValido = { anio: 2026, mes: 9, dia: 1, hora: 4, minuto: 0 };
    expect(validarFechaEntrega(pasadoMananaValido, HORARIOS_DEFECTO)).toBe(true);
  });
});

describe('esMuyProntoParaHoy', () => {
  test('una hora de hoy dentro de la tolerancia es muy pronto', () => {
    fijarHoraPeru(9, 0); // ahora 09:00, tolerancia 30 min -> mínimo 09:30
    const propuesta = { anio: 2026, mes: 8, dia: 30, hora: 9, minuto: 15 };
    expect(esMuyProntoParaHoy(propuesta, HORARIOS_DEFECTO)).toBe(true);
  });

  test('una hora de hoy justo en el límite de tolerancia ya no es muy pronto', () => {
    fijarHoraPeru(9, 0);
    const propuesta = { anio: 2026, mes: 8, dia: 30, hora: 9, minuto: 30 };
    expect(esMuyProntoParaHoy(propuesta, HORARIOS_DEFECTO)).toBe(false);
  });

  test('una fecha que no es hoy nunca es "muy pronto"', () => {
    fijarHoraPeru(9, 0);
    const propuesta = { anio: 2026, mes: 8, dia: 31, hora: 0, minuto: 0 };
    expect(esMuyProntoParaHoy(propuesta, HORARIOS_DEFECTO)).toBe(false);
  });
});

describe('esMuyTardeParaHoy', () => {
  test('una hora de hoy después de la hora tope de recojo es muy tarde', () => {
    fijarHoraPeru(20, 0);
    const propuesta = { anio: 2026, mes: 8, dia: 30, hora: 23, minuto: 0 };
    expect(esMuyTardeParaHoy(propuesta, HORARIOS_DEFECTO)).toBe(true);
  });

  test('una hora de hoy antes de la hora tope de recojo no es muy tarde', () => {
    fijarHoraPeru(20, 0);
    const propuesta = { anio: 2026, mes: 8, dia: 30, hora: 21, minuto: 0 };
    expect(esMuyTardeParaHoy(propuesta, HORARIOS_DEFECTO)).toBe(false);
  });

  test('una fecha que no es hoy nunca es "muy tarde"', () => {
    fijarHoraPeru(20, 0);
    const propuesta = { anio: 2026, mes: 8, dia: 31, hora: 23, minuto: 0 };
    expect(esMuyTardeParaHoy(propuesta, HORARIOS_DEFECTO)).toBe(false);
  });
});

describe('hayVentanaHoy', () => {
  test('todavía hay ventana si la tolerancia mínima no se pasa de la hora tope', () => {
    fijarHoraPeru(9, 0); // 09:00 + 30 min tolerancia = 09:30, bajo el tope 22:00
    expect(hayVentanaHoy(HORARIOS_DEFECTO)).toBe(true);
  });

  test('ya no hay ventana cuando la tolerancia mínima supera la hora tope', () => {
    fijarHoraPeru(21, 45); // 21:45 + 30 min = 22:15, pasa el tope 22:00
    expect(hayVentanaHoy(HORARIOS_DEFECTO)).toBe(false);
  });
});
