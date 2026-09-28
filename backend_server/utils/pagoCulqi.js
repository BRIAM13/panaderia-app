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
// DEUDA_PARCIAL y VUELTO_PENDIENTE. Con Culqi es el SERVIDOR el que pide un
// cargo por un monto exacto, calculado por él y nunca tomado del body.
//
// DESDE EL 2026-09-28 ese monto exacto ya NO es siempre el total del pedido:
// el cliente puede pagar entre el 50% y el 100% para "separar" su pedido (ver
// `montoMinimoAPagar` en pagoAdelanto.js), y lo que falte queda como saldo a
// cobrar al recoger — exactamente el mismo DEUDA_PARCIAL + AjustesPago del
// flujo de Yape, que por eso no se tiró nunca. Así que DEUDA_PARCIAL pasó de
// ser un caso raro de contingencia a ser el camino normal de la mitad de los
// pedidos.
//
// Y encima el cargo a la tarjeta NO es el monto que va al pedido: arriba de
// eso viaja la comisión de la pasarela, que paga el cliente (ver
// `calcularMontoConComision` y el bloque de constantes de comisión). Las tres
// cifras son distintas y conviene no confundirlas nunca:
//   montoElegido  lo que el cliente abona A SU PEDIDO (decide el estado)
//   comision      lo que se le cobra de más por usar la pasarela
//   montoACobrar  lo que de verdad sale de su tarjeta/Yape (= los dos de arriba)
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

// =====================================================================
// LA COMISIÓN DE CULQI — LAS DOS CONSTANTES QUE HAY QUE RECONFIRMAR
// =====================================================================
//
// Decisión de negocio del dueño (2026-09-28): la comisión de la pasarela la
// paga EL CLIENTE, no el negocio. O sea que al dueño le tiene que llegar
// LIMPIO lo que el cliente decidió abonar a su pedido, y lo que se le cobra a
// la tarjeta/Yape es un poco más (ver `calcularMontoConComision`).
//
// ⚠️ DE DÓNDE SALEN ESTOS DOS NÚMEROS, Y POR QUÉ HAY QUE VOLVER A MIRARLOS.
//    Salen de un cargo REAL contra la cuenta de ESTE comercio en modo PRUEBA
//    (2026-09-28, `venta_exitosa`, amount 4550 céntimos): comisión fija de
//    S/ 1.00 + IGV y comisión variable de 1% + IGV sobre el monto cobrado.
//    NO son una tarifa universal de Culqi: cada comercio negocia la suya, y
//    la de la cuenta en producción puede NO ser la de prueba.
//
//    CUANDO EL COMERCIO PASE A PRODUCCIÓN hay que abrir CulqiPanel ->
//    "Desarrollo" -> "Ver comisión producto", leer la tarifa real de la
//    cuenta y corregir estas dos constantes. Si quedan mal, el error es
//    silencioso y acumulativo: nadie va a ver un mensaje de error, solo que
//    al dueño le llega un poco menos (o un poco más) de lo que creía por cada
//    pedido cobrado.
//
//    Están acá arriba, juntas y con nombre propio, justamente para que
//    cambiarlas sea una edición de dos líneas y no una cacería.

/** Comisión FIJA por transacción, en soles, IGV incluido: S/ 1.00 + 18%. */
const COMISION_FIJA_SOLES = 1.18;

/** Comisión VARIABLE como fracción del monto cobrado, IGV incluido:
 * 1% * 1.18 = 0.0118 (o sea 1.18% de lo que se le cobra a la tarjeta). */
const TASA_COMISION_VARIABLE = 0.0118;

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
 * "Engrosar" (gross-up) el monto a cobrar para que al dueño le llegue LIMPIO
 * `montoNetoDeseado`.
 *
 * Culqi se queda con su comisión ANTES de depositar, así que cobrar exactamente
 * lo que el cliente eligió abonar a su pedido haría que al negocio le llegara
 * menos que eso — y el pedido quedaría "pagado" con plata que no entró
 * completa. La cuenta es el álgebra estándar de un gross-up con comisión fija
 * más comisión variable:
 *
 *     neto = cobrado - fija - tasa * cobrado
 *     cobrado = (neto + fija) / (1 - tasa)
 *
 * Ejemplo con las constantes de hoy (S/ 1.18 fija, 1.18% variable):
 *   neto S/ 45.50 -> (4550 + 118) / 0.9882 = 4723.74 -> 4724 céntimos
 *                 -> se le cobra S/ 47.24 y la comisión es S/ 1.74.
 *
 * COMPROBADO CONTRA UN CARGO REAL (2026-09-28, cuenta de prueba de este
 * comercio, cargo `chr_test_eJeIj4O0JboCRKZU`): se pidió un cargo por los 4724
 * céntimos que calcula esta función para un neto de S/ 45.50, y Culqi reportó
 * `fee_details.fixed_fee.total: 118`, `variable_fee.total: 55`,
 * `total_fee: 173` y `net_amount: 4551`. O sea que al dueño le llegaron
 * S/ 45.51 — un céntimo MÁS que los S/ 45.50 que el cliente eligió abonar, no
 * menos. El céntimo de diferencia es el del redondeo (Culqi trunca su comisión
 * variable de 55.7 a 55 céntimos) y cae del lado del negocio, que es el lado
 * correcto: el dueño nunca recibe menos de lo que se le acreditó al pedido.
 *
 * TODA la cuenta en CÉNTIMOS ENTEROS, con UN SOLO redondeo al final (mismo
 * criterio que `aCentimosCulqi` y que `aCentimos` de pagoAdelanto.js):
 * redondear antes —por ejemplo la comisión por separado y después sumarla—
 * arrastra el error y deja al neto un céntimo corto, que es justo el céntimo
 * que el dueño no quería regalar. `Math.round` y no `Math.ceil`: medio céntimo
 * no se le cobra a nadie, y el redondeo al más cercano es el que mantiene
 * `comision` fiel a la tarifa real.
 *
 * Devuelve `{ montoACobrar, comision }` en SOLES con 2 decimales, donde
 * `comision = montoACobrar - montoNetoDeseado` (o sea: exactamente lo que el
 * cliente paga de más por usar la pasarela, que es lo que hay que mostrarle en
 * el desglose). Devuelve null para un neto que no es cobrable (no numérico,
 * cero, negativo), igual que `aCentimosCulqi`: quien llama corta ahí.
 */
function calcularMontoConComision(montoNetoDeseado) {
  const netoCentimos = aCentimosCulqi(montoNetoDeseado);
  if (netoCentimos === null) return null;

  const fijaCentimos = Math.round(COMISION_FIJA_SOLES * 100);
  const cobrarCentimos = Math.round((netoCentimos + fijaCentimos) / (1 - TASA_COMISION_VARIABLE));

  const montoACobrar = aSolesCulqi(cobrarCentimos);
  return {
    montoACobrar,
    comision: aSolesCulqi(cobrarCentimos - netoCentimos),
  };
}

/**
 * ¿Tiene forma de token de Culqi?
 *
 * Los tokens de tarjeta son `tkn_test_…` / `tkn_live_…`; los de Yape (que
 * CulqiJS v4 genera a partir del celular + código de aprobación del cliente)
 * son `ype_test_…` / `ype_live_…`. Los dos se cobran igual, como `source_id`
 * del mismo `POST /charges` — comprobado el 2026-09-27 con un cargo real de
 * prueba: token `ype_test_…` -> `outcome.type: 'venta_exitosa'`. Antes de
 * eso, esta función solo conocía `tkn_` y habría rechazado todo pago por
 * Yape con un 400 sin que Culqi llegara a enterarse.
 *
 * La validación es a propósito laxa (prefijo + largo razonable + solo
 * caracteres de token): el que decide de verdad si el token sirve es Culqi,
 * y un formato nuevo de su lado no debería romper el cobro acá. Esto solo
 * evita mandarle a la API una cadena obviamente inventada.
 */
function tokenCulqiValido(token) {
  if (typeof token !== 'string') return false;
  const limpio = token.trim();
  return /^(tkn|ype)_(test|live)_[A-Za-z0-9]{6,60}$/.test(limpio);
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
 * OJO con lo que este número NO es: desde que la comisión la paga el cliente,
 * esto incluye la comisión y por lo tanto NO es lo que entró al pedido. La
 * cuenta de saldos (`resolverPagoAdelanto`) se hace con `montoElegido`, no con
 * esto. Sirve para la auditoría: es la constancia de cuánto dijo Culqi haber
 * cobrado de verdad, contra lo que le pedimos. Si la respuesta no trae
 * `amount` utilizable, devuelve null y quien llama cae al monto que pidió
 * cobrar — lo único defendible sin más información.
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
  COMISION_FIJA_SOLES,
  TASA_COMISION_VARIABLE,
  MENSAJE_RECHAZO_GENERICO,
  MENSAJE_SIN_RESPUESTA,
  MENSAJES_POR_DECLINE_CODE,
  culqiConfigurado,
  aCentimosCulqi,
  aSolesCulqi,
  calcularMontoConComision,
  tokenCulqiValido,
  traducirErrorCulqi,
  montoCobradoEnSoles,
  crearCargoCulqi,
};
