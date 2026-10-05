/**
 * Delivery a domicilio del pedido web de PANADERÍA (pan de agua / pan
 * francés, por unidad). El pan de hamburguesa (por paquete) no entra: sigue
 * siendo solo para recoger en tienda.
 *
 * Pedido del dueño (2026-10-05): pin en el mapa + dirección escrita + una
 * referencia. El GPS de una laptop puede errar por cuadras, así que el pin
 * solo no alcanza: lo que de verdad usa el repartidor es la dirección
 * escrita, y el pin sirve para decidir si la casa cae dentro de la zona.
 *
 * Todo lo de acá es puro y se prueba sin levantar nada. El SERVIDOR es la
 * autoridad: él decide el costo real del envío, el centro y el radio de la
 * zona (`backend_server/utils/delivery.js`, editables desde la app). Esta
 * copia existe solo para que el cliente vea el problema ANTES de enviar y
 * para pintar un estimado honesto mientras el servidor no confirmó nada.
 */

export type TipoEntrega = "RECOJO" | "DELIVERY";

export interface Coordenadas {
  latitud: number;
  longitud: number;
}

/**
 * ESTIMADO del costo de envío, en soles, para mostrar en el "Total estimado"
 * antes de que el pedido exista. El monto REAL lo decide el servidor al crear
 * el pedido (`COSTO_DELIVERY_PANADERIA` en Configuraciones, hoy S/ 4) y
 * vuelve en la respuesta como `costoEnvio`: desde ahí, lo que se muestra es
 * ese número y no este. Si el dueño cambia el precio desde la app, esto queda
 * desactualizado hasta que alguien lo corrija acá — por eso en pantalla
 * siempre se dice "aprox." mientras se usa este valor.
 */
export const COSTO_ENVIO_ESTIMADO = 4;

/**
 * Dónde abre el mapa cuando el cliente todavía no marcó nada: la ciudad de
 * Pisco (~Plaza de Armas), el MISMO centro por defecto que usa el backend
 * para la zona de reparto. No son las coordenadas de la panadería — el
 * dueño todavía no las pasó — y no hace falta que lo sean: es solo el
 * encuadre inicial, el pin lo pone el cliente.
 */
export const CENTRO_MAPA_POR_DEFECTO: Coordenadas = { latitud: -13.7103, longitud: -76.2054 };

/** Zoom para ver la ciudad entera y ubicarse (sin pin todavía). */
export const ZOOM_INICIAL_MAPA = 14;
/** Zoom "de cuadra": al que se acerca el mapa cuando ya hay un pin. */
export const ZOOM_CON_PIN = 17;

/**
 * Largos de los campos escritos. El backend guarda dirección + referencia en
 * UNA columna VARCHAR(300) y exige al menos 8 caracteres (ver
 * `LARGO_MINIMO_DIRECCION`/`LARGO_MAXIMO_DIRECCION` en delivery.js). Los
 * topes de acá están pensados para que la suma de los dos campos más el
 * separador NUNCA pase de 300, así el servidor no rechaza algo que el
 * formulario dejó escribir: 180 + 100 + 15 = 295.
 */
export const LARGO_MINIMO_DIRECCION = 8;
export const LARGO_MAXIMO_DIRECCION = 180;
export const LARGO_MAXIMO_REFERENCIA = 100;

/** Cómo se pegan dirección y referencia en el único campo del backend. Es
 * texto que después lee una persona (el repartidor, la app), así que tiene
 * que ser legible a simple vista. */
const SEPARADOR_REFERENCIA = " — Referencia: ";

/** Espacios colapsados y sin bordes — misma limpieza que `normalizarDireccion`
 * en el backend, para que lo que el cliente ve coincida con lo que se guarda. */
export function normalizarTexto(valor: string): string {
  return valor.replace(/\s+/g, " ").trim();
}

/**
 * El único string que viaja como `direccionEntrega`:
 * `"Calle Ayacucho 475 — Referencia: casa celeste, al lado de la bodega"`.
 * Sin referencia (no debería pasar: el formulario la exige), va la dirección
 * sola, sin el separador colgando.
 */
export function armarDireccionEntrega(direccion: string, referencia: string): string {
  const direccionLimpia = normalizarTexto(direccion);
  const referenciaLimpia = normalizarTexto(referencia);
  if (!referenciaLimpia) return direccionLimpia;
  return `${direccionLimpia}${SEPARADOR_REFERENCIA}${referenciaLimpia}`;
}

/** Lat/lon con forma de coordenada real del planeta. */
export function coordenadasValidas(coordenadas: Coordenadas | null | undefined): coordenadas is Coordenadas {
  if (!coordenadas) return false;
  const { latitud, longitud } = coordenadas;
  if (!Number.isFinite(latitud) || !Number.isFinite(longitud)) return false;
  return latitud >= -90 && latitud <= 90 && longitud >= -180 && longitud <= 180;
}

/**
 * La misma revisión que hace el servidor sobre los datos del delivery, para
 * que el cliente vea qué le falta antes de enviar. Devuelve el mensaje listo
 * para mostrar, o null si está todo bien. El orden es el del formulario
 * (mapa → dirección → referencia): el primer problema que se encuentra es el
 * campo más arriba, así el cliente no tiene que buscar.
 *
 * La referencia es OBLIGATORIA, a pedido del dueño: el pin puede errar y la
 * dirección a mano no siempre alcanza en Pisco ("cuadra 4" no dice qué
 * puerta). "Casa celeste, al lado de la bodega" es lo que de verdad
 * encuentra al cliente.
 */
export function revisarDatosDelivery({
  coordenadas,
  direccion,
  referencia,
}: {
  coordenadas: Coordenadas | null;
  direccion: string;
  referencia: string;
}): string | null {
  if (!coordenadasValidas(coordenadas)) {
    return "Marca en el mapa el lugar exacto de entrega.";
  }
  const direccionLimpia = normalizarTexto(direccion);
  if (direccionLimpia.length === 0) {
    return "Escribe tu dirección para el delivery.";
  }
  if (direccionLimpia.length < LARGO_MINIMO_DIRECCION) {
    return "Escribe tu dirección completa (calle y número, o manzana y lote).";
  }
  if (normalizarTexto(referencia).length === 0) {
    return "Agrega una referencia para que el repartidor te encuentre (ej. casa celeste, al lado de la bodega).";
  }
  return null;
}

/**
 * ¿El cuerpo de un 400 del backend dice que el pin cayó FUERA de la zona de
 * reparto? Es el único rechazo del delivery que tiene salida sin corregir
 * nada: pedir igual para recoger en tienda. Un 400 por dato faltante
 * (`fueraDeZona: false`) o cualquier otro error se muestra como texto
 * común, sin ofrecer ese atajo — ahí lo que corresponde es corregir el
 * campo. Recibe `err.datos` (ver `ApiError`), igual que `rangoDesdeRespuesta`
 * en utils/pagoAdelanto.
 */
export function esRechazoPorZona(datos: unknown): boolean {
  if (!datos || typeof datos !== "object") return false;
  return (datos as { fueraDeZona?: unknown }).fueraDeZona === true;
}

/**
 * Códigos de `GeolocationPositionError`, escritos acá para no depender de la
 * constante global en las pruebas (en Node no existe `GeolocationPositionError`).
 */
export const GEO_PERMISO_DENEGADO = 1;
export const GEO_POSICION_NO_DISPONIBLE = 2;
export const GEO_TIEMPO_AGOTADO = 3;

/**
 * Qué decirle al cliente cuando "Usar mi ubicación actual" no pudo. Siempre
 * cierra con la salida que SÍ tiene: mover el pin a mano, que nunca deja de
 * funcionar. `null` = el navegador no ofrece geolocalización (o la página no
 * está en HTTPS, donde los navegadores la apagan).
 */
export function textoErrorGeolocalizacion(codigo: number | null): string {
  const salida = "Puedes marcar tu casa moviendo el pin en el mapa.";
  switch (codigo) {
    case GEO_PERMISO_DENEGADO:
      return `No nos diste permiso para ver tu ubicación. ${salida}`;
    case GEO_POSICION_NO_DISPONIBLE:
      return `Tu dispositivo no pudo calcular dónde estás. ${salida}`;
    case GEO_TIEMPO_AGOTADO:
      return `Tardó demasiado en encontrar tu ubicación. Intenta de nuevo o ${salida.charAt(0).toLowerCase()}${salida.slice(1)}`;
    default:
      return `Tu navegador no permite usar la ubicación acá. ${salida}`;
  }
}

/**
 * Aviso de precisión tras ubicar al cliente. El GPS de un celular suele
 * acertar a 5–30 m; una laptop por Wi-Fi/IP puede errar por cuadras enteras.
 * A partir de 100 m vale la pena decirlo para que REVISE el pin en vez de
 * confiar ciego. Por debajo no se dice nada: no hay problema que avisar.
 */
export function textoPrecisionUbicacion(precisionMetros: number): string | null {
  if (!Number.isFinite(precisionMetros) || precisionMetros < 100) return null;
  const redondeada = precisionMetros >= 1000 ? `${(precisionMetros / 1000).toFixed(1)} km` : `${Math.round(precisionMetros)} m`;
  return `Tu ubicación puede tener un error de hasta ${redondeada}. Revisa que el pin esté sobre tu casa y arrástralo si hace falta.`;
}

/**
 * Total con el envío sumado, en céntimos enteros para que 48.10 + 4 dé 52.10
 * exacto y no 52.099999 (misma razón que `aCentimos` en pagoAdelanto). Un
 * envío no numérico o negativo cuenta como 0: nunca se le cobra de más al
 * cliente por un dato roto.
 */
export function totalConEnvio(total: number, costoEnvio: number): number {
  const envio = Number.isFinite(costoEnvio) && costoEnvio > 0 ? costoEnvio : 0;
  return Number(((Math.round(total * 100) + Math.round(envio * 100)) / 100).toFixed(2));
}

/** Lo que se le muestra al cliente como nombre de cada forma de entrega —
 * en el formulario, la confirmación y el seguimiento. */
export function etiquetaTipoEntrega(tipo: TipoEntrega): string {
  return tipo === "DELIVERY" ? "Delivery a domicilio" : "Recojo en tienda";
}
