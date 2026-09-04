// Perú no usa horario de verano: el offset es siempre fijo.
const PERU_OFFSET_MS = -5 * 60 * 60 * 1000;

/** Fecha calendario (medianoche UTC) que representa el día que era, en hora
 * de Perú, en el instante [fecha] — sin importar la zona horaria del
 * servidor donde corre este proceso. */
function diaCalendarioPeru(fecha) {
  const ajustada = new Date(fecha.getTime() + PERU_OFFSET_MS);
  return Date.UTC(ajustada.getUTCFullYear(), ajustada.getUTCMonth(), ajustada.getUTCDate());
}

/**
 * true si [fechaEntrega] cae en un día calendario (hora de Perú) anterior
 * a hoy. Se compara solo por DÍA, no por instante exacto: la hora es un
 * dato opcional dentro del pedido (por defecto queda en medianoche cuando
 * el usuario no eligió una específica) — comparar el instante exacto
 * contra "ahora" rechazaría casi cualquier pedido programado para hoy,
 * ya que medianoche de hoy siempre queda "en el pasado" frente a la hora
 * actual.
 */
function fechaEntregaEsAnteriorAHoy(fechaEntrega) {
  return diaCalendarioPeru(new Date(fechaEntrega)) < diaCalendarioPeru(new Date());
}

/** Instante UTC real que corresponde a la medianoche de hoy, en hora de
 * Perú — útil para armar rangos "hoy"/"este mes" en consultas SQL. */
function inicioDeHoyPeru() {
  const ahora = new Date();
  const ajustada = new Date(ahora.getTime() + PERU_OFFSET_MS);
  const medianochePeruComoUtc = Date.UTC(ajustada.getUTCFullYear(), ajustada.getUTCMonth(), ajustada.getUTCDate());
  return new Date(medianochePeruComoUtc - PERU_OFFSET_MS);
}

/** Instante UTC real del primer día del mes actual, a medianoche hora de
 * Perú. */
function inicioDeMesPeru() {
  const ahora = new Date();
  const ajustada = new Date(ahora.getTime() + PERU_OFFSET_MS);
  const primerDiaMesComoUtc = Date.UTC(ajustada.getUTCFullYear(), ajustada.getUTCMonth(), 1);
  return new Date(primerDiaMesComoUtc - PERU_OFFSET_MS);
}

/** Instante UTC real del primer día del MES ANTERIOR, a medianoche hora de
 * Perú — el par de [inicioDeMesPeru] para comparar "este mes contra el
 * pasado" (ver comparativoMensual en tiendasController.js). En enero
 * retrocede a diciembre del año anterior: `Date.UTC` normaliza el mes -1
 * solo, no hace falta tratar ese caso aparte. */
function inicioDeMesAnteriorPeru() {
  const ahora = new Date();
  const ajustada = new Date(ahora.getTime() + PERU_OFFSET_MS);
  const primerDia = Date.UTC(ajustada.getUTCFullYear(), ajustada.getUTCMonth() - 1, 1);
  return new Date(primerDia - PERU_OFFSET_MS);
}

/** Instante UTC real del LUNES de la semana actual, a medianoche hora de
 * Perú. La semana empieza el lunes (convención peruana), no el domingo como
 * `getUTCDay()` — de ahí el ajuste del 0 a 6 días. */
function inicioDeSemanaPeru() {
  const ahora = new Date();
  const ajustada = new Date(ahora.getTime() + PERU_OFFSET_MS);
  const diaSemana = ajustada.getUTCDay(); // 0=domingo..6=sábado
  const diasDesdeLunes = diaSemana === 0 ? 6 : diaSemana - 1;
  const lunes = Date.UTC(ajustada.getUTCFullYear(), ajustada.getUTCMonth(), ajustada.getUTCDate() - diasDesdeLunes);
  return new Date(lunes - PERU_OFFSET_MS);
}

/** Instante UTC real que corresponde a la medianoche del día [fechaISO]
 * ("YYYY-MM-DD"), en hora de Perú — misma idea que inicioDeHoyPeru() pero
 * para un día cualquiera, no solo hoy (ej. el selector de fecha del
 * Dashboard). Lanza si el formato no es válido. */
function inicioDeDiaPeru(fechaISO) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(fechaISO);
  if (!match) throw new Error(`Fecha inválida: ${fechaISO}`);
  const anio = Number(match[1]);
  const mes = Number(match[2]);
  const dia = Number(match[3]);
  const medianochePeruComoUtc = Date.UTC(anio, mes - 1, dia);
  return new Date(medianochePeruComoUtc - PERU_OFFSET_MS);
}

/** "YYYY-MM-DD" del día calendario (hora de Perú) de [fecha] — para claves
 * de agrupación/conteo por día (ver ContadoresPedidosDiarios). */
function fechaLocalPeruISO(fecha = new Date()) {
  return new Date(diaCalendarioPeru(fecha)).toISOString().slice(0, 10);
}

/** Hora y minuto actuales, en hora de Perú (0-23, 0-59) — para reglas de
 * negocio que dependen de la hora exacta del día (ej. horario límite de
 * pedido/recojo de Panadería, ver horariosPanaderia.js). */
function horaActualPeru() {
  const ajustada = new Date(Date.now() + PERU_OFFSET_MS);
  return { hora: ajustada.getUTCHours(), minuto: ajustada.getUTCMinutes() };
}

/** Instante UTC real correspondiente a una fecha y hora "naive" en hora de
 * Perú (sin zona horaria, como la que arma el front al combinar un
 * <input type=date> y un <input type=time>) — misma idea que
 * inicioDeDiaPeru() pero permitiendo elegir también la hora, no solo
 * medianoche. */
function instantePeru({ anio, mes, dia, hora, minuto }) {
  const comoUtc = Date.UTC(anio, mes - 1, dia, hora, minuto);
  return new Date(comoUtc - PERU_OFFSET_MS);
}

module.exports = {
  PERU_OFFSET_MS,
  diaCalendarioPeru,
  fechaEntregaEsAnteriorAHoy,
  inicioDeHoyPeru,
  inicioDeMesPeru,
  inicioDeMesAnteriorPeru,
  inicioDeSemanaPeru,
  inicioDeDiaPeru,
  fechaLocalPeruISO,
  horaActualPeru,
  instantePeru,
};
