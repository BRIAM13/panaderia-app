import { describe, expect, test } from "vitest";
import type { HorariosPanaderia } from "../../services/api";
import {
  estaFueraDeVentana,
  esMuyProntoHoy,
  esMuyTardeHoy,
  formatearHora12,
  franjaAjustada,
  fueraDeHorarioAtencion,
  hayVentanaHoy,
  horaMinimaHoy,
  hoyISO,
} from "../horariosPan";

// Mismos valores por defecto que usa el backend (ver
// backend_server/utils/horariosPanaderia.js y Configuraciones).
const HORARIOS_DEFECTO: HorariosPanaderia = {
  horaLimitePedido: "10:00",
  horaRecojoMismoDia: "15:30",
  horaRecojoDiaSiguiente: "04:00",
  minutosTolerancia: 30,
  horaTopeRecojo: "22:00",
  horaApertura: "04:00",
  horaCierre: "22:00",
  horaInicioPedidoTarde: "18:00",
  domingoHoraLimitePedido: "07:00",
  franjaMananaActiva: true,
  franjaTardeActiva: true,
};

// 2026-08-30 es domingo; 2026-08-31 es lunes — se usan fijas (no
// `new Date()`) para que las pruebas no dependan del día en que corran.
const DOMINGO = (hora: number, minuto = 0) => new Date(2026, 7, 30, hora, minuto);
const LUNES = (hora: number, minuto = 0) => new Date(2026, 7, 31, hora, minuto);

describe("formatearHora12", () => {
  test("convierte horas de la mañana y la tarde a formato 12h sin espacios ni puntos", () => {
    expect(formatearHora12("04:00")).toBe("4:00am");
    expect(formatearHora12("15:30")).toBe("3:30pm");
  });

  test("mediodía y medianoche se muestran como 12", () => {
    expect(formatearHora12("00:00")).toBe("12:00am");
    expect(formatearHora12("12:00")).toBe("12:00pm");
  });
});

describe("hoyISO", () => {
  test("formatea una fecha como YYYY-MM-DD", () => {
    expect(hoyISO(LUNES(9))).toBe("2026-08-31");
  });
});

describe("franjaAjustada", () => {
  test("con las dos franjas activas, el rango es todo el horario de atención", () => {
    expect(franjaAjustada(HORARIOS_DEFECTO)).toEqual({ piso: "04:00", tope: "22:00" });
  });

  test("con solo la franja de mañana activa, el tope baja a la hora de recojo del mismo día", () => {
    expect(franjaAjustada({ ...HORARIOS_DEFECTO, franjaTardeActiva: false })).toEqual({
      piso: "04:00",
      tope: "15:30",
    });
  });

  test("con las dos franjas apagadas, no queda ningún rango válido", () => {
    expect(
      franjaAjustada({ ...HORARIOS_DEFECTO, franjaMananaActiva: false, franjaTardeActiva: false }),
    ).toBeNull();
  });
});

describe("fueraDeHorarioAtencion", () => {
  test("una hora dentro del rango de atención no está fuera de horario", () => {
    expect(fueraDeHorarioAtencion("10:00", HORARIOS_DEFECTO)).toBe(false);
  });

  test("antes de la apertura o después del cierre sí está fuera de horario", () => {
    expect(fueraDeHorarioAtencion("03:00", HORARIOS_DEFECTO)).toBe(true);
    expect(fueraDeHorarioAtencion("23:00", HORARIOS_DEFECTO)).toBe(true);
  });
});

describe("estaFueraDeVentana — corte especial de domingo", () => {
  test("un lunes a las 8am todavía está dentro del plazo normal (corte 10am): hoy sigue ofreciéndose", () => {
    const ahora = LUNES(8);
    expect(estaFueraDeVentana("2026-08-31", "16:00", HORARIOS_DEFECTO, ahora)).toBe(false);
  });

  test("un domingo a las 8am ya pasó el corte especial de domingo (7am): hoy deja de ofrecerse", () => {
    const ahora = DOMINGO(8);
    // Mismo horario de reloj (8am) que el caso del lunes, pero domingo usa
    // domingoHoraLimitePedido (7am) en vez de horaLimitePedido (10am).
    expect(estaFueraDeVentana("2026-08-30", "16:00", HORARIOS_DEFECTO, ahora)).toBe(true);
  });
});

describe("esMuyProntoHoy", () => {
  test("una hora de hoy dentro de la tolerancia es muy pronto", () => {
    const ahora = LUNES(9, 0); // tolerancia 30 min -> mínimo 09:30
    expect(esMuyProntoHoy("2026-08-31", "09:15", HORARIOS_DEFECTO, ahora)).toBe(true);
  });

  test("una hora de hoy en el límite de tolerancia ya no es muy pronto", () => {
    const ahora = LUNES(9, 0);
    expect(esMuyProntoHoy("2026-08-31", "09:30", HORARIOS_DEFECTO, ahora)).toBe(false);
  });

  test("una fecha que no es hoy nunca es muy pronto", () => {
    const ahora = LUNES(9, 0);
    expect(esMuyProntoHoy("2026-09-01", "00:00", HORARIOS_DEFECTO, ahora)).toBe(false);
  });
});

describe("esMuyTardeHoy", () => {
  test("una hora de hoy después de la hora tope de recojo es muy tarde", () => {
    const ahora = LUNES(20);
    expect(esMuyTardeHoy("2026-08-31", "23:00", HORARIOS_DEFECTO, ahora)).toBe(true);
  });

  test("una hora de hoy antes de la hora tope no es muy tarde", () => {
    const ahora = LUNES(20);
    expect(esMuyTardeHoy("2026-08-31", "21:00", HORARIOS_DEFECTO, ahora)).toBe(false);
  });
});

describe("horaMinimaHoy", () => {
  test("suma los minutos de tolerancia a la hora actual", () => {
    expect(horaMinimaHoy(HORARIOS_DEFECTO, LUNES(9, 0))).toBe("09:30");
  });

  test("no pasa de las 23:59 aunque la tolerancia empuje más allá de medianoche", () => {
    expect(horaMinimaHoy(HORARIOS_DEFECTO, LUNES(23, 50))).toBe("23:59");
  });
});

describe("hayVentanaHoy", () => {
  test("todavía hay ventana si la tolerancia mínima no se pasa del tope efectivo", () => {
    expect(hayVentanaHoy(HORARIOS_DEFECTO, LUNES(9, 0))).toBe(true);
  });

  test("ya no hay ventana cuando la tolerancia mínima supera la hora tope", () => {
    expect(hayVentanaHoy(HORARIOS_DEFECTO, LUNES(21, 45))).toBe(false);
  });

  test("sin ninguna franja activa, nunca hay ventana hoy", () => {
    const horarios = { ...HORARIOS_DEFECTO, franjaMananaActiva: false, franjaTardeActiva: false };
    expect(hayVentanaHoy(horarios, LUNES(9, 0))).toBe(false);
  });
});
