// Cliente delgado para el backend: las rutas públicas (sin login, ver
// publicoController.js) y las de cuenta de cliente (login + mis pedidos,
// las mismas que ya usa la app móvil).

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

export interface PedidoPublicoInput {
  dni: string;
  telefono: string;
  idProducto: number;
  cantidad: number;
  notas?: string;
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

export async function obtenerCatalogoPublico(): Promise<ProductoPublico[]> {
  const respuesta = await fetch(`${API_BASE_URL}/publico/catalogo`);
  const data = await manejarRespuesta<{ productos: ProductoPublico[] }>(respuesta);
  return data.productos;
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

export interface UsuarioSesion {
  idUsuario: number;
  idPersona: number;
  nombreUsuario: string;
  rol: string;
  requiereCambioPassword: boolean;
  nombres: string | null;
  apellidoPaterno: string | null;
  apellidoMaterno: string | null;
}

export interface LoginResultado {
  accessToken: string;
  refreshToken: string;
  usuario: UsuarioSesion;
}

/** Mismo login que usa la app móvil (POST /auth/login) — el usuario es el
 * DNI para cualquier cuenta creada desde un pedido web (ver
 * publicoController.js), con la contraseña por defecto también el DNI. */
export async function login(nombreUsuario: string, password: string): Promise<LoginResultado> {
  const respuesta = await fetch(`${API_BASE_URL}/auth/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ nombreUsuario, password }),
  });
  return manejarRespuesta<LoginResultado>(respuesta);
}

export async function cambiarPasswordPrimerIngreso(
  accessToken: string,
  passwordNueva: string,
): Promise<void> {
  const respuesta = await fetch(`${API_BASE_URL}/auth/cambiar-password`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({ passwordNueva }),
  });
  await manejarRespuesta(respuesta);
}

export interface PedidoClienteResumen {
  dni: string | null;
  nombres: string;
  apellidoPaterno: string;
  apellidoMaterno: string | null;
  descripcionNegocio: string | null;
}

/** Un pedido propio, tal como lo devuelve GET /pedidos/mis-pedidos — ya
 * excluye rechazados/cancelados, e incluye pedidos de cualquier tienda
 * (Hamburguesas, Panadería, etc.), no solo una. */
export interface PedidoCliente {
  idPedido: number;
  numeroPedidoDia: number;
  tienda: string | null;
  producto: string;
  tipoPedido: string;
  cantidad: number;
  precioUnitario: number;
  total: number;
  fechaEntrega: string | null;
  estado: string;
  estadoPago: string | null;
  fechaEntregaReal: string | null;
  notas: string | null;
  fechaCreacion: string;
  cliente: PedidoClienteResumen;
}

export async function obtenerMisPedidos(accessToken: string): Promise<PedidoCliente[]> {
  const respuesta = await fetch(`${API_BASE_URL}/pedidos/mis-pedidos`, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  const data = await manejarRespuesta<{ pedidos: PedidoCliente[] }>(respuesta);
  return data.pedidos;
}
