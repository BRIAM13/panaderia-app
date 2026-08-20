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

/** "YYYY-MM-DD" de hoy — para comparar contra la fecha que eligió el
 * cliente sin repetir el formateo en cada componente que lo necesita. */
export function hoyISO(ahora = new Date()): string {
  return formatearFecha(ahora);
}

/** "HH:mm" (24h) -> "3:15pm"/"4:00am": sin espacio ni puntos, porque mucha
 * gente no maneja bien el formato de 24 horas y el "p. m." con puntos
 * confunde más de lo que aclara. Formato único usado en todo el sitio para
 * mostrar cualquier hora configurada o elegida. */
export function formatearHora12(horaTexto: string): string {
  const [h, m] = horaTexto.split(":").map(Number);
  const periodo = h >= 12 ? "pm" : "am";
  const hora12 = h % 12 === 0 ? 12 : h % 12;
  return `${hora12}:${String(m).padStart(2, "0")}${periodo}`;
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

function minutosDesdeAhoraMasTolerancia(horarios: HorariosPanaderia, ahora: Date): number {
  return ahora.getHours() * 60 + ahora.getMinutes() + horarios.minutosTolerancia;
}

/** Piso duro (a diferencia de `estaFueraDeVentana`, que solo avisa): para
 * un pedido de HOY, nunca se puede elegir una hora a menos de
 * `horarios.minutosTolerancia` minutos desde ahora mismo — refleja del
 * lado del cliente la misma regla que el backend vuelve a exigir
 * (esMuyProntoParaHoy en horariosPanaderia.js), para que el selector de
 * hora ya la respete en vez de dejar que el envío falle. */
export function esMuyProntoHoy(
  fechaElegida: string,
  horaElegida: string,
  horarios: HorariosPanaderia,
  ahora = new Date(),
): boolean {
  if (fechaElegida !== formatearFecha(ahora)) return false;
  return horaAMinutos(horaElegida) < minutosDesdeAhoraMasTolerancia(horarios, ahora);
}

/** "HH:mm" más temprano que se puede elegir hoy en este momento — usado
 * para que el selector de hora deshabilite de entrada lo que ya sabe que
 * el backend va a rechazar. Si la tolerancia empuja después de
 * medianoche, ya no queda ninguna hora válida hoy (ver `esMuyProntoHoy`
 * con cualquier hora del día siempre da true en ese caso). */
export function horaMinimaHoy(horarios: HorariosPanaderia, ahora = new Date()): string {
  const minutos = Math.min(minutosDesdeAhoraMasTolerancia(horarios, ahora), 23 * 60 + 59);
  const h = Math.floor(minutos / 60);
  const m = minutos % 60;
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
}

/** Segundo piso duro: para un pedido de HOY, tampoco se puede elegir una
 * hora después de `horarios.horaTopeRecojo` — el negocio ya cerró para
 * recoger ese día, sin importar la tolerancia. Refleja del lado del
 * cliente la misma regla que el backend vuelve a exigir
 * (esMuyTardeParaHoy en horariosPanaderia.js). */
export function esMuyTardeHoy(
  fechaElegida: string,
  horaElegida: string,
  horarios: HorariosPanaderia,
  ahora = new Date(),
): boolean {
  if (fechaElegida !== formatearFecha(ahora)) return false;
  return horaAMinutos(horaElegida) > horaAMinutos(horarios.horaTopeRecojo);
}

/** true si todavía queda al menos un minuto válido para recoger HOY —
 * false una vez que la tolerancia mínima ya empuja más allá del tope de
 * recojo (ej. tope 10pm, tolerancia 30 min: desde las 9:30pm en adelante
 * ya no hay ninguna hora de hoy que respete ambas reglas a la vez). Se usa
 * para que el selector de fecha deje de ofrecer "hoy" en ese caso — no
 * tiene sentido dejarlo elegible si después ninguna hora sería válida. */
export function hayVentanaHoy(horarios: HorariosPanaderia, ahora = new Date()): boolean {
  return minutosDesdeAhoraMasTolerancia(horarios, ahora) <= horaAMinutos(horarios.horaTopeRecojo);
}

/** Piso/tope duro que aplica a CUALQUIER fecha (hoy o un día futuro), a
 * diferencia de `esMuyProntoHoy`/`esMuyTardeHoy` que solo rigen si la
 * fecha elegida es hoy: el horario general de atención de la tienda.
 * Ninguna hora de recojo puede caer fuera de [horaApertura, horaCierre],
 * sin importar qué día sea. Refleja del lado del cliente la misma regla
 * que el backend vuelve a exigir (fueraDeHorarioAtencion en
 * horariosPanaderia.js). */
export function fueraDeHorarioAtencion(horaElegida: string, horarios: HorariosPanaderia): boolean {
  const minutos = horaAMinutos(horaElegida);
  return minutos < horaAMinutos(horarios.horaApertura) || minutos > horaAMinutos(horarios.horaCierre);
}
