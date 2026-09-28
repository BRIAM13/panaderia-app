// Pago por adelantado del pedido web de Panadería.
//
// Toda la CUENTA de este archivo es pura (`resolverPagoAdelanto`,
// `validarMontoDeclarado`, `aCentimos`): la cuenta de "¿pagó justo, de menos
// o de más?" es la que decide si al cliente le queda un saldo o un vuelto, y
// tiene que poder probarse sola, sin levantar nada. Mismo criterio que
// `descuentosCliente.js` y `horariosPanaderia.js`.
//
// La ÚNICA excepción es el portón de entrada (`requierePagoAdelanto` y las
// dos funciones que lo alimentan): desde que el dueño puede encender y apagar
// el cobro por adelantado desde la app, ese portón depende de una clave de
// `Configuraciones` y de un flag por cliente, así que necesita la base. Se
// mantiene acá y no en el controlador porque es la MISMA decisión de negocio
// que el resto del archivo, y porque así hay un solo lugar que responde
// "¿este pedido tiene que pagarse antes?".
//
// Ver `database_migrations/2026_09_pago_adelanto_panaderia.sql` para el
// porqué de cada columna, y en particular por qué esto NO reutiliza
// `Pedidos.EstadoPago` (que significa el fiado posterior a la entrega y
// alimenta todos los reportes de deuda del sistema).
// Ver `database_migrations/2026_09_excepcion_pago_adelanto.sql` por la
// columna `Clientes.PideSinPagarAdelanto` y el toggle global.
//
// ⚠️ A propósito SIN `require('../config/db')`, aunque las dos consultas de
//    abajo lo pedirían: ese módulo crea el pool de mysql2 al importarse, y
//    este archivo lo importan las pruebas puras (`__tests__/pagoAdelanto.test.js`),
//    que no deben levantar nada. El `pool` llega por parámetro —siempre el de
//    quien llama— y los `.input()` usan la forma de DOS argumentos
//    (nombre, valor), que la capa de compatibilidad soporta igual: los
//    marcadores `sql.Int`/`sql.VarChar(n)` son decorativos ahí, mysql2 deduce
//    el tipo del valor JS (ver `RequestCompat.input` en config/db.js).

/** Los 5 valores de `Pedidos.EstadoPagoAdelanto` (CK_Pedidos_EstadoPagoAdelanto). */
const ESTADO_NO_APLICA = 'NO_APLICA';
const ESTADO_VERIFICANDO = 'VERIFICANDO';
const ESTADO_PAGADO = 'PAGADO';
const ESTADO_DEUDA_PARCIAL = 'DEUDA_PARCIAL';
const ESTADO_VUELTO_PENDIENTE = 'VUELTO_PENDIENTE';

/** Los 2 valores de `AjustesPago.Tipo` (CK_AjustesPago_Tipo). */
const AJUSTE_DEUDA = 'DEUDA';
const AJUSTE_VUELTO = 'VUELTO';

/**
 * Tiendas CANDIDATAS a exigir pago por adelantado.
 *
 * Ojo con lo que esta lista significa hoy: es un filtro de "qué tiendas
 * podrían llegar a cobrar por adelantado", NO el interruptor. El interruptor
 * real es [CLAVE_EXIGE_PAGO_ADELANTADO] en `Configuraciones`, que el dueño
 * prende y apaga desde la app sin redeploy. Las dos condiciones se exigen
 * juntas (ver `requierePagoAdelanto`), y son dos cosas distintas a propósito:
 * esta lista es una decisión de ARQUITECTURA (el pan de hamburguesa es otro
 * negocio y nunca entra en esto, pase lo que pase con la configuración),
 * mientras la clave de Configuraciones es una decisión OPERATIVA del día a
 * día ("hoy cobro antes" / "hoy no").
 *
 * Volvió a `['panaderia']` con la integración de Culqi: estuvo vacía entre el
 * 2026-09-17 y el 2026-09-26, mientras el pago con código de operación de
 * Yape estaba dado de baja y no había pasarela que lo reemplazara.
 */
const SLUGS_PAGO_ADELANTO = ['panaderia'];

/**
 * Clave de `Configuraciones` que enciende y apaga el cobro por adelantado.
 *
 * '1' = el pedido web de Panadería no se confirma hasta que Culqi cobre.
 * '0' (o cualquier otro valor, o la clave ausente) = se registra como
 * siempre y se paga al recoger.
 *
 * Mismo patrón que `DESCUENTOS_TIENDAS_HABILITADAS`: se lee de la base EN
 * CADA pedido, sin caché en memoria, así el cambio hecho desde la app aplica
 * en el pedido siguiente sin reiniciar nada.
 */
const CLAVE_EXIGE_PAGO_ADELANTADO = 'EXIGE_PAGO_ADELANTADO_PANADERIA';

/**
 * Qué pasa si la clave no existe todavía en `Configuraciones`.
 *
 * Falla APAGADO, y no es un detalle: encendido por defecto, una base sin
 * sembrar convertiría todos los pedidos de pan en pedidos que exigen tarjeta
 * — con la cuenta de Culqi del dueño todavía en trámite, o sea con el cobro
 * respondiendo 503. Nadie podría pedir pan. Apagado, lo peor que pasa es que
 * se siga cobrando al recoger, que es como funcionó siempre.
 */
const EXIGE_PAGO_ADELANTADO_POR_DEFECTO = false;

/**
 * Cuánto del total hay que pagar como MÍNIMO para separar el pedido.
 *
 * 0.5 = la mitad. Es una DECISIÓN DE NEGOCIO del dueño (2026-09-28), no un
 * número técnico: quería que un cliente pudiera "separar" su pedido sin tener
 * que adelantar todo, pero con suficiente plata puesta como para que no le
 * convenga no aparecer a recogerlo. El pan por unidad se hornea contra pedido;
 * un pedido que nadie recoge es masa, harina y horno gastados, y la mitad
 * cobrada por adelantado cubre eso. Menos de la mitad y el incentivo se
 * invierte; más y vuelve a ser casi lo mismo que pagar todo.
 *
 * Si el dueño cambia de opinión, se cambia ACÁ y nada más: el saldo que queda
 * pendiente ya lo maneja el mecanismo de DEUDA_PARCIAL + AjustesPago que
 * existía desde el flujo de Yape (ver `resolverPagoAdelanto`).
 */
const FRACCION_MINIMA_PAGO_ADELANTO = 0.5;

/** Largo máximo aceptado para el código de operación de Yape.
 *
 * Los códigos reales son bastante más cortos (alrededor de 7 dígitos), pero
 * acá NO se exige un largo exacto: si el largo real fuera 8 en algún caso,
 * un cliente con un pago legítimo quedaría fuera sin forma de enviar su
 * pedido. Esto solo corta una entrada absurda antes de que llegue a la base
 * (la columna es VARCHAR(30)). Quien verifica de verdad es la persona que
 * mira el Yape del negocio.
 */
const LARGO_MAXIMO_CODIGO = 10;

/**
 * Soles a céntimos enteros. Toda comparación de plata de este archivo pasa
 * por acá: `48.10 + 2 !== 50.10` en punto flotante, y esa clase de error se
 * traduciría en un ajuste fantasma de S/ 0.00000001 en la base (que además
 * violaría CK_AjustesPago_Monto, "Monto > 0", y tiraría abajo la
 * confirmación entera).
 */
function aCentimos(monto) {
  return Math.round(Number(monto) * 100);
}

/** Céntimos enteros de vuelta a soles con 2 decimales, listos para la base. */
function aSoles(centimos) {
  return Number((centimos / 100).toFixed(2));
}

/**
 * El mínimo pagable AHORA para separar un pedido de `total` soles.
 *
 * [FRACCION_MINIMA_PAGO_ADELANTO] del total, redondeado al céntimo. La cuenta
 * pasa por céntimos enteros como todo el resto del archivo: `montoMinimoAPagar`
 * es la cifra contra la que se compara lo que el cliente eligió pagar, y un
 * mínimo con cola de punto flotante (S/ 25.024999999) rechazaría un pago de
 * exactamente el mínimo mostrado en pantalla.
 *
 * Redondea al céntimo más cercano y eso puede dejar el mínimo un céntimo POR
 * ENCIMA de la mitad exacta (total 50.05 -> mínimo 25.03, no 25.025): es lo
 * correcto, porque el mínimo tiene que ser un monto cobrable de verdad y el
 * céntimo de más va del lado del negocio, no del cliente que quiere pagar de
 * menos.
 *
 * Devuelve null para un total que no es cobrable (no numérico, cero,
 * negativo). Quien llama ya validó el total del pedido antes de llegar acá;
 * null es la señal de "no hay mínimo que calcular", nunca 0 — un mínimo de 0
 * dejaría pasar cualquier monto.
 */
function montoMinimoAPagar(total) {
  const totalCentimos = aCentimos(total);
  if (!Number.isFinite(totalCentimos) || totalCentimos <= 0) return null;
  return aSoles(Math.round(totalCentimos * FRACCION_MINIMA_PAGO_ADELANTO));
}

/**
 * ¿La tienda y el producto son de los que PODRÍAN exigir pago por adelantado?
 *
 * La parte pura y sin base del portón, separada para poder probarla sola:
 * la tienda tiene que estar en [SLUGS_PAGO_ADELANTO] Y el pedido tiene que
 * ser de pan por unidad. Hoy las dos dicen casi lo mismo (en Panadería todo
 * se vende por unidad), pero el día que Panadería sume un producto por
 * paquete, el pedido mínimo de 50 unidades y este cobro por adelantado tienen
 * que seguir yendo del mismo lado.
 */
function esCandidatoAPagoAdelanto({ tiendaSlug, hayPanPorUnidad }) {
  return SLUGS_PAGO_ADELANTO.includes(String(tiendaSlug || '').trim()) && Boolean(hayPanPorUnidad);
}

/**
 * El interruptor global, leído de `Configuraciones` en cada llamada.
 *
 * Sin caché a propósito (ver [CLAVE_EXIGE_PAGO_ADELANTADO]). Si la consulta
 * falla o la clave no existe, cae a [EXIGE_PAGO_ADELANTADO_POR_DEFECTO]
 * (apagado) en vez de propagar el error: que la base de configuración esté
 * incompleta no puede ser motivo para que nadie pueda pedir pan.
 */
async function exigePagoAdelantadoConfigurado(pool) {
  try {
    const result = await pool
      .request()
      .input('Clave', CLAVE_EXIGE_PAGO_ADELANTADO)
      .query('SELECT Valor FROM Configuraciones WHERE Clave = @Clave');
    const valor = result.recordset[0]?.Valor;
    if (valor === undefined || valor === null) return EXIGE_PAGO_ADELANTADO_POR_DEFECTO;
    // Solo '1' enciende. Cualquier otra cosa ('0', '', 'true', basura) apaga:
    // el valor lo edita un humano desde la app y un "sí" ambiguo no puede
    // terminar en un cobro obligatorio.
    return String(valor).trim() === '1';
  } catch (err) {
    console.warn('No se pudo leer EXIGE_PAGO_ADELANTADO_PANADERIA, se asume apagado:', err.message);
    return EXIGE_PAGO_ADELANTADO_POR_DEFECTO;
  }
}

/**
 * ¿Este cliente en concreto tiene permiso para pedir SIN pagar primero?
 *
 * `Clientes.PideSinPagarAdelanto` — la excepción que pidió el dueño para los
 * clientes de siempre, los que le pagan la semana o el mes completo de una
 * vez (bodegas, puestos de mercado). Para ellos exigir tarjeta pedido por
 * pedido sería romperles la forma de trabajar que ya tenían acordada.
 *
 * `idCliente` puede venir null (un visitante que todavía no existe como
 * cliente en la base): sin fila no hay excepción posible, así que se
 * responde false sin consultar nada.
 *
 * También falla CERRADO al revés que el toggle: si la consulta revienta, se
 * asume que NO tiene la excepción (o sea, se le exige pagar). Regalar la
 * excepción por un error de base sería regalar pan al fiado.
 */
async function clientePideSinPagarAdelanto(pool, idCliente) {
  if (idCliente === null || idCliente === undefined) return false;
  try {
    const result = await pool
      .request()
      .input('IdCliente', idCliente)
      .query('SELECT PideSinPagarAdelanto FROM Clientes WHERE IdCliente = @IdCliente');
    return Boolean(result.recordset[0]?.PideSinPagarAdelanto);
  } catch (err) {
    // Incluye el caso "la migración 2026_09_excepcion_pago_adelanto todavía
    // no se corrió" (Unknown column): el sistema sigue funcionando como
    // antes de la excepción, sin tumbar el pedido.
    console.warn('No se pudo leer Clientes.PideSinPagarAdelanto, se asume sin excepción:', err.message);
    return false;
  }
}

/**
 * ¿Este pedido web exige pagar por adelantado? EL portón, las tres
 * condiciones juntas:
 *
 *   1. la tienda y el producto son candidatos (Panadería, pan por unidad);
 *   2. el dueño tiene el cobro ENCENDIDO en Configuraciones;
 *   3. este cliente NO tiene la excepción de "paga después".
 *
 * El orden importa por costo: la condición 1 es pura y descarta de una todos
 * los pedidos de hamburguesa sin gastar ni una consulta. La 3 solo se
 * consulta si la 2 dio verdadero, porque con el cobro apagado la excepción
 * es irrelevante.
 */
async function requierePagoAdelanto({ pool, tiendaSlug, hayPanPorUnidad, idCliente }) {
  if (!esCandidatoAPagoAdelanto({ tiendaSlug, hayPanPorUnidad })) return false;
  if (!pool) return false;
  if (!(await exigePagoAdelantadoConfigurado(pool))) return false;
  return !(await clientePideSinPagarAdelanto(pool, idCliente));
}

/**
 * El código tal como se guarda: sin espacios alrededor y sin los espacios
 * que la app de Yape a veces mete al copiar. No se toca nada más — es un
 * dato que emitió otro sistema, no nuestro.
 *
 * Devuelve '' para cualquier cosa que no sea un texto con contenido, para
 * que quien llama compare contra un solo caso vacío.
 */
function normalizarCodigoOperacion(codigo) {
  if (typeof codigo !== 'string' && typeof codigo !== 'number') return '';
  return String(codigo).replace(/\s+/g, '').trim();
}

/**
 * ¿El código que escribió el cliente tiene forma de código de operación?
 *
 * Solo dígitos y no más largo que [LARGO_MAXIMO_CODIGO]. A propósito NO
 * exige un largo exacto (ver el comentario de esa constante). Que el código
 * corresponda a un pago REAL no lo puede saber nadie acá: eso lo confirma
 * una persona mirando su Yape, y que no se use dos veces lo garantiza el
 * UNIQUE de la base.
 */
function codigoOperacionValido(codigo) {
  const limpio = normalizarCodigoOperacion(codigo);
  return limpio.length > 0 && limpio.length <= LARGO_MAXIMO_CODIGO && /^\d+$/.test(limpio);
}

/**
 * Revisión del monto que el cliente DECLARA haber pagado, contra el total
 * real del pedido.
 *
 * Es a propósito una red blanda: atrapa el error honesto (tecleó 5 en vez
 * de 50, o no sumó bien) antes de que el pedido entre. NO pretende impedir
 * que alguien mienta — quien escriba "50" y haya pagado 5 pasa esta
 * validación igual, y lo va a descubrir el personal al verificar contra el
 * Yape real. Por eso nunca se hace una sola cuenta de plata con este valor.
 *
 * Pagar de MÁS sí se acepta: es un caso real (el cliente redondea) y
 * termina en un vuelto pendiente, no en un rechazo.
 */
function validarMontoDeclarado(total, montoDeclarado) {
  const monto = Number(montoDeclarado);
  if (!Number.isFinite(monto) || monto <= 0) {
    return { valido: false, mensaje: 'Indica cuánto pagaste por Yape.' };
  }
  if (aCentimos(monto) < aCentimos(total)) {
    return {
      valido: false,
      mensaje: `El monto que indicaste (S/ ${monto.toFixed(2)}) es menor que el total del pedido (S/ ${Number(total).toFixed(2)}). Revisa tu comprobante de Yape.`,
    };
  }
  return { valido: true, mensaje: null };
}

/**
 * EL cálculo del feature: qué pasa cuando el personal confirma cuánto llegó
 * DE VERDAD a la cuenta de Yape.
 *
 * Los TRES resultados dejan el pedido validado (quien llama lo pasa a
 * `Estado = 'CONFIRMADO'`): en los tres el pago existe y el pan hay que
 * prepararlo. Lo único que cambia es si además queda algo por saldar:
 *
 *   justo      -> PAGADO            , sin ajuste
 *   de menos   -> DEUDA_PARCIAL     , ajuste DEUDA  por lo que falta
 *   de más     -> VUELTO_PENDIENTE  , ajuste VUELTO por lo que sobra
 *
 * `ajuste` es null o `{ tipo, monto }` con `monto` SIEMPRE positivo: quién
 * le debe a quién lo dice `tipo`, no el signo (ver CK_AjustesPago_Monto).
 * El personal nunca elige el resultado a mano — escribe un número y esto
 * lo deduce; un menú de tres opciones solo abriría la puerta a marcar
 * "pagado" sobre un pago incompleto.
 */
function resolverPagoAdelanto(total, montoConfirmado) {
  const totalCentimos = aCentimos(total);
  const confirmadoCentimos = aCentimos(montoConfirmado);
  const diferencia = confirmadoCentimos - totalCentimos;

  if (diferencia === 0) {
    return { estadoPagoAdelanto: ESTADO_PAGADO, ajuste: null };
  }
  if (diferencia < 0) {
    return {
      estadoPagoAdelanto: ESTADO_DEUDA_PARCIAL,
      ajuste: { tipo: AJUSTE_DEUDA, monto: aSoles(-diferencia) },
    };
  }
  return {
    estadoPagoAdelanto: ESTADO_VUELTO_PENDIENTE,
    ajuste: { tipo: AJUSTE_VUELTO, monto: aSoles(diferencia) },
  };
}

/**
 * Mensaje para el personal justo después de confirmar — la misma frase que
 * ve en la app y que queda en la auditoría, para que no haya dos redacciones
 * distintas del mismo hecho.
 */
function describirResultadoPago({ estadoPagoAdelanto, ajuste }) {
  switch (estadoPagoAdelanto) {
    case ESTADO_PAGADO:
      return 'Pago verificado: el monto coincide exactamente con el total.';
    case ESTADO_DEUDA_PARCIAL:
      return `Pago verificado, pero falta S/ ${ajuste.monto.toFixed(2)}: cóbralo al entregar.`;
    case ESTADO_VUELTO_PENDIENTE:
      return `Pago verificado con S/ ${ajuste.monto.toFixed(2)} de más: devuélvelo al entregar.`;
    default:
      return 'Pago verificado.';
  }
}

module.exports = {
  ESTADO_NO_APLICA,
  ESTADO_VERIFICANDO,
  ESTADO_PAGADO,
  ESTADO_DEUDA_PARCIAL,
  ESTADO_VUELTO_PENDIENTE,
  AJUSTE_DEUDA,
  AJUSTE_VUELTO,
  SLUGS_PAGO_ADELANTO,
  CLAVE_EXIGE_PAGO_ADELANTADO,
  EXIGE_PAGO_ADELANTADO_POR_DEFECTO,
  FRACCION_MINIMA_PAGO_ADELANTO,
  LARGO_MAXIMO_CODIGO,
  aCentimos,
  aSoles,
  montoMinimoAPagar,
  esCandidatoAPagoAdelanto,
  exigePagoAdelantadoConfigurado,
  clientePideSinPagarAdelanto,
  requierePagoAdelanto,
  normalizarCodigoOperacion,
  codigoOperacionValido,
  validarMontoDeclarado,
  resolverPagoAdelanto,
  describirResultadoPago,
};
