// Cliente delgado para el backend: las rutas públicas (sin login, ver
// publicoController.js) para catálogo y creación de pedidos desde la web.

const API_BASE_URL =
  (import.meta.env.VITE_API_BASE_URL as string | undefined) ||
  "https://panaderia-backend-2xvd.onrender.com/api";

export class ApiError extends Error {
  errores?: string[];
  constructor(mensaje: string, errores?: string[]) {
    super(mensaje);
    this.errores = errores;
  }
}

export interface ProductoPublico {
  idProducto: number;
  nombre: string;
  precioUnitario: number;
  /** true: se vende por paquete de 12 a precio fijo (pan de hamburguesa),
   * no por unidad suelta como el resto del catálogo. */
  esPaquete: boolean;
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
}

export interface CatalogoPublicoResultado {
  productos: ProductoPublico[];
  horarios: HorariosPanaderia;
}

export interface PedidoPublicoInput {
  /** DNI (8 dígitos) o RUC (11 dígitos) — el backend distingue por el
   * largo, mismo criterio que el registro manual de clientes en la app. */
  documento: string;
  telefono: string;
  idProducto: number;
  cantidad: number;
  notas?: string;
  /** "YYYY-MM-DDTHH:mm" en hora de Perú (sin zona horaria) — obligatorio
   * solo para productos que no sean paquete (Pan de Agua/Francés); el
   * backend vuelve a validar el rango horario permitido, nunca confía en
   * lo que mande el cliente. */
  fechaEntrega?: string;
}

export interface PedidoPublicoResultado {
  mensaje: string;
  numeroPedidoDia: number;
  total: number;
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
    throw new ApiError(mensaje, data.errores as string[] | undefined);
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
  producto: string;
  cantidad: number;
  total: number;
  estado: "SOLICITADO" | "PENDIENTE" | "RECHAZADO" | "ENTREGADO" | "CANCELADO";
  fechaCreacion: string;
  /** null en pedidos de pan de hamburguesa (por paquete), que no usan el
   * flujo de recojo con fecha/hora — solo lo tienen los de pan por unidad. */
  fechaEntrega: string | null;
}

export interface PedidoPublicoConsultaResultado {
  nombre: string | null;
  pedidos: PedidoPublicoConsultaItem[];
}

export async function consultarPedidosPublicos(dni: string): Promise<PedidoPublicoConsultaResultado> {
  const respuesta = await fetch(`${API_BASE_URL}/publico/pedidos?dni=${encodeURIComponent(dni)}`);
  return manejarRespuesta<PedidoPublicoConsultaResultado>(respuesta);
}

export interface VerificarDocumentoResultado {
  existe: boolean;
  /** Presente solo cuando existe:false, ya explica el motivo (RENIEC/SUNAT
   * no lo tienen registrado). */
  mensaje?: string;
}

export async function verificarDocumentoPublico(documento: string): Promise<VerificarDocumentoResultado> {
  const respuesta = await fetch(`${API_BASE_URL}/publico/verificar-documento?documento=${encodeURIComponent(documento)}`);
  return manejarRespuesta<VerificarDocumentoResultado>(respuesta);
}
