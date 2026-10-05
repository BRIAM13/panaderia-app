import type { AjustePagoPublico, EstadoPagoAdelanto, PedidoPublicoConsultaItem } from "../services/api";

/**
 * Pago por adelantado del pedido de Panadería, lado del cliente.
 *
 * Todo lo de acá es puro: son las mismas reglas que aplica el servidor
 * (`backend_server/utils/pagoAdelanto.js`), repetidas para que el visitante
 * vea el problema ANTES de enviar y no después de un viaje de ida y vuelta.
 * El servidor sigue siendo el que manda — nada de esto lo reemplaza.
 *
 * Hoy el cobro es con TARJETA o YAPE, por la pasarela Culqi (ver
 * `PagoCulqi.tsx` y `pagarConCulqi` en services/api.ts), y desde el
 * 2026-09-28 el cliente elige cuánto abonar AHORA (entre la mitad y el
 * total, para "separar" el pedido) y paga él la comisión de la pasarela: la
 * cuenta de eso —mínimo, comisión, acotado del monto— está en el bloque
 * "PAGO PARCIAL Y COMISIÓN" más abajo, espejo de los dos archivos del
 * backend que la definen. Lo que sigue acá del flujo anterior
 * —el de código de operación de Yape, dado de baja el 2026-09-17— es a
 * propósito:
 *
 *   * [CLAVE_PAGO_PENDIENTE] y compañía: el patrón de "el pedido se crea
 *     ANTES de pagar y se retoma desde localStorage" es EL MISMO y por la
 *     misma razón. Pagar saca al cliente de la página (a Yape entonces, al
 *     3DS de su banco ahora) y al volver la pestaña suele venir recargada.
 *   * `limpiarCodigoOperacion` / `revisarMontoDeclarado` / `montoSugerido`:
 *     los usa `PagoYape.tsx`, que sigue en el repositorio como referencia y
 *     por si hay que atender un pedido viejo que quedó a medias.
 */

/** Largo máximo del código de operación. El mismo tope que
 * `LARGO_MAXIMO_CODIGO` en el backend, y por el mismo motivo: los códigos
 * reales rondan los 7 dígitos, pero exigir un largo EXACTO dejaría fuera un
 * pago legítimo si alguna constancia trae uno más. Esto solo corta una
 * entrada absurda. */
export const LARGO_MAXIMO_CODIGO = 10;

/** Clave de localStorage donde vive el pedido de Panadería creado pero
 * todavía sin código de pago. Existe por una razón concreta: para pagar hay
 * que salir del navegador a la app de Yape, y al volver la pestaña suele
 * venir recargada desde cero. Sin esto, el cliente perdería la pantalla de
 * pago de un pedido que SÍ existe. */
export const CLAVE_PAGO_PENDIENTE = "panaderia.pagoPendiente";

/** Lo mínimo para poder retomar la pantalla de pago tal cual estaba. */
export interface PagoPendienteGuardado {
  idPedido: number;
  token: string;
  numeroPedidoDia: number;
  total: number;
  /** Para poder volver a pintar el resumen del pedido sin pedirlo al
   * servidor. Es una foto de lo que se envió, no una fuente de verdad. */
  producto: string;
  cantidad: string;
  documento: string;
  telefono: string;
  fechaRecojo: string;
  horaRecojo: string;
  notas: string;
  /** Cómo se entrega (2026-10-05). Opcionales: un pendiente guardado antes
   * del delivery no los trae, y se lee como recojo. */
  tipoEntrega?: "RECOJO" | "DELIVERY";
  direccionEntrega?: string;
  /** Para descartar solo el pendiente si quedó de hace mucho (ver
   * [pagoPendienteVigente]). */
  guardadoEn: number;
}

/** Cuánto vale un pendiente guardado. Un día entero: alcanza de sobra para
 * ir a pagar y volver, incluso dejando el celular de lado un rato, y evita
 * que un pedido abandonado hace semanas secuestre el formulario de alguien
 * que quiere pedir de nuevo. */
const VIGENCIA_PENDIENTE_MS = 24 * 60 * 60 * 1000;

export function pagoPendienteVigente(
  pendiente: PagoPendienteGuardado | null,
  ahora: number = Date.now(),
): boolean {
  if (!pendiente) return false;
  return ahora - pendiente.guardadoEn < VIGENCIA_PENDIENTE_MS;
}

/**
 * Lee el pendiente guardado, o null si no hay, está vencido o el contenido
 * no tiene la forma esperada. Nunca lanza: `localStorage` puede estar
 * bloqueado (modo incógnito, permisos del navegador) y eso no puede tumbar
 * la página de pedidos.
 */
export function leerPagoPendiente(almacen: Storage | undefined = obtenerAlmacen()): PagoPendienteGuardado | null {
  if (!almacen) return null;
  try {
    const crudo = almacen.getItem(CLAVE_PAGO_PENDIENTE);
    if (!crudo) return null;
    const dato = JSON.parse(crudo) as Partial<PagoPendienteGuardado>;
    if (typeof dato?.idPedido !== "number" || typeof dato?.token !== "string") return null;
    const pendiente = dato as PagoPendienteGuardado;
    if (!pagoPendienteVigente(pendiente)) {
      borrarPagoPendiente(almacen);
      return null;
    }
    return pendiente;
  } catch {
    return null;
  }
}

export function guardarPagoPendiente(
  pendiente: PagoPendienteGuardado,
  almacen: Storage | undefined = obtenerAlmacen(),
): void {
  if (!almacen) return;
  try {
    almacen.setItem(CLAVE_PAGO_PENDIENTE, JSON.stringify(pendiente));
  } catch {
    // Sin localStorage el flujo sigue funcionando: solo se pierde la
    // posibilidad de retomar la pantalla de pago si la pestaña se muere. La
    // segunda vía (seguimiento por DNI) sigue en pie.
  }
}

export function borrarPagoPendiente(almacen: Storage | undefined = obtenerAlmacen()): void {
  if (!almacen) return;
  try {
    almacen.removeItem(CLAVE_PAGO_PENDIENTE);
  } catch {
    // Ídem.
  }
}

function obtenerAlmacen(): Storage | undefined {
  try {
    return typeof window === "undefined" ? undefined : window.localStorage;
  } catch {
    return undefined;
  }
}

/** Deja solo dígitos — misma limpieza que ya usan el DNI y el celular en
 * PedidoForm. El código de operación de Yape es numérico. */
export function limpiarCodigoOperacion(valor: string): string {
  return valor.replace(/\D/g, "").slice(0, LARGO_MAXIMO_CODIGO);
}

export function codigoOperacionValido(codigo: string): boolean {
  const limpio = limpiarCodigoOperacion(codigo);
  return limpio.length > 0 && limpio === codigo.trim();
}

/**
 * Soles a céntimos enteros. Misma razón que en el backend: `48.10 + 2` no
 * da exactamente `50.10` en punto flotante, y comparar así haría que un
 * pago exacto pareciera insuficiente.
 */
function aCentimos(monto: number): number {
  return Math.round(monto * 100);
}

/** Céntimos enteros de vuelta a soles con 2 decimales — el mismo `aSoles`
 * del backend, para que un monto que pasó por céntimos vuelva sin cola de
 * punto flotante (4724 -> 47.24, no 47.239999). */
function aSoles(centimos: number): number {
  return Number((centimos / 100).toFixed(2));
}

// =====================================================================
// PAGO PARCIAL ("separar el pedido") Y COMISIÓN DE LA PASARELA
// =====================================================================
//
// ⚠️ ESPEJO DEL BACKEND. Las tres constantes y las dos funciones que siguen
//    son una COPIA fiel de:
//      * `FRACCION_MINIMA_PAGO_ADELANTO` y `montoMinimoAPagar`
//        -> backend_server/utils/pagoAdelanto.js
//      * `COMISION_FIJA_SOLES`, `TASA_COMISION_VARIABLE` y
//        `calcularMontoConComision`
//        -> backend_server/utils/pagoCulqi.js
//
//    Existen SOLO para la vista previa: para que lo que el cliente ve en
//    pantalla mientras mueve el monto ("vas a tu pedido S/ X, comisión S/ Y,
//    sale de tu tarjeta S/ Z") coincida centavo a centavo con lo que el
//    servidor va a cobrar de verdad un segundo después. Un desfase de un
//    céntimo entre lo mostrado y lo cobrado es exactamente la clase de bug
//    que rompe la confianza de alguien con su tarjeta.
//
//    EL BACKEND ES LA AUTORIDAD FINAL: recibe `montoElegido` (sin comisión),
//    lo valida contra el rango y calcula la comisión por su cuenta. Nada de
//    lo de acá reemplaza eso. SI CAMBIAN ALLÁ, HAY QUE CAMBIARLAS ACÁ — y
//    en particular las dos de comisión, que salen de la tarifa negociada de
//    ESTE comercio en modo prueba y se van a reconfirmar al pasar a
//    producción (ver el bloque de constantes en pagoCulqi.js).

/** Cuánto del total hay que pagar como MÍNIMO para separar el pedido: la
 * mitad. Decisión de negocio del dueño (2026-09-28). */
export const FRACCION_MINIMA_PAGO_ADELANTO = 0.5;

/** Comisión FIJA de Culqi por transacción, en soles, IGV incluido:
 * S/ 1.00 + 18%. */
export const COMISION_FIJA_SOLES = 1.18;

/** Comisión VARIABLE de Culqi como fracción del monto cobrado, IGV incluido:
 * 1% * 1.18 = 0.0118. */
export const TASA_COMISION_VARIABLE = 0.0118;

/**
 * El mínimo pagable AHORA para separar un pedido de `total` soles: la
 * fracción mínima del total, redondeada al céntimo más cercano — mismo
 * `Math.round` en céntimos enteros que el backend, así el mínimo de un total
 * de S/ 50.05 es S/ 25.03 acá y allá (y no 25.025 de un lado y 25.02 del
 * otro, que rechazaría un pago de exactamente el mínimo mostrado).
 *
 * null para un total que no es cobrable (no numérico, cero, negativo): nunca
 * 0, porque un mínimo de 0 dejaría pasar cualquier monto.
 */
export function montoMinimoAPagar(total: number): number | null {
  const totalCentimos = aCentimos(total);
  if (!Number.isFinite(totalCentimos) || totalCentimos <= 0) return null;
  return aSoles(Math.round(totalCentimos * FRACCION_MINIMA_PAGO_ADELANTO));
}

/**
 * "Engrosar" el monto para que al dueño le llegue LIMPIO `montoNetoDeseado`
 * después de que Culqi se quede con su comisión (fija + variable):
 *
 *     cobrado = (neto + fija) / (1 - tasa)
 *
 * TODA la cuenta en céntimos enteros con UN SOLO redondeo al final, igual
 * que el backend: redondear la comisión aparte y sumarla arrastra un
 * céntimo y deja de coincidir. Con las constantes de hoy, neto S/ 45.50 ->
 * (4550 + 118) / 0.9882 = 4723.74 -> 4724 céntimos -> se cobra S/ 47.24 y
 * la comisión es S/ 1.74 (comprobado contra un cargo real de prueba el
 * 2026-09-28).
 *
 * Devuelve `{ montoACobrar, comision }` en soles con 2 decimales, con
 * `comision = montoACobrar - neto` (lo que el cliente paga de más por usar
 * la pasarela). null para un neto no cobrable.
 */
export function calcularMontoConComision(
  montoNetoDeseado: number,
): { montoACobrar: number; comision: number } | null {
  const netoCentimos = aCentimos(montoNetoDeseado);
  if (!Number.isFinite(netoCentimos) || netoCentimos <= 0) return null;

  const fijaCentimos = Math.round(COMISION_FIJA_SOLES * 100);
  const cobrarCentimos = Math.round((netoCentimos + fijaCentimos) / (1 - TASA_COMISION_VARIABLE));

  return {
    montoACobrar: aSoles(cobrarCentimos),
    comision: aSoles(cobrarCentimos - netoCentimos),
  };
}

/**
 * Lo que de verdad se le manda al servidor como `montoElegido`: el monto que
 * el cliente pidió, encajado en [mínimo, total] y redondeado al céntimo. Es
 * la única puerta por la que pasa cualquier interacción del control de monto
 * (slider, campo de texto, atajos), así nunca hay en pantalla —ni en el
 * botón de pagar, ni en el body— un número que el backend vaya a rechazar.
 *
 * Un `monto` no numérico (campo vacío, "12.") cae al TOTAL, no al mínimo:
 * el estado por defecto del control es "pago completo", y ante la duda es
 * mejor mostrar de más que de menos.
 */
export function acotarMontoElegido(total: number, monto: number): number {
  const minimo = montoMinimoAPagar(total);
  if (minimo === null) return total;
  if (!Number.isFinite(monto)) return aSoles(aCentimos(total));
  const centimos = Math.min(Math.max(aCentimos(monto), aCentimos(minimo)), aCentimos(total));
  return aSoles(centimos);
}

/** Lo que va a quedar por pagar al recoger si el cliente abona `montoElegido`
 * ahora: total - elegido, en céntimos para que 91 - 45.50 dé 45.50 exacto y
 * no 45.499999. Nunca negativo. */
export function saldoPendiente(total: number, montoElegido: number): number {
  return aSoles(Math.max(aCentimos(total) - aCentimos(montoElegido), 0));
}

/**
 * Error que levanta quien llama a `pagarConCulqi` cuando el servidor rechazó
 * el `montoElegido` por estar fuera de rango (400 con `total` y
 * `montoMinimo`). En teoría no puede pasar —el control ya acota en el
 * cliente con la misma cuenta—, pero si pasara (el total del pedido cambió
 * en la base, o esta copia de la fracción quedó desactualizada), la pantalla
 * de pago usa `total`/`montoMinimo` para corregir el control y dejar el
 * botón con el número que el servidor sí va a aceptar. Red de seguridad, no
 * el camino normal.
 */
export class ErrorMontoFueraDeRango extends Error {
  readonly total: number;
  readonly montoMinimo: number;
  constructor(mensaje: string, total: number, montoMinimo: number) {
    super(mensaje);
    this.name = "ErrorMontoFueraDeRango";
    this.total = total;
    this.montoMinimo = montoMinimo;
  }
}

/** ¿El cuerpo de un error del backend trae el rango de un rechazo por monto?
 * Devuelve `{ total, montoMinimo }` cuando vienen los dos como números
 * cobrables, null si no — así quien atrapa el `ApiError` sabe si convertirlo
 * en [ErrorMontoFueraDeRango] o dejarlo como un error de texto común. */
export function rangoDesdeRespuesta(datos: unknown): { total: number; montoMinimo: number } | null {
  if (!datos || typeof datos !== "object") return null;
  const { total, montoMinimo } = datos as { total?: unknown; montoMinimo?: unknown };
  if (typeof total !== "number" || typeof montoMinimo !== "number") return null;
  if (!Number.isFinite(total) || !Number.isFinite(montoMinimo) || total <= 0 || montoMinimo <= 0) return null;
  return { total, montoMinimo };
}

/**
 * La misma revisión que hace el servidor sobre el monto declarado, para que
 * el cliente vea el problema antes de enviar. Devuelve el mensaje listo
 * para mostrar, o null si está todo bien.
 *
 * Es a propósito una red blanda: atrapa el error honesto (tecleó 5 en vez
 * de 50), no la mentira — eso lo descubre el personal comparando contra el
 * Yape real.
 */
export function revisarMontoDeclarado(total: number, montoTexto: string): string | null {
  const monto = Number(montoTexto);
  if (montoTexto.trim().length === 0 || !Number.isFinite(monto) || monto <= 0) {
    return "Indica cuánto pagaste por Yape.";
  }
  if (aCentimos(monto) < aCentimos(total)) {
    return `Pagaste menos que el total (S/ ${total.toFixed(2)}). Revisa el monto de tu constancia de Yape.`;
  }
  return null;
}

/** Lo que el campo de monto trae escrito al abrirse: el total exacto. Es lo
 * que va a pagar la inmensa mayoría, así que la mayoría no tiene que
 * escribir nada — y quien redondeó hacia arriba solo corrige el número. */
export function montoSugerido(total: number): string {
  return total.toFixed(2);
}

/** Deja escribir un importe en soles y nada más: dígitos y UN punto, con
 * hasta dos decimales. Se aplica al teclear, como el `.replace(/\D/g, "")`
 * de los campos numéricos del resto del formulario. */
export function limpiarMonto(valor: string): string {
  const soloValidos = valor.replace(/[^\d.]/g, "");
  const partes = soloValidos.split(".");
  if (partes.length === 1) return partes[0].slice(0, 7);
  return `${partes[0].slice(0, 7)}.${partes.slice(1).join("").slice(0, 2)}`;
}

/** ¿Este pedido todavía está esperando que el cliente lo pague?
 *
 * Es lo que decide si el seguimiento por DNI le ofrece "Pagar con tarjeta" —
 * la segunda vía para quien perdió el localStorage o está en otro
 * dispositivo.
 *
 * El `!codigoOperacionYape` sigue en la condición aunque el pago con código de
 * operación ya no exista: hay pedidos viejos que alcanzaron a mandar su código
 * y están esperando que una persona lo verifique. A ESOS no hay que
 * ofrecerles pagar de nuevo — ya pagaron, por el camino de antes. */
export function esperaPagoDelCliente(pedido: PedidoPublicoConsultaItem): boolean {
  return (
    pedido.estadoPagoAdelanto === "VERIFICANDO" &&
    !pedido.codigoOperacionYape &&
    pedido.estado !== "CANCELADO" &&
    pedido.estado !== "RECHAZADO"
  );
}

export interface AvisoPago {
  texto: string;
  tono: "espera" | "bien" | "atencion";
}

/**
 * La línea que se le muestra al cliente sobre su pago, en el seguimiento.
 * null cuando el pedido no usa pago por adelantado (hamburguesa, o un
 * backend viejo): ahí la vista queda exactamente como era antes.
 */
export function avisoPagoAdelanto(pedido: PedidoPublicoConsultaItem): AvisoPago | null {
  const estado: EstadoPagoAdelanto = pedido.estadoPagoAdelanto ?? "NO_APLICA";
  if (estado === "NO_APLICA") return null;

  if (estado === "VERIFICANDO") {
    // Con código de operación = pedido viejo del flujo de Yape, esperando que
    // una persona lo revise. Sin código = pedido actual, esperando que el
    // cliente pague con tarjeta.
    return pedido.codigoOperacionYape
      ? { texto: "Estamos verificando tu pago con la tienda.", tono: "espera" }
      : { texto: "Falta pagar tu pedido con tarjeta para confirmarlo.", tono: "atencion" };
  }
  if (estado === "PAGADO") {
    return { texto: "Pago confirmado. ¡Ya lo estamos preparando!", tono: "bien" };
  }

  const ajuste = pedido.ajustePago ?? null;
  if (estado === "DEUDA_PARCIAL") {
    return {
      texto: textoAjuste(ajuste, "DEUDA"),
      tono: "atencion",
    };
  }
  return { texto: textoAjuste(ajuste, "VUELTO"), tono: "atencion" };
}

/**
 * "Tu pedido está separado: aún debes S/ 2.00, los pagas al recoger" / "Te
 * debemos S/ 3.00 de vuelto, te lo damos al recoger".
 *
 * La DEUDA ya no se cuenta como "pagaste de menos": desde el pago parcial es
 * el camino normal de quien eligió separar su pedido con la mitad, no un
 * error que haya que señalar. El VUELTO sí sigue siendo un caso raro del
 * flujo viejo de Yape (con Culqi el servidor topa en el total).
 *
 * `ajuste` puede llegar null aunque el estado diga que hubo diferencia: eso
 * pasa cuando la tienda YA resolvió el saldo/vuelto (el backend solo manda
 * los pendientes). En ese caso se dice justamente eso, en vez de un monto
 * inventado.
 */
export function textoAjuste(
  ajuste: AjustePagoPublico | null,
  tipoEsperado: "DEUDA" | "VUELTO",
): string {
  if (!ajuste || ajuste.estado !== "PENDIENTE") {
    return tipoEsperado === "DEUDA"
      ? "Tu saldo pendiente ya quedó cobrado."
      : "Tu vuelto ya quedó devuelto.";
  }
  return ajuste.tipo === "DEUDA"
    ? `Tu pedido está separado: aún debes S/ ${ajuste.monto.toFixed(2)}. Los pagas al recoger.`
    : `Pagaste de más: te debemos S/ ${ajuste.monto.toFixed(2)} de vuelto. Te lo damos al recoger.`;
}
