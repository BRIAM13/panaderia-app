import type { UsuarioSesion } from "./api";

// Guarda la sesión en localStorage, nada más — esta página es liviana a
// propósito (sin refresh automático de token ni Context global). Si el
// accessToken vence (1 hora), CuentaPage simplemente pide loguearse de
// nuevo, igual que cualquier sesión vencida.
const CLAVE_ACCESS_TOKEN = "ronceros_access_token";
const CLAVE_USUARIO = "ronceros_usuario";

export function guardarSesion(accessToken: string, usuario: UsuarioSesion) {
  localStorage.setItem(CLAVE_ACCESS_TOKEN, accessToken);
  localStorage.setItem(CLAVE_USUARIO, JSON.stringify(usuario));
}

export function obtenerAccessToken(): string | null {
  return localStorage.getItem(CLAVE_ACCESS_TOKEN);
}

export function obtenerUsuarioGuardado(): UsuarioSesion | null {
  const crudo = localStorage.getItem(CLAVE_USUARIO);
  if (!crudo) return null;
  try {
    return JSON.parse(crudo) as UsuarioSesion;
  } catch {
    return null;
  }
}

export function cerrarSesion() {
  localStorage.removeItem(CLAVE_ACCESS_TOKEN);
  localStorage.removeItem(CLAVE_USUARIO);
}
