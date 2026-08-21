const { diaCalendarioPeru, horaActualPeru } = require('./fechaPeru');

// Mismas claves de Configuraciones que edita "Horarios de pedido" en la app
// (ADMIN/SUPERADMIN de Panadería, ver horarios_pedido_page.dart) — mismo
// patrón que PRECIO_PAQUETE: se leen de la BD en cada consulta, así un
// cambio hecho desde la app surte efecto de inmediato, sin redeploy.
const CLAVE_HORA_LIMITE = 'PANADERIA_HORA_LIMITE_PEDIDO';
const CLAVE_HORA_MISMO_DIA = 'PANADERIA_HORA_RECOJO_MISMO_DIA';
const CLAVE_HORA_DIA_SIGUIENTE = 'PANADERIA_HORA_RECOJO_DIA_SIGUIENTE';
const CLAVE_MINUTOS_TOLERANCIA = 'PANADERIA_MINUTOS_TOLERANCIA';
const CLAVE_HORA_TOPE_RECOJO = 'PANADERIA_HORA_TOPE_RECOJO';
const CLAVE_HORA_APERTURA = 'PANADERIA_HORA_APERTURA';
const CLAVE_HORA_CIERRE = 'PANADERIA_HORA_CIERRE';
// Turnos de pedido (solo informativos, ver franjaAjustada más abajo para
// el bloqueo real) y los 2 interruptores de franja de recojo.
const CLAVE_HORA_INICIO_PEDIDO_TARDE = 'PANADERIA_HORA_INICIO_PEDIDO_TARDE';
const CLAVE_DOMINGO_HORA_LIMITE_PEDIDO = 'PANADERIA_DOMINGO_HORA_LIMITE_PEDIDO';
const CLAVE_FRANJA_MANANA_ACTIVA = 'PANADERIA_FRANJA_MANANA_ACTIVA';
const CLAVE_FRANJA_TARDE_ACTIVA = 'PANADERIA_FRANJA_TARDE_ACTIVA';

const UN_DIA_MS = 24 * 60 * 60 * 1000;

function horaAMinutos(horaTexto) {
  const [h, m] = horaTexto.split(':').map(Number);
  return h * 60 + m;
}

/** Horario de pedido/recojo de Panadería (pan de agua y francés, vendidos
 * por unidad — el pan de hamburguesa por paquete no tiene esta
 * restricción). Si alguna clave todavía no existe en Configuraciones, cae
 * a los valores por defecto en vez de romper el pedido. */
async function obtenerHorariosPanaderia(pool) {
  const result = await pool.request().query(`
    SELECT Clave, Valor FROM Configuraciones
    WHERE Clave IN (
      '${CLAVE_HORA_LIMITE}', '${CLAVE_HORA_MISMO_DIA}', '${CLAVE_HORA_DIA_SIGUIENTE}',
      '${CLAVE_MINUTOS_TOLERANCIA}', '${CLAVE_HORA_TOPE_RECOJO}', '${CLAVE_HORA_APERTURA}', '${CLAVE_HORA_CIERRE}',
      '${CLAVE_HORA_INICIO_PEDIDO_TARDE}', '${CLAVE_DOMINGO_HORA_LIMITE_PEDIDO}',
      '${CLAVE_FRANJA_MANANA_ACTIVA}', '${CLAVE_FRANJA_TARDE_ACTIVA}'
    )
  `);
  const mapa = Object.fromEntries(result.recordset.map((r) => [r.Clave, r.Valor]));
  return {
    horaLimitePedido: mapa[CLAVE_HORA_LIMITE] || '10:00',
    horaRecojoMismoDia: mapa[CLAVE_HORA_MISMO_DIA] || '15:30',
    horaRecojoDiaSiguiente: mapa[CLAVE_HORA_DIA_SIGUIENTE] || '04:00',
    minutosTolerancia: Number(mapa[CLAVE_MINUTOS_TOLERANCIA]) || 30,
    // Hora tope de recojo: después de esta hora ya no se puede recoger un
    // pedido el mismo día, sin importar la tolerancia — el negocio cierra.
    horaTopeRecojo: mapa[CLAVE_HORA_TOPE_RECOJO] || '22:00',
    // Horario general de atención: rige el recojo de CUALQUIER día (hoy o
    // una fecha futura) — ver franjaAjustada() para cómo se combina con
    // los 2 interruptores de franja.
    horaApertura: mapa[CLAVE_HORA_APERTURA] || '04:00',
    horaCierre: mapa[CLAVE_HORA_CIERRE] || '22:00',
    // Turnos de pedido: puramente informativos (solo alimentan el aviso
    // de "fuera de ventana" del lado del cliente) — el bloqueo real de
    // horas lo hacen los 2 interruptores de franja de abajo.
    horaInicioPedidoTarde: mapa[CLAVE_HORA_INICIO_PEDIDO_TARDE] || '18:00',
    domingoHoraLimitePedido: mapa[CLAVE_DOMINGO_HORA_LIMITE_PEDIDO] || '07:00',
    // Interruptores manuales de franja: cuando el dueño se queda sin
    // stock de una hornada, los apaga desde la app y los pedidos nuevos
    // saltan directo a la otra franja — ver franjaAjustada().
    franjaMananaActiva: (mapa[CLAVE_FRANJA_MANANA_ACTIVA] ?? 'true') === 'true',
    franjaTardeActiva: (mapa[CLAVE_FRANJA_TARDE_ACTIVA] ?? 'true') === 'true',
  };
}

/**
 * Piso/techo EFECTIVO de recojo para cualquier día, según qué franjas
 * están activas ahora mismo. Las dos franjas son secuenciales y sin
 * encimarse (juntas cubren exactamente [horaApertura, horaCierre]):
 * franja mañana [horaApertura, horaRecojoMismoDia) y franja tarde
 * [horaRecojoMismoDia, horaCierre). Si el dueño apaga una, el rango
 * válido se achica al de la otra; si apaga las dos, no queda ningún
 * minuto válido (caso raro — se trata como "cerrado hasta que reactive
 * alguna", no auto-recupera solo).
 */
function franjaAjustada(horarios) {
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

/**
 * Calcula la fecha y hora mínima de recojo permitida en este momento: si
 * todavía no pasa la hora límite de pedido, el mínimo es HOY a la hora de
 * "mismo día" (normalmente 3:30pm, la tanda de la tarde que alcanza a
 * salir con la harina ya pedida); si ya pasó, el mínimo salta a MAÑANA a
 * la hora de "día siguiente" (normalmente 4:00am, la tanda normal de la
 * mañana). `fechaMinima` es el mismo formato numérico que usa
 * diaCalendarioPeru() (medianoche UTC del día, en hora de Perú).
 */
function calcularMinimoRecojo(horarios) {
  const { hora, minuto } = horaActualPeru();
  const minutosAhora = hora * 60 + minuto;
  const dentroDePlazo = minutosAhora <= horaAMinutos(horarios.horaLimitePedido);

  const hoyPeru = diaCalendarioPeru(new Date());

  return {
    fechaMinima: dentroDePlazo ? hoyPeru : hoyPeru + UN_DIA_MS,
    horaMinima: dentroDePlazo ? horarios.horaRecojoMismoDia : horarios.horaRecojoDiaSiguiente,
    esMismoDia: dentroDePlazo,
  };
}

/**
 * Valida una fecha/hora de recojo propuesta por el cliente contra el
 * mínimo permitido en este momento. Nunca confía en el horario que mandó
 * el front — lo recalcula acá con la hora real del servidor, así nadie
 * puede saltarse la restricción editando la petición a mano.
 */
function validarFechaEntrega({ anio, mes, dia, hora, minuto }, horarios) {
  const minimo = calcularMinimoRecojo(horarios);
  const fechaPropuesta = Date.UTC(anio, mes - 1, dia);

  if (fechaPropuesta < minimo.fechaMinima) return false;

  const minutosPropuestos = hora * 60 + minuto;
  // La hora de "mismo día" (ej. 3:30pm) solo aplica cuando la fecha
  // propuesta es exactamente hoy — cualquier otra fecha (mañana, o una
  // fecha más adelante que elija el cliente) usa siempre la hora normal
  // de "día siguiente" como piso; ese batch de la tarde es exclusivo del
  // mismo día en que se hizo el pedido, no se repite después.
  const aplicaHoraMismoDia = fechaPropuesta === minimo.fechaMinima && minimo.esMismoDia;
  const pisoMinutos = aplicaHoraMismoDia
    ? horaAMinutos(minimo.horaMinima)
    : horaAMinutos(horarios.horaRecojoDiaSiguiente);

  return minutosPropuestos >= pisoMinutos;
}

/**
 * Piso duro de "minutos de tolerancia": para una fecha de recojo elegida
 * que caiga HOY (hora de Perú), el cliente nunca puede elegir una hora a
 * menos de `minutosTolerancia` minutos del momento actual del servidor —
 * necesitamos ese margen para confirmar si hay stock y avisarle antes de
 * que pase la hora que eligió. No aplica a fechas futuras, esas ya tienen
 * su propio piso vía calcularMinimoRecojo/validarFechaEntrega.
 */
function esMuyProntoParaHoy({ anio, mes, dia, hora, minuto }, horarios) {
  const hoyPeru = diaCalendarioPeru(new Date());
  const fechaPropuesta = Date.UTC(anio, mes - 1, dia);
  if (fechaPropuesta !== hoyPeru) return false;

  const ahora = horaActualPeru();
  const minutosMinimos = ahora.hora * 60 + ahora.minuto + horarios.minutosTolerancia;
  const minutosPropuestos = hora * 60 + minuto;
  return minutosPropuestos < minutosMinimos;
}

/**
 * Tope duro de recojo: para una fecha de recojo elegida que caiga HOY, el
 * cliente nunca puede elegir una hora después de `horaTopeRecojo` (el
 * negocio ya cerró para el día) — sin importar la tolerancia. No aplica a
 * fechas futuras, esas siempre arrancan de nuevo desde `horaRecojoDiaSiguiente`.
 */
function esMuyTardeParaHoy({ anio, mes, dia, hora, minuto }, horarios) {
  const hoyPeru = diaCalendarioPeru(new Date());
  const fechaPropuesta = Date.UTC(anio, mes - 1, dia);
  if (fechaPropuesta !== hoyPeru) return false;

  const minutosPropuestos = hora * 60 + minuto;
  return minutosPropuestos > horaAMinutos(horarios.horaTopeRecojo);
}

/**
 * true si todavía queda al menos un minuto válido para recoger HOY —
 * false cuando la tolerancia mínima ya empujó más allá del tope de recojo
 * (ej. tope 10:00pm, tolerancia 30 min: desde las 9:30pm en adelante ya no
 * queda ninguna hora de hoy que respete ambas reglas a la vez). En ese
 * caso el propio día de hoy deja de ofrecerse como fecha de recojo — el
 * cliente pasa directo a elegir desde mañana.
 */
function hayVentanaHoy(horarios) {
  const ahora = horaActualPeru();
  const minutosMinimos = ahora.hora * 60 + ahora.minuto + horarios.minutosTolerancia;
  return minutosMinimos <= horaAMinutos(horarios.horaTopeRecojo);
}

/**
 * Piso/tope duro que aplica a CUALQUIER fecha de recojo (hoy o un día
 * futuro), a diferencia de esMuyProntoParaHoy/esMuyTardeParaHoy que solo
 * rigen si la fecha propuesta es exactamente hoy: el rango efectivo según
 * qué franjas de recojo están activas (ver franjaAjustada). Sin esto, un
 * cliente podía elegir una fecha futura a cualquier hora del día (ej.
 * 12:05am), aunque la tienda ya llevara horas cerrada, o seguir eligiendo
 * una franja que el dueño ya apagó por falta de stock.
 */
function fueraDeHorarioAtencion({ hora, minuto }, horarios) {
  const franja = franjaAjustada(horarios);
  if (!franja) return true;
  const minutosPropuestos = hora * 60 + minuto;
  return minutosPropuestos < horaAMinutos(franja.piso) || minutosPropuestos > horaAMinutos(franja.tope);
}

module.exports = {
  CLAVE_HORA_LIMITE,
  CLAVE_HORA_MISMO_DIA,
  CLAVE_HORA_DIA_SIGUIENTE,
  CLAVE_MINUTOS_TOLERANCIA,
  CLAVE_HORA_TOPE_RECOJO,
  CLAVE_HORA_APERTURA,
  CLAVE_HORA_CIERRE,
  CLAVE_HORA_INICIO_PEDIDO_TARDE,
  CLAVE_DOMINGO_HORA_LIMITE_PEDIDO,
  CLAVE_FRANJA_MANANA_ACTIVA,
  CLAVE_FRANJA_TARDE_ACTIVA,
  obtenerHorariosPanaderia,
  calcularMinimoRecojo,
  validarFechaEntrega,
  esMuyProntoParaHoy,
  esMuyTardeParaHoy,
  hayVentanaHoy,
  fueraDeHorarioAtencion,
  franjaAjustada,
};
