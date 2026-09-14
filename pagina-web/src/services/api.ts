// Cliente delgado para el backend: las rutas públicas (sin login, ver
// publicoController.js) para catálogo y creación de pedidos desde la web.

const API_BASE_URL =
  (import.meta.env.VITE_API_BASE_URL as string | undefined) ||
  "https://panaderia-backend-qy3y.onrender.com/api";

export class ApiError extends Error {
  errores?: string[];
  /** Clasificación del backend cuando la hay ('INVALIDO', 'EXPIRADO',
   * 'MAX_INTENTOS'…, ver OtpError en el backend). El mensaje ya viene
   * redactado para mostrarse tal cual; esto sirve para decidir la FORMA de
   * mostrarlo (ej. un callejón sin salida en vez de un error del campo). */
  tipo?: string;
  constructor(mensaje: string, errores?: string[], tipo?: string) {
    super(mensaje);
    this.errores = errores;
    this.tipo = tipo;
  }
}

export interface ProductoPublico {
  idProducto: number;
  nombre: string;
  precioUnitario: number;
  /** true: se vende por paquete de 12 a precio fijo (pan de hamburguesa),
   * no por unidad suelta como el resto del catálogo. */
  esPaquete: boolean;
  /** Slug de la tienda dueña del producto ("panaderia", "hamburguesas").
   * Se usa para preguntarle al backend si hay descuento por fidelidad en
   * esa tienda: la lista de tiendas con descuento la decide el dueño desde
   * la app, así que no se puede deducir de `esPaquete`. Puede faltar si el
   * backend todavía no está actualizado. */
  tiendaSlug?: string;
}

/** Horario de pedido/recojo del pan vendido por unidad (Pan de Agua/
 * Francés) — editable desde la app (ADMIN/SUPERADMIN de Panadería), nunca
 * hardcodeado acá. Todas las horas vienen en formato "HH:mm", hora de
 * Perú. No aplica al pan de hamburguesa (esPaquete). */
export interface HorariosPanaderia {
  horaLimitePedido: string;
  horaRecojoMismoDia: string;
  horaRecojoDiaSiguiente: string;
  minutosTolerancia: number;
  /** Hora tope para recoger un pedido el mismo día — después de esta hora
   * ya no se ofrece el mismo día, sin importar la tolerancia. */
  horaTopeRecojo: string;
  /** Horario general de atención de la tienda — rige el recojo de
   * CUALQUIER día (hoy o una fecha futura), no solo el mismo día. Ninguna
   * hora de recojo puede caer fuera de [horaApertura, horaCierre]. */
  horaApertura: string;
  horaCierre: string;
  /** Puramente informativos (alimentan el aviso de "fuera de ventana"),
   * no bloquean nada por sí mismos — ver franjaAjustada() en
   * utils/horariosPan.ts para el bloqueo real. */
  horaInicioPedidoTarde: string;
  domingoHoraLimitePedido: string;
  /** Interruptores manuales: si el dueño se queda sin stock de una
   * hornada, apaga la franja correspondiente desde la app y los pedidos
   * nuevos saltan directo a la otra franja. */
  franjaMananaActiva: boolean;
  franjaTardeActiva: boolean;
}

export interface CatalogoPublicoResultado {
  productos: ProductoPublico[];
  horarios: HorariosPanaderia;
}

export interface PedidoPublicoInput {
  /** DNI (8 dígitos) o RUC (11 dígitos) — el backend distingue por el
   * largo, mismo criterio que el registro manual de clientes en la app. */
  documento: string;
  /** Se omite cuando el documento ya tiene celular guardado y el cliente no
   * lo cambió: el backend reutiliza el que ya está en Personas. Nunca se
   * manda la máscara (`9*****321`), solo un número nuevo y completo. */
  telefono?: string;
  /** Opcional siempre. Se manda solo cuando es un correo nuevo o uno que el
   * cliente eligió reemplazar (y el anterior no estaba verificado). */
  email?: string;
  /** El backend acepta un carrito (`items`) desde que se agregó soporte a
   * pedidos con varios productos — este formulario público solo arma UNO,
   * pero igual hay que mandarlo envuelto en el array o el backend lo
   * rechaza con "El pedido debe tener al menos un producto". */
  items: { idProducto: number; cantidad: number }[];
  notas?: string;
  /** "YYYY-MM-DDTHH:mm" en hora de Perú (sin zona horaria) — obligatorio
   * solo para productos que no sean paquete (Pan de Agua/Francés); el
   * backend vuelve a validar el rango horario permitido, nunca confía en
   * lo que mande el cliente. */
  fechaEntrega?: string;
}

/** Descuento por fidelidad que el backend calculó para un cliente en una
 * tienda concreta, a partir de su segmento del CRM (ver
 * utils/descuentosCliente.js). `porcentaje` viene en forma decimal-porciento
 * (5 = 5%). Siempre null cuando la tienda no tiene el descuento habilitado. */
export interface DescuentoCliente {
  segmento: "NUEVO" | "EN_RIESGO" | "REGULAR" | "FRECUENTE" | "VIP";
  porcentaje: number;
}

/** Estado del pago por adelantado con Yape de un pedido (solo Panadería;
 * en cualquier otro pedido vale "NO_APLICA"). Los mismos 5 valores que
 * acepta `CK_Pedidos_EstadoPagoAdelanto` en la base — ver
 * backend_server/utils/pagoAdelanto.js. */
export type EstadoPagoAdelanto =
  | "NO_APLICA"
  | "VERIFICANDO"
  | "PAGADO"
  | "DEUDA_PARCIAL"
  | "VUELTO_PENDIENTE";

/** Saldo o vuelto que quedó pendiente después de que la tienda verificó el
 * pago. `monto` SIEMPRE es positivo: quién le debe a quién lo dice `tipo`. */
export interface AjustePagoPublico {
  tipo: "DEUDA" | "VUELTO";
  monto: number;
  estado: "PENDIENTE" | "RESUELTO";
}

export interface PedidoPublicoResultado {
  mensaje: string;
  /** El pedido YA existe con este id apenas se envía el formulario, incluso
   * en Panadería, donde todavía falta pagar — así una pestaña que se muera
   * mientras el cliente está en Yape no pierde nada (ver
   * `registrarCodigoPago`). Puede faltar con un backend viejo. */
  idPedido?: number;
  numeroPedidoDia: number;
  /** Lo que el cliente realmente paga: YA con el descuento aplicado. */
  total: number;
  /** Antes del descuento. Puede faltar si el backend todavía no está
   * actualizado — en ese caso no hay desglose que mostrar. */
  subtotal?: number;
  /** El descuento que el SERVIDOR aplicó de verdad al guardar el pedido, no
   * el que la web había estimado. null cuando no hubo. */
  descuentoCliente?: DescuentoCliente | null;
  /** "VERIFICANDO" en Panadería (falta pagar), "NO_APLICA" en el resto. */
  estadoPagoAdelanto?: EstadoPagoAdelanto;
  /** Lo único de la respuesta que no se le muestra al cliente: sirve para
   * mandar después el código de operación sin tener login. null/ausente
   * cuando el pedido no se paga por adelantado. */
  tokenConfirmacionPago?: string | null;
}

/** A dónde yapear: el medio de pago activo de una tienda. `null` cuando el
 * dueño todavía no cargó ninguno (ver `MediosPagoTienda`) — la pantalla de
 * pago tiene un estado propio para eso, no muestra una caja vacía. */
export interface MedioPagoPublico {
  tipo: string;
  titular: string;
  numeroDestino: string;
  notas: string | null;
  /** PNG en base64 del QR REAL descargado de la app de Yape, sin el prefijo
   * `data:`. null si el dueño no lo subió: ahí solo se muestra el número. */
  imagenQrBase64: string | null;
}

export async function obtenerMedioPagoPublico(tiendaSlug: string): Promise<MedioPagoPublico | null> {
  const respuesta = await fetch(
    `${API_BASE_URL}/publico/medio-pago?tiendaSlug=${encodeURIComponent(tiendaSlug)}`,
  );
  const data = await manejarRespuesta<{ medioPago: MedioPagoPublico | null }>(respuesta);
  return data.medioPago ?? null;
}

export interface RegistrarCodigoPagoInput {
  idPedido: number;
  /** El que devolvió `crearPedidoPublico`. Se omite cuando se llega desde el
   * seguimiento por DNI en otro dispositivo, donde no hay token guardado. */
  token?: string;
  /** Alternativa al token: el mismo documento con el que se hizo el pedido. */
  documento?: string;
  /** Solo dígitos, tal como lo emitió Yape. */
  codigoOperacionYape: string;
  /** Cuánto dice el cliente haber pagado. El servidor exige que sea >= total. */
  montoDeclaradoCliente: number;
}

export interface RegistrarCodigoPagoResultado {
  mensaje: string;
  idPedido: number;
  numeroPedidoDia: number;
  estadoPagoAdelanto: EstadoPagoAdelanto;
  codigoOperacionYape: string;
  montoDeclaradoCliente: number;
  total: number;
}

/** Segundo paso del pedido de Panadería: el cliente ya yapeó y manda el
 * código de operación. El pedido ya existe desde `crearPedidoPublico`; esto
 * solo le agrega el código y el monto, y lo deja esperando que la tienda lo
 * verifique. Se puede hacer UNA sola vez por pedido. */
export async function registrarCodigoPago(
  input: RegistrarCodigoPagoInput,
): Promise<RegistrarCodigoPagoResultado> {
  const { idPedido, ...cuerpo } = input;
  const respuesta = await fetch(`${API_BASE_URL}/publico/pedidos/${idPedido}/codigo-pago`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(cuerpo),
  });
  return manejarRespuesta<RegistrarCodigoPagoResultado>(respuesta);
}

async function manejarRespuesta<T>(respuesta: Response): Promise<T> {
  let data: Record<string, unknown> = {};
  try {
    data = await respuesta.json();
  } catch {
    // Sin cuerpo JSON — se maneja como error genérico abajo.
  }
  if (!respuesta.ok) {
    const mensaje = (data.mensaje as string) || "Ocurrió un error inesperado.";
    throw new ApiError(mensaje, data.errores as string[] | undefined, data.tipo as string | undefined);
  }
  return data as T;
}

export async function obtenerCatalogoPublico(): Promise<CatalogoPublicoResultado> {
  const respuesta = await fetch(`${API_BASE_URL}/publico/catalogo`);
  return manejarRespuesta<CatalogoPublicoResultado>(respuesta);
}

export async function crearPedidoPublico(
  input: PedidoPublicoInput,
): Promise<PedidoPublicoResultado> {
  const respuesta = await fetch(`${API_BASE_URL}/publico/pedidos`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(input),
  });
  return manejarRespuesta<PedidoPublicoResultado>(respuesta);
}

/** Los pedidos recientes (últimos 20) del cliente, en cualquier estado —
 * la página los vuelve a pedir sola cada cierto tiempo mientras el panel
 * queda abierto, para que el estado se vea actualizado sin recargar. */
export interface PedidoPublicoConsultaItem {
  idPedido: number;
  numeroPedidoDia: number;
  tienda: string | null;
  /** Cada línea del carrito (acá siempre habrá una sola, este formulario
   * no arma pedidos de varios productos, pero el backend siempre manda un
   * array desde que se agregó soporte a pedidos con varios productos). */
  items: { producto: string; cantidad: number; precioUnitario: number; subtotal: number }[];
  /** "Pan francés x50" — ya armado por el backend a partir de `items`,
   * conveniencia para no reconstruirlo acá. */
  productoResumen: string;
  total: number;
  /** "CONFIRMADO" es el estado nuevo de un pedido de Panadería cuyo pago por
   * adelantado ya fue verificado por la tienda: está listo para recogerse,
   * igual que un "PENDIENTE", solo que llegó por el otro camino. */
  estado: "SOLICITADO" | "PENDIENTE" | "CONFIRMADO" | "RECHAZADO" | "ENTREGADO" | "CANCELADO";
  fechaCreacion: string;
  /** null en pedidos de pan de hamburguesa (por paquete), que no usan el
   * flujo de recojo con fecha/hora — solo lo tienen los de pan por unidad. */
  fechaEntrega: string | null;
  /** "NO_APLICA" en todo pedido que no sea de Panadería por la web. Puede
   * faltar con un backend viejo — se trata como "NO_APLICA". */
  estadoPagoAdelanto?: EstadoPagoAdelanto;
  /** null mientras el cliente no haya mandado su código de operación: es lo
   * que distingue "pedido creado, falta pagar" de "pagado, esperando que la
   * tienda lo revise". */
  codigoOperacionYape?: string | null;
  montoDeclaradoCliente?: number | null;
  /** Saldo o vuelto todavía sin resolver de ESTE pedido, si quedó alguno al
   * verificar el pago. null (lo normal) cuando no hay nada pendiente. */
  ajustePago?: AjustePagoPublico | null;
}

export interface PedidoPublicoConsultaResultado {
  nombre: string | null;
  pedidos: PedidoPublicoConsultaItem[];
}

export async function consultarPedidosPublicos(dni: string): Promise<PedidoPublicoConsultaResultado> {
  const respuesta = await fetch(`${API_BASE_URL}/publico/pedidos?dni=${encodeURIComponent(dni)}`);
  return manejarRespuesta<PedidoPublicoConsultaResultado>(respuesta);
}

/** Estado de UN canal de contacto (correo o celular) de un documento que ya
 * está registrado. El valor real NUNCA viaja hasta acá: solo su máscara
 * (`j***@gmail.com`, `9*****321`), porque el DNI en Perú no es un secreto
 * fuerte y este endpoint es público — ver utils/enmascarar.js en el backend. */
export interface EstadoContacto {
  /** Ya tenemos algo guardado para este canal. */
  enArchivo: boolean;
  /** Verificado con código dentro de la app: desde la web NO se puede
   * cambiar (el backend ignora cualquier valor nuevo para este canal). */
  verificado: boolean;
  /** null siempre que `enArchivo` sea false. */
  mascara: string | null;
}

export interface ContactoDocumento {
  email: EstadoContacto;
  telefono: EstadoContacto;
}

export interface VerificarDocumentoResultado {
  existe: boolean;
  /** Qué datos de contacto ya tenemos de este documento. Puede faltar si el
   * backend todavía no está actualizado — el hook lo trata como "nada
   * guardado", que es el comportamiento de siempre. */
  contacto?: ContactoDocumento;
  /** Descuento por fidelidad de ESTE documento en la tienda que se pasó por
   * `tiendaSlug`. null (o ausente) cuando no se pidió tienda, cuando esa
   * tienda no tiene el descuento habilitado, o con un backend viejo.
   *
   * Es solo para mostrárselo al cliente antes de enviar: el monto que se
   * cobra lo vuelve a calcular el servidor al crear el pedido. */
  descuentoCliente?: DescuentoCliente | null;
  /** Presente solo cuando existe:false, ya explica el motivo (RENIEC/SUNAT
   * no lo tienen registrado). */
  mensaje?: string;
}

/** `tiendaSlug` es opcional: sin él el backend responde igual que siempre,
 * solo que sin `descuentoCliente`. Se manda en cuanto el visitante ya eligió
 * un pan, que es cuando se sabe de qué tienda estamos hablando. */
export async function verificarDocumentoPublico(
  documento: string,
  tiendaSlug?: string,
): Promise<VerificarDocumentoResultado> {
  const parametros = new URLSearchParams({ documento });
  if (tiendaSlug) parametros.set("tiendaSlug", tiendaSlug);
  const respuesta = await fetch(`${API_BASE_URL}/publico/verificar-documento?${parametros.toString()}`);
  return manejarRespuesta<VerificarDocumentoResultado>(respuesta);
}

/** Portal donde el cliente de verdad inicia sesión: la app Flutter
 * compilada para web, en su propio subdominio. Es un sitio SEPARADO de
 * este, sin sesión compartida — por eso la activación termina ofreciendo
 * el enlace, no "entrando" sola. */
export const URL_PORTAL_APP = "https://app.panaderiaronceros.com";

export interface ActivarCuentaInput {
  /** Viene del parámetro `p` del enlace del correo. */
  idPersona: number;
  /** Viene del parámetro `t`: token largo aleatorio, de un solo uso. */
  token: string;
  passwordNueva: string;
}

/** Cierra el flujo que arrancó con el pedido: define la contraseña y deja
 * la cuenta activada. No devuelve sesión ni token — esta página no tiene
 * dónde usarlos (ver URL_PORTAL_APP). */
export async function activarCuenta(input: ActivarCuentaInput): Promise<{ mensaje: string }> {
  const respuesta = await fetch(`${API_BASE_URL}/auth/activar-cuenta`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(input),
  });
  return manejarRespuesta<{ mensaje: string }>(respuesta);
}
