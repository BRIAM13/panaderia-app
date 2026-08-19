const { diaCalendarioPeru, horaActualPeru } = require('./fechaPeru');

// Mismas claves de Configuraciones que edita "Horarios de pedido" en la app
// (ADMIN/SUPERADMIN de Panadería, ver horarios_pedido_page.dart) — mismo
// patrón que PRECIO_PAQUETE: se leen de la BD en cada consulta, así un
// cambio hecho desde la app surte efecto de inmediato, sin redeploy.
const CLAVE_HORA_LIMITE = 'PANADERIA_HORA_LIMITE_PEDIDO';
const CLAVE_HORA_MISMO_DIA = 'PANADERIA_HORA_RECOJO_MISMO_DIA';
const CLAVE_HORA_DIA_SIGUIENTE = 'PANADERIA_HORA_RECOJO_DIA_SIGUIENTE';

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
    WHERE Clave IN ('${CLAVE_HORA_LIMITE}', '${CLAVE_HORA_MISMO_DIA}', '${CLAVE_HORA_DIA_SIGUIENTE}')
  `);
  const mapa = Object.fromEntries(result.recordset.map((r) => [r.Clave, r.Valor]));
  return {
    horaLimitePedido: mapa[CLAVE_HORA_LIMITE] || '10:00',
    horaRecojoMismoDia: mapa[CLAVE_HORA_MISMO_DIA] || '15:30',
    horaRecojoDiaSiguiente: mapa[CLAVE_HORA_DIA_SIGUIENTE] || '04:00',
  };
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

module.exports = {
  CLAVE_HORA_LIMITE,
  CLAVE_HORA_MISMO_DIA,
  CLAVE_HORA_DIA_SIGUIENTE,
  obtenerHorariosPanaderia,
  calcularMinimoRecojo,
  validarFechaEntrega,
};
