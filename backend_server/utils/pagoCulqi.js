// Pago con tarjeta por la pasarela CULQI en el pedido web de Panadería.
//
// Reemplaza al pago por adelantado con código de operación de Yape (dado de
// baja el 2026-09-17), pero NO reemplaza su infraestructura: los estados
// (`EstadoPagoAdelanto`), la máquina de estados del pedido ('CONFIRMADO') y
// la tabla `AjustesPago` son los MISMOS y viven en `utils/pagoAdelanto.js`.
// Este archivo solo agrega lo que Culqi trae de nuevo: hablar con su API y
// traducir su respuesta a algo que el cliente pueda leer en español.
//
// LA DIFERENCIA DE FONDO CON YAPE. Con Yape, el monto lo DECLARABA el
// cliente y lo verificaba a mano una persona mirando su app — de ahí la
// posibilidad real de que llegara de menos o de más, y por eso existen
// DEUDA_PARCIAL y VUELTO_PENDIENTE. Con Culqi es el servidor el que pide un
// cargo por un monto EXACTO (`pedido.Total`), así que en la práctica el
// resultado va a ser siempre PAGADO. Aun así el cálculo de la diferencia se
// sigue haciendo con `resolverPagoAdelanto` en vez de asumir PAGADO a ciegas:
// cuesta nada, y el día que haya un reembolso parcial o una captura por un
// monto distinto, el saldo queda registrado igual que antes en vez de
// perderse en silencio.
//
// ---------------------------------------------------------------------
// API USADA (documentación oficial, consultada el 2026-09-26)
//
//   POST https://api.culqi.com/v2/charges
//   Authorization: Bearer <CULQI_SECRET_KEY>   (la llave sk_..., NUNCA la
//                                               pk_ pública, que es la que
//                                               usa el navegador)
//   Content-Type: application/json
//   {
//     "amount":        5000,        // ENTERO, en CÉNTIMOS (S/ 50.00 -> 5000)
//     "currency_code": "PEN",
//     "email":         "cliente@correo.com",
//     "source_id":     "tkn_live_…", // el token que tokenizó el navegador
//     "description":   "…",
//     "metadata":      { … }
//   }
//
//   Éxito   -> 2xx con { object: 'charge', id: 'chr_…', amount, outcome: {…} }
//   Rechazo -> 4xx con { object: 'error', type: 'card_error',
//                        code: 'card_declined', decline_code: 'insufficient_funds',
//                        merchant_message: '…', user_message: '…' }
//
//   Fuentes:
//     https://docs.culqi.com/es/documentacion/pagos-online/cargo-unico/cargos/
//     https://docs.culqi.com/es/documentacion/pagos-online/denegaciones/
//
// ⚠️ `amount` EN CÉNTIMOS es el error más fácil y más caro de cometer acá:
//    mandar `50` en vez de `5000` le cobra S/ 0.50 a quien pidió S/ 50 de
//    pan, y el pedido quedaría marcado como pagado. Por eso la conversión
//    tiene su propia función probada (`aCentimosCulqi`) y el controlador
//    nunca arma el número a mano.

const axios = require('axios');

/** Base de la API REST de Culqi (lado servidor). Sobreescribible por entorno
 * solo para poder apuntar a un mock en pruebas manuales; en producción nunca
 * se define y queda la oficial. */
const CULQI_API_URL = process.env.CULQI_API_URL || 'https://api.culqi.com/v2';

/** Culqi solo cobra en soles o dólares; Panadería cobra en soles. */
const MONEDA = 'PEN';

/** Un cargo no debería tardar más que una consulta de DNI (6s): el cliente
 * está mirando una pantalla de "procesando" con su tarjeta ya tokenizada. Si
 * Culqi no contesta en 20s, mejor decírselo y que reintente que dejarlo
 * colgado sin saber si le cobraron. */
const TIMEOUT_MS = 20000;

/**
 * ¿Está configurada la llave secreta de Culqi?
 *
 * Se consulta ANTES de tocar el pedido: sin llave no hay forma de cobrar, y
 * la respuesta correcta es un 503 ("todavía no está configurado"), no un 500
 * genérico ni —peor— un pedido que se queda a medio camino. El dueño todavía
 * está tramitando la cuenta Culqi (RUC a nombre de su padre), así que este
 * caso es el estado NORMAL del sistema hasta que la llene.
 */
function culqiConfigurado() {
  return typeof process.env.CULQI_SECRET_KEY === 'string' && process.env.CULQI_SECRET_KEY.trim().length > 0;
}

/**
 * Soles a céntimos ENTEROS, que es la única unidad que acepta Culqi.
 *
 * `Math.round` y no `Math.trunc` a propósito: `50.10 * 100` da
 * `5009.999999999999` en punto flotante, y truncar cobraría S/ 50.09 —
 * un céntimo de menos en cada pedido con decimales. Mismo criterio que
 * `aCentimos` en `pagoAdelanto.js`, de donde sale toda la cuenta de plata
 * del sistema.
 *
 * Devuelve null para cualquier cosa que no sea un monto cobrable (NaN,
 * negativo, cero): quien llama tiene que cortar ahí, no mandarle basura a
 * la pasarela.
 */
function aCentimosCulqi(soles) {
  const monto = Number(soles);
  if (!Number.isFinite(monto) || monto <= 0) return null;
  const centimos = Math.round(monto * 100);
  return centimos > 0 ? centimos : null;
}

/** Céntimos enteros de vuelta a soles con 2 decimales — para comparar lo que
 * Culqi dice haber cobrado contra el `Total` del pedido. */
function aSolesCulqi(centimos) {
  return Number((Number(centimos) / 100).toFixed(2));
}

/**
 * ¿Tiene forma de token de Culqi?
 *
 * Los tokens de tarjeta son `tkn_test_…` / `tkn_live_…`. La validación es a
 * propósito laxa (prefijo + largo razonable + solo caracteres de token): el
 * que decide de verdad si el token sirve es Culqi, y un formato nuevo de su
 * lado no debería romper el cobro acá. Esto solo evita mandarle a la API una
 * cadena obviamente inventada.
 */
function tokenCulqiValido(token) {
  if (typeof token !== 'string') return false;
  const limpio = token.trim();
  return /^tkn_(test|live)_[A-Za-z0-9]{6,60}$/.test(limpio);
}

/**
 * Mensajes en español para cada `decline_code` documentado por Culqi.
 *
 * Culqi ya manda un `user_message` en español y ESE es el que se prefiere
 * (ver `traducirErrorCulqi`): es el texto que su equipo mantiene al día con
 * lo que de verdad dicen los bancos. Esta tabla es la red de seguridad para
 * cuando la respuesta no trae `user_message`, y además deja claro en el
 * código qué rechazos se esperan.
 *
 * Todos los mensajes terminan igual, en una acción concreta: el pedido SIGUE
 * existiendo en 'VERIFICANDO', así que el cliente siempre puede reintentar
 * con otra tarjeta. Un error de pago que no dice qué hacer después manda al
 * cliente a WhatsApp, que es justo lo que esta pantalla vino a evitar.
 */
const MENSAJES_POR_DECLINE_CODE = {
  expired_card: 'Tu tarjeta está vencida o la fecha de vencimiento no coincide. Revísala o prueba con otra.',
  stolen_card: 'El banco bloqueó esta tarjeta. Usa otra tarjeta para pagar tu pedido.',
  lost_card: 'El banco bloqueó esta tarjeta. Usa otra tarjeta para pagar tu pedido.',
  insufficient_funds: 'Tu tarjeta no tiene saldo suficiente para este pedido. Prueba con otra tarjeta.',
  contact_issuer: 'Tu banco no autorizó el pago. Llámalos para habilitar la compra por internet, o prueba con otra tarjeta.',
  invalid_cvv: 'El código de seguridad (CVV) no es válido. Vuelve a escribirlo tal como está en tu tarjeta.',
  incorrect_cvv: 'El código de seguridad (CVV) no coincide. Vuelve a escribirlo tal como está en tu tarjeta.',
  too_many_attempts_cvv: 'Se intentó demasiadas veces con un código de seguridad incorrecto. Espera un momento o usa otra tarjeta.',
  issuer_not_available: 'Tu banco no está respondiendo en este momento. Intenta de nuevo en unos minutos.',
  issuer_decline_operation: 'Tu banco rechazó el pago. Llámalos para saber por qué, o prueba con otra tarjeta.',
  invalid_card: 'Tu tarjeta tiene restricciones para este tipo de compra. Prueba con otra tarjeta.',
  processing_error: 'Hubo un problema al procesar el pago. Intenta de nuevo en unos minutos.',
  fraudulent: 'Tu banco rechazó el pago por seguridad. Llámalos para autorizarlo, o prueba con otra tarjeta.',
  culqi_card: 'Esa es una tarjeta de prueba y no sirve para pagar de verdad. Usa tu tarjeta real.',
};

/** Lo que se le dice al cliente cuando Culqi rechazó el cobro pero no se
 * entiende por qué (respuesta sin `user_message` ni `decline_code` conocido).
 * Nunca se le muestra el `merchant_message` crudo: puede traer jerga de
 * procesador que no le sirve de nada y que a veces filtra detalles internos. */
const MENSAJE_RECHAZO_GENERICO =
  'No pudimos cobrar con esa tarjeta. Revisa los datos o prueba con otra — tu pedido sigue guardado.';

/** Cuando la API de Culqi no contesta (red, timeout, caída). Se distingue a
 * propósito del rechazo: acá NO se sabe si hubo cobro o no, y decirle
 * "tarjeta rechazada" a alguien a quien tal vez sí le cobraron sería mentirle. */
const MENSAJE_SIN_RESPUESTA =
  'No pudimos comunicarnos con la pasarela de pago. Si te llegó el cargo, escríbenos por WhatsApp antes de volver a intentar.';

/**
 * Traduce la respuesta de error de Culqi a { mensaje, codigo, declineCode }.
 *
 * Orden de preferencia para el texto: el `user_message` de Culqi (ya viene en
 * español y redactado para el comprador) -> la tabla de arriba por
 * `decline_code` -> el genérico. `codigo`/`declineCode` NO se le muestran al
 * cliente: viajan para quedar en la auditoría y poder reconstruir después
 * por qué falló un cobro.
 */
function traducirErrorCulqi(datos) {
  const cuerpo = datos && typeof datos === 'object' ? datos : {};
  const declineCode = typeof cuerpo.decline_code === 'string' ? cuerpo.decline_code : null;
  const codigo = typeof cuerpo.code === 'string' ? cuerpo.code : null;

  const userMessage = typeof cuerpo.user_message === 'string' ? cuerpo.user_message.trim() : '';
  const mensaje =
    userMessage.length > 0
      ? userMessage
      : (declineCode && MENSAJES_POR_DECLINE_CODE[declineCode]) || MENSAJE_RECHAZO_GENERICO;

  return { mensaje, codigo, declineCode };
}

/**
 * Cuánto cobró Culqi DE VERDAD, en soles, según su propia respuesta.
 *
 * No se asume que sea el monto pedido: es el dato con el que
 * `resolverPagoAdelanto` decide si quedó un saldo o un vuelto (ver el
 * encabezado). Si la respuesta no trae `amount` utilizable, devuelve null y
 * quien llama cae al `Total` del pedido — que es lo que se pidió cobrar y lo
 * único defendible sin más información.
 */
function montoCobradoEnSoles(cargo) {
  const centimos = Number(cargo?.amount);
  if (!Number.isFinite(centimos) || centimos <= 0) return null;
  return aSolesCulqi(centimos);
}

/**
 * Crea el cargo en Culqi. ES LA ÚNICA función de este archivo que sale a la
 * red; todo lo demás es cuenta y texto.
 *
 * Nunca lanza: devuelve un resultado discriminado por `ok`, porque las tres
 * salidas posibles llevan a tres respuestas HTTP distintas y muy diferentes
 * entre sí (201 cobrado / 400 rechazado / 502 sin respuesta), y un try/catch
 * en el controlador tendería a colapsarlas en un 500.
 *
 *   { ok: true,  cargo }                        cobrado
 *   { ok: false, rechazado: true,  mensaje, codigo, declineCode, estado }
 *   { ok: false, rechazado: false, mensaje }    no se sabe si cobró
 */
async function crearCargoCulqi({ centimos, email, tokenId, descripcion, metadata }) {
  try {
    const respuesta = await axios.post(
      `${CULQI_API_URL}/charges`,
      {
        amount: centimos,
        currency_code: MONEDA,
        email,
        source_id: tokenId,
        ...(descripcion ? { description: String(descripcion).slice(0, 80) } : {}),
        // `metadata` es texto libre que queda guardado en el cargo del panel
        // de Culqi. Se manda el pedido para poder cruzar un cargo con su
        // pedido desde el lado de Culqi, sin tener que abrir la base.
        ...(metadata ? { metadata } : {}),
      },
      {
        timeout: TIMEOUT_MS,
        headers: {
          Authorization: `Bearer ${process.env.CULQI_SECRET_KEY.trim()}`,
          'Content-Type': 'application/json',
        },
      },
    );

    // Culqi responde 2xx con el objeto `charge`. Si por lo que sea no vino
    // un id de cargo, se trata como "no se sabe": marcar el pedido como
    // pagado sin un id al que volver sería imposible de auditar o reembolsar.
    if (!respuesta?.data?.id) {
      return { ok: false, rechazado: false, mensaje: MENSAJE_SIN_RESPUESTA };
    }
    return { ok: true, cargo: respuesta.data };
  } catch (err) {
    // Con respuesta HTTP de error: Culqi dijo NO y dijo por qué. Es un
    // rechazo legítimo y el cliente puede reintentar con otra tarjeta.
    if (err.response) {
      const { mensaje, codigo, declineCode } = traducirErrorCulqi(err.response.data);
      return {
        ok: false,
        rechazado: true,
        mensaje,
        codigo,
        declineCode,
        estado: err.response.status,
      };
    }
    // Sin respuesta (timeout, DNS, red caída): NO se sabe si el cobro
    // ocurrió. Se registra en el log del servidor porque es lo único que va
    // a quedar de este intento — el cliente solo ve el mensaje prudente.
    console.error('Culqi no respondió al crear el cargo:', err.message);
    return { ok: false, rechazado: false, mensaje: MENSAJE_SIN_RESPUESTA };
  }
}

module.exports = {
  CULQI_API_URL,
  MONEDA,
  TIMEOUT_MS,
  MENSAJE_RECHAZO_GENERICO,
  MENSAJE_SIN_RESPUESTA,
  MENSAJES_POR_DECLINE_CODE,
  culqiConfigurado,
  aCentimosCulqi,
  aSolesCulqi,
  tokenCulqiValido,
  traducirErrorCulqi,
  montoCobradoEnSoles,
  crearCargoCulqi,
};
