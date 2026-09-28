/**
 * Utilidades puras para el pago con Yape a través de Culqi. Igual que
 * `tarjeta.ts`: solo formato y validación del lado del cliente, sin DOM, sin
 * red — se prueba entera con vitest.
 *
 * CÓMO FUNCIONA YAPE POR CULQI (confirmado el 2026-09-27 contra el bundle
 * `https://checkout.culqi.com/js/v4` y el demo oficial
 * `culqi/culqi-reactjs-demo-jsv4`, GitHub): el cliente NO recibe nada
 * nuestro. Abre SU app de Yape, en "Yapear con código de aprobación" genera
 * un código de 6 dígitos (vale ~2 minutos), y escribe acá ese código junto
 * con su número de celular. CulqiJS v4 lee esos dos campos del DOM
 * (`yape[phone]` y `yape[code]`), los manda a `/v2/tokens/yape` junto con
 * el monto que le dimos en `Culqi.settings`, y devuelve un token
 * `ype_test_…`/`ype_live_…` (prefijo propio, distinto del `tkn_` de tarjeta,
 * pero mismo objeto `{ object: "token", id }`) que el backend cobra con el
 * MISMO endpoint y el mismo `POST /charges` de Culqi. Lo que valida este
 * archivo es lo que se puede atrapar antes de gastar ese viaje: que el
 * celular parezca un celular peruano y que el código tenga 6 dígitos.
 */

import { soloDigitos } from "./tarjeta";

/** Un celular peruano son 9 dígitos y siempre empieza con 9 — es la misma
 * regla que ya usa el resto del sitio para el celular del pedido. */
export const LARGO_CELULAR = 9;

/** El código de aprobación que genera la app de Yape: exactamente 6 dígitos. */
export const LARGO_CODIGO_YAPE = 6;

/**
 * Techo y piso que CulqiJS v4 aplica al monto ANTES de generar el token de
 * Yape (en el bundle: `yape: { min: 6, max: 2000 }` soles, convertidos a
 * céntimos con `uo()`). Si el total no cae en ese rango, `Culqi.
 * paymentOptionsAvailable.yape.available` viene en `false` con un mensaje
 * genérico en inglés-español mezclado ("El monto ingresado debe ser mayor a
 * PEN 6.00 y menor a PEN 2,000.00"). Se conocen acá para poder avisarlo
 * ANTES, con palabras nuestras, y ofrecer la tarjeta en su lugar — no para
 * reemplazar la validación de Culqi, que sigue corriendo igual.
 *
 * El máximo coincide con el límite que Yape publica por operación (S/ 2000).
 */
export const MONTO_MINIMO_YAPE = 6;
export const MONTO_MAXIMO_YAPE = 2000;

/** Lo que de verdad queda escrito en el campo de celular mientras el cliente
 * teclea: solo dígitos, cortado a 9. */
export function limpiarCelular(valor: string): string {
  return soloDigitos(valor).slice(0, LARGO_CELULAR);
}

/**
 * Formato "en vivo" del celular mientras se teclea: "987 654 321", en grupos
 * de 3, que es como los peruanos dictan y leen un número de celular. Solo es
 * visual: a Culqi se le entregan los 9 dígitos pelados (ver `limpiarCelular`).
 */
export function formatearCelular(valor: string): string {
  const limpio = limpiarCelular(valor);
  return limpio.replace(/(\d{3})(?=\d)/g, "$1 ");
}

/**
 * ¿Parece un celular peruano? 9 dígitos y el primero es 9. No confirma que el
 * número exista ni que tenga Yape — eso lo resuelve Culqi/Yape cuando
 * generamos el token. Es el mismo criterio que `telefonoResuelto` en
 * `PedidoForm`, más el "empieza con 9" que ahí no hacía falta pero acá sí:
 * Yape solo funciona con celulares, y en Perú todos los celulares van con 9.
 */
export function celularPeruanoValido(valor: string): boolean {
  return /^9\d{8}$/.test(soloDigitos(valor));
}

/** El código de aprobación solo se limpia a dígitos y se corta a 6. */
export function limpiarCodigoYape(valor: string): string {
  return soloDigitos(valor).slice(0, LARGO_CODIGO_YAPE);
}

/** ¿El código de aprobación tiene la forma correcta (exactamente 6 dígitos)? */
export function codigoYapeValido(valor: string): boolean {
  return /^\d{6}$/.test(soloDigitos(valor));
}

/**
 * Cómo se ve el celular en el panel de vista previa mientras se escribe: los
 * dígitos ya tecleados y, para los que faltan, un "•" de relleno — así el
 * panel nunca se ve "vacío a medias", igual que hace `numeroTarjetaEnmascarado`
 * con la tarjeta. A diferencia de la tarjeta, acá NO se tapa nada: el celular
 * no es un dato sensible y verlo entero ayuda a detectar el dígito mal
 * tecleado antes de generar el token.
 */
export function celularParaVistaPrevia(valor: string): string {
  const limpio = limpiarCelular(valor);
  const relleno = limpio + "•".repeat(Math.max(LARGO_CELULAR - limpio.length, 0));
  return relleno.replace(/(.{3})(?=.)/g, "$1 ");
}

/**
 * ¿Se puede pagar este total con Yape? Devuelve null si sí, o el motivo en
 * palabras del cliente si no — el componente lo muestra en lugar del
 * formulario y deja la tarjeta como camino. Un total no cobrable (NaN, cero)
 * también se rechaza: no hay nada que Yapear.
 */
export function motivoYapeNoDisponible(total: number): string | null {
  if (!Number.isFinite(total) || total <= 0) {
    return "Este pedido no tiene un monto que se pueda pagar con Yape.";
  }
  if (total > MONTO_MAXIMO_YAPE) {
    return `Yape acepta hasta S/ ${MONTO_MAXIMO_YAPE.toLocaleString("es-PE")} por operación y este pedido lo supera. Págalo con tarjeta, o escríbenos para dividirlo.`;
  }
  if (total < MONTO_MINIMO_YAPE) {
    return `Yape por Culqi necesita un monto de al menos S/ ${MONTO_MINIMO_YAPE.toFixed(2)}. Este pedido puedes pagarlo con tarjeta.`;
  }
  return null;
}
