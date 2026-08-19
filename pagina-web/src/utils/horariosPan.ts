import type { HorariosPanaderia } from "../services/api";

export interface VentanaRecojo {
  /** "YYYY-MM-DD" */
  fechaMinima: string;
  /** "HH:mm" */
  horaMinima: string;
  esMismoDia: boolean;
}

function horaAMinutos(hora: string): number {
  const [h, m] = hora.split(":").map(Number);
  return h * 60 + m;
}

function formatearFecha(fecha: Date): string {
  const y = fecha.getFullYear();
  const m = String(fecha.getMonth() + 1).padStart(2, "0");
  const d = String(fecha.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

/** Calcula la fecha/hora mínima de recojo que puede elegir el cliente en
 * este momento: si todavía no pasa la hora límite de pedido, el mínimo es
 * HOY a la hora de "mismo día" (la tanda de la tarde); si ya pasó, el
 * mínimo salta a MAÑANA a la hora de "día siguiente" (la tanda normal de
 * la mañana). Mismo cálculo que hace el backend al validar el pedido (ver
 * validarFechaEntrega en horariosPanaderia.js) — reflejado acá solo para
 * que el formulario proponga la opción correcta; el backend es quien de
 * verdad lo hace cumplir. */
export function calcularVentanaRecojo(horarios: HorariosPanaderia, ahora = new Date()): VentanaRecojo {
  const minutosAhora = ahora.getHours() * 60 + ahora.getMinutes();
  const dentroDePlazo = minutosAhora <= horaAMinutos(horarios.horaLimitePedido);

  const fecha = new Date(ahora);
  if (!dentroDePlazo) fecha.setDate(fecha.getDate() + 1);

  return {
    fechaMinima: formatearFecha(fecha),
    horaMinima: dentroDePlazo ? horarios.horaRecojoMismoDia : horarios.horaRecojoDiaSiguiente,
    esMismoDia: dentroDePlazo,
  };
}

/** Hora mínima válida para una fecha de recojo ya elegida por el cliente:
 * la hora de "mismo día" (ej. 3:30pm) solo aplica cuando la fecha elegida
 * es exactamente la fecha mínima Y esa fecha mínima es hoy — cualquier
 * otra fecha (mañana, o una fecha más adelante) usa siempre la hora
 * normal de "día siguiente" como piso. */
export function horaMinimaParaFecha(
  fechaElegida: string,
  ventana: VentanaRecojo,
  horarios: HorariosPanaderia,
): string {
  const aplicaHoraMismoDia = fechaElegida === ventana.fechaMinima && ventana.esMismoDia;
  return aplicaHoraMismoDia ? ventana.horaMinima : horarios.horaRecojoDiaSiguiente;
}
