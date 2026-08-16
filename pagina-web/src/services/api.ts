// Cliente delgado para las dos únicas rutas públicas del backend (sin
// login) — ver backend_server/controllers/publicoController.js.

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
