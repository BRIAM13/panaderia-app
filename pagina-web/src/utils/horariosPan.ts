import type { HorariosPanaderia } from "../services/api";

interface VentanaRecojo {
  /** "YYYY-MM-DD" */
  fechaMinima: string;
  /** "HH:mm" */
  horaMinima: string;
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
 * en este momento — solo se usa para decidir si un horario elegido por
 * el cliente cae dentro o fuera de la ventana normal (el aviso ámbar
 * informativo), NO para bloquear ninguna fecha: el cliente puede elegir
 * cualquier fecha desde hoy en adelante y cualquier hora, aunque caiga
 * fuera de esta ventana (ver `estaFueraDeVentana`).
 *
 * El día se reparte en 3 zonas (domingo usa su propio corte de mañana
 * en vez de `horaLimitePedido`, ver `horaLimiteHoy`):
 *   1. antes del corte de la mañana -> HOY, franja tarde (3pm).
 *   2. entre ese corte y `horaInicioPedidoTarde` (6pm) -> MAÑANA, franja
 *      mañana (4am) — el turno de pedidos "de la tarde" que hoy en día
 *      alimenta la hornada de mañana.
 *   3. después de `horaInicioPedidoTarde` -> MAÑANA, franja tarde (3pm)
 *      — turno tarde/noche, alimenta la hornada de la tarde del día
 *      siguiente (no la de la mañana). */
function horaLimiteHoy(horarios: HorariosPanaderia, ahora: Date): string {
  return ahora.getDay() === 0 ? horarios.domingoHoraLimitePedido : horarios.horaLimitePedido;
}

function calcularVentanaRecojo(horarios: HorariosPanaderia, ahora = new Date()): VentanaRecojo {
  const minutosAhora = ahora.getHours() * 60 + ahora.getMinutes();
  const minutosLimite = horaAMinutos(horaLimiteHoy(horarios, ahora));
  const minutosInicioTarde = horaAMinutos(horarios.horaInicioPedidoTarde);

  if (minutosAhora < minutosLimite) {
    return { fechaMinima: formatearFecha(ahora), horaMinima: horarios.horaRecojoMismoDia };
  }

  const manana = new Date(ahora);
  manana.setDate(manana.getDate() + 1);
  const zonaTarde = minutosAhora >= minutosInicioTarde;
  return {
    fechaMinima: formatearFecha(manana),
    horaMinima: zonaTarde ? horarios.horaRecojoMismoDia : horarios.horaRecojoDiaSiguiente,
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
  // fechaElegida === ventana.fechaMinima: `horaMinima` ya trae la hora
  // correcta para la zona en la que se hizo el pedido (franja mañana o
  // franja tarde), tanto si el mínimo es hoy como si es mañana.
  return horaAMinutos(horaElegida) < horaAMinutos(ventana.horaMinima);
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

interface FranjaAjustada {
  /** "HH:mm" */
  piso: string;
  /** "HH:mm" */
  tope: string;
}

/** Piso/techo EFECTIVO de recojo para cualquier día, según qué franjas
 * están activas ahora mismo — mismo cálculo que `franjaAjustada` en
 * horariosPanaderia.js (backend). Las dos franjas son secuenciales y sin
 * encimarse (juntas cubren exactamente [horaApertura, horaCierre]):
 * franja mañana [horaApertura, horaRecojoMismoDia) y franja tarde
 * [horaRecojoMismoDia, horaCierre). Si el dueño apaga una, el rango
 * válido se achica al de la otra; si apaga las dos, no queda ningún
 * minuto válido (`null`). */
export function franjaAjustada(horarios: HorariosPanaderia): FranjaAjustada | null {
  if (horarios.franjaMananaActiva && horarios.franjaTardeActiva) {
    return { piso: horarios.horaApertura, tope: horarios.horaCierre };
  }
  if (horarios.franjaMananaActiva && !horarios.franjaTardeActiva) {
    return { piso: horarios.horaApertura, tope: horarios.horaRecojoMismoDia };
  }
  if (!horarios.franjaMananaActiva && horarios.franjaTardeActiva) {
    return { piso: horarios.horaRecojoMismoDia, tope: horarios.horaCierre };
  }
  return null;
}

/** true si todavía queda al menos un minuto válido para recoger HOY —
 * false una vez que la tolerancia mínima ya empuja más allá del techo
 * efectivo de hoy (el tope de recojo del mismo día, o antes si la franja
 * tarde está apagada — ver `franjaAjustada`). Se usa para que el selector
 * de fecha deje de ofrecer "hoy" en ese caso — no tiene sentido dejarlo
 * elegible si después ninguna hora sería válida. */
export function hayVentanaHoy(horarios: HorariosPanaderia, ahora = new Date()): boolean {
  const franja = franjaAjustada(horarios);
  if (!franja) return false;
  const topeEfectivo = Math.min(horaAMinutos(horarios.horaTopeRecojo), horaAMinutos(franja.tope));
  return minutosDesdeAhoraMasTolerancia(horarios, ahora) <= topeEfectivo;
}

/** Piso/tope duro que aplica a CUALQUIER fecha (hoy o un día futuro), a
 * diferencia de `esMuyProntoHoy`/`esMuyTardeHoy` que solo rigen si la
 * fecha elegida es hoy: el rango efectivo según qué franjas de recojo
 * están activas (ver `franjaAjustada`). Ninguna hora de recojo puede caer
 * fuera de ese rango, sin importar qué día sea, ni dentro de una franja
 * que el dueño apagó por falta de stock. Refleja del lado del cliente la
 * misma regla que el backend vuelve a exigir (fueraDeHorarioAtencion en
 * horariosPanaderia.js). */
export function fueraDeHorarioAtencion(horaElegida: string, horarios: HorariosPanaderia): boolean {
  const franja = franjaAjustada(horarios);
  if (!franja) return true;
  const minutos = horaAMinutos(horaElegida);
  return minutos < horaAMinutos(franja.piso) || minutos > horaAMinutos(franja.tope);
}
