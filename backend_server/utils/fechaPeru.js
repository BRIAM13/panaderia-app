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

module.exports = {
  PERU_OFFSET_MS,
  diaCalendarioPeru,
  fechaEntregaEsAnteriorAHoy,
  inicioDeHoyPeru,
  inicioDeMesPeru,
};
