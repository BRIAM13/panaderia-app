import type { DescuentoCliente } from "../services/api";

/** Cómo se le nombra cada segmento del CRM al propio cliente. Los nombres
 * internos ("EN_RIESGO", "REGULAR") son etiquetas de gestión y algunas
 * suenan mal si se le dicen en la cara a quien está comprando: nadie quiere
 * leer "eres un cliente en riesgo" en su propio total. Acá se traducen a
 * algo que se pueda mostrar sin explicaciones. */
const ETIQUETA_SEGMENTO: Record<DescuentoCliente["segmento"], string> = {
  NUEVO: "cliente nuevo",
  EN_RIESGO: "cliente que vuelve",
  REGULAR: "cliente frecuente",
  FRECUENTE: "cliente frecuente",
  VIP: "cliente VIP",
};

export function etiquetaSegmento(segmento: DescuentoCliente["segmento"]): string {
  return ETIQUETA_SEGMENTO[segmento] ?? "cliente";
}

/** "Descuento cliente VIP (15%)" — la línea que se muestra en el desglose
 * del total, ya lista para pintar. */
export function textoDescuento(descuento: DescuentoCliente): string {
  return `Descuento ${etiquetaSegmento(descuento.segmento)} (${formatearPorcentaje(descuento.porcentaje)}%)`;
}

/** 5 -> "5", 7.5 -> "7.5". El dueño puede configurar decimales, pero un "5"
 * no debe verse como "5.0". */
export function formatearPorcentaje(porcentaje: number): string {
  return Number.isInteger(porcentaje) ? String(porcentaje) : String(Number(porcentaje.toFixed(2)));
}

/** Cuánta plata se descuenta, redondeada a 2 decimales. */
export function montoDescontado(subtotal: number, porcentaje: number): number {
  if (!porcentaje || subtotal <= 0) return 0;
  return Number(((subtotal * porcentaje) / 100).toFixed(2));
}

/**
 * Total que el cliente va a pagar. MISMA fórmula que `aplicarDescuento` en
 * backend_server/utils/descuentosCliente.js (subtotal * (1 - %/100),
 * redondeado a 2 decimales), para que la cifra que se muestra acá coincida
 * exactamente con la que el servidor guarda al crear el pedido.
 *
 * El servidor sigue siendo la fuente de verdad: esto es solo el anticipo
 * honesto de lo que va a cobrar.
 */
export function totalConDescuento(subtotal: number, porcentaje: number): number {
  if (!porcentaje) return Number(subtotal.toFixed(2));
  return Number((subtotal * (1 - porcentaje / 100)).toFixed(2));
}

/**
 * ¿Hay que mostrar el descuento para lo que el visitante tiene elegido
 * ahora mismo? Solo si el backend devolvió uno con porcentaje real Y el
 * producto elegido es de la tienda por la que se consultó — si el visitante
 * cambia de pan (o de tienda) después de escribir su documento, el
 * descuento de la consulta anterior deja de aplicar hasta que se recalcule.
 */
export function descuentoVigente(
  descuento: DescuentoCliente | null | undefined,
  tiendaSlugConsultada: string | undefined,
  tiendaSlugProductoElegido: string | undefined,
): DescuentoCliente | null {
  if (!descuento || descuento.porcentaje <= 0) return null;
  if (!tiendaSlugConsultada || tiendaSlugConsultada !== tiendaSlugProductoElegido) return null;
  return descuento;
}
