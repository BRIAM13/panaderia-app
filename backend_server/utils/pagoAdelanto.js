// Pago por adelantado con Yape en el pedido web de Panadería.
//
// Todo lo de este archivo es PURO a propósito (ni una consulta, ni un
// `require` de la base): la cuenta de "¿pagó justo, de menos o de más?" es
// la que decide si al cliente le queda un saldo o un vuelto, y tiene que
// poder probarse sola, sin levantar nada. Mismo criterio que
// `descuentosCliente.js` y `horariosPanaderia.js`, donde el cálculo vive
// aparte del controlador que toca la base.
//
// Ver `database_migrations/2026_09_pago_adelanto_panaderia.sql` para el
// porqué de cada columna, y en particular por qué esto NO reutiliza
// `Pedidos.EstadoPago` (que significa el fiado posterior a la entrega y
// alimenta todos los reportes de deuda del sistema).

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
 * Tiendas donde el pedido web exige pagar por adelantado. Hardcodeada a
 * `panaderia` a propósito, a diferencia de los descuentos (que se habilitan
 * por tienda desde Configuraciones): esto no es una promoción que el dueño
 * prenda y apague, es el modelo de cobro de ESE negocio. El pan de
 * hamburguesa, según el dueño, es un negocio aparte y sigue cobrándose al
 * recoger.
 */
const SLUGS_PAGO_ADELANTO = ['panaderia'];

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
 * ¿Este pedido web exige pagar por adelantado?
 *
 * Las dos condiciones juntas, no una sola: la tienda tiene que estar en la
 * lista Y el pedido tiene que ser de pan por unidad. Hoy las dos dicen lo
 * mismo (en Panadería todo se vende por unidad), pero el día que Panadería
 * sume un producto por paquete, el pedido mínimo de 50 unidades y este
 * cobro por adelantado tienen que seguir yendo del mismo lado.
 */
function requierePagoAdelanto({ tiendaSlug, hayPanPorUnidad }) {
  return SLUGS_PAGO_ADELANTO.includes(String(tiendaSlug || '').trim()) && Boolean(hayPanPorUnidad);
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
  LARGO_MAXIMO_CODIGO,
  requierePagoAdelanto,
  normalizarCodigoOperacion,
  codigoOperacionValido,
  validarMontoDeclarado,
  resolverPagoAdelanto,
  describirResultadoPago,
};
