import type { HorariosPanaderia } from "../services/api";

interface VentanaRecojo {
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

/** Primer día en el que técnicamente ya se puede recoger un pedido nuevo
 * en este momento (hoy, si todavía no pasa la hora límite de pedido;
 * mañana si ya pasó) — solo se usa para decidir si un horario elegido por
 * el cliente cae dentro o fuera de la ventana normal, NO para bloquear
 * ninguna fecha: el cliente puede elegir cualquier fecha desde hoy en
 * adelante y cualquier hora, aunque caiga fuera de esta ventana (ver
 * `estaFueraDeVentana`). */
function calcularVentanaRecojo(horarios: HorariosPanaderia, ahora = new Date()): VentanaRecojo {
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

/** true si la fecha/hora que eligió el cliente ya no alcanza a salir en
 * la tanda normal (quedó fuera del horario configurado) — el pedido igual
 * se registra, esto solo decide si se le muestra el aviso de "este
 * horario ya cerró, te confirmamos disponibilidad por WhatsApp". */
export function estaFueraDeVentana(
  fechaElegida: string,
  horaElegida: string,
  horarios: HorariosPanaderia,
  ahora = new Date(),
): boolean {
  const ventana = calcularVentanaRecojo(horarios, ahora);

  if (fechaElegida < ventana.fechaMinima) return true;
  if (fechaElegida > ventana.fechaMinima) {
    // Cualquier día posterior al mínimo usa siempre la hora normal de
    // "día siguiente" como piso (la de "mismo día" es exclusiva de hoy).
    return horaAMinutos(horaElegida) < horaAMinutos(horarios.horaRecojoDiaSiguiente);
  }
  // fechaElegida === ventana.fechaMinima
  const piso = ventana.esMismoDia ? ventana.horaMinima : horarios.horaRecojoDiaSiguiente;
  return horaAMinutos(horaElegida) < horaAMinutos(piso);
}
