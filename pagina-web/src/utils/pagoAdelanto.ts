import type { AjustePagoPublico, EstadoPagoAdelanto, PedidoPublicoConsultaItem } from "../services/api";

/**
 * Pago por adelantado con Yape, lado del cliente (solo Panadería).
 *
 * Todo lo de acá es puro: son las mismas reglas que aplica el servidor
 * (`backend_server/utils/pagoAdelanto.js`), repetidas para que el visitante
 * vea el problema ANTES de enviar y no después de un viaje de ida y vuelta.
 * El servidor sigue siendo el que manda — nada de esto lo reemplaza.
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

/** ¿Este pedido todavía está esperando que el cliente mande su código?
 * Es lo que decide si el seguimiento por DNI le ofrece "Ingresar código de
 * pago" — la segunda vía para quien perdió el localStorage o está en otro
 * dispositivo. */
export function esperaCodigoDePago(pedido: PedidoPublicoConsultaItem): boolean {
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
    return pedido.codigoOperacionYape
      ? { texto: "Estamos verificando tu pago con la tienda.", tono: "espera" }
      : { texto: "Falta tu código de operación de Yape para confirmar el pedido.", tono: "atencion" };
  }
  if (estado === "PAGADO") {
    return { texto: "Pago verificado. ¡Ya lo estamos preparando!", tono: "bien" };
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
 * "Aún debes S/ 2.00, los completas al recoger" / "Te debemos S/ 3.00 de
 * vuelto, te lo damos al recoger".
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
    ? `Pagaste de menos: aún debes S/ ${ajuste.monto.toFixed(2)}. Los completas al recoger.`
    : `Pagaste de más: te debemos S/ ${ajuste.monto.toFixed(2)} de vuelto. Te lo damos al recoger.`;
}
