// Toda la información editable del sitio vive acá — para cambiar textos,
// links de descarga o features NO hace falta tocar ningún componente.

export const SITE = {
  nombre: "Corporación Ronceros",
  claim: "Panadería y Pastelería Briam",
  descripcion:
    "El sistema que gestiona pedidos, deudas y pagos del negocio — en el celular, la laptop o donde estés.",
};

export type OS = "android" | "ios" | "windows" | "macos" | "web";

export interface PlataformaDescarga {
  id: OS;
  nombre: string;
  estado: "disponible" | "en-camino" | "proximamente";
  descripcionEstado: string;
  /** Ruta pública del instalador/app, o null si todavía no hay nada. */
  archivo: string | null;
  /** Nombre visible del archivo a descargar (null si no aplica, ej. "abrir"). */
  nombreArchivo: string | null;
  /** true = además de la acción principal, se puede escanear un QR. */
  viaQr: boolean;
  /** "descargar" = botón de bajar un archivo; "abrir" = enlace directo (Web). */
  tipoAccion: "descargar" | "abrir";
}

// "archivo" acepta dos formas: una ruta relativa dentro de /public (Vite la
// sirve tal cual, resuelta contra el dominio donde se despliegue el sitio —
// ver PlatformCard.tsx), o una URL externa completa (ej. GitHub Releases,
// para binarios grandes que no conviene empaquetar en el propio deploy).
export const PLATAFORMAS: PlataformaDescarga[] = [
  {
    id: "android",
    nombre: "Android",
    estado: "disponible",
    descripcionEstado: "Instalador directo (.apk)",
    // NO se sirve desde GitHub Releases: el repo es privado, así que esos
    // links de descarga dan 404 a cualquier visitante sin sesión — se
    // vuelve a empaquetar directo en el propio deploy de Vercel, que es
    // público sin importar que el repo fuente sea privado.
    archivo: "/downloads/CorporacionRonceros-v1.0.0.apk",
    nombreArchivo: "CorporacionRonceros-v1.0.0.apk",
    viaQr: true,
    tipoAccion: "descargar",
  },
  {
    id: "windows",
    nombre: "Windows",
    estado: "en-camino",
    descripcionEstado: "Instalador (.exe) en preparación final",
    archivo: null,
    nombreArchivo: "CorporacionRonceros-Setup.exe",
    viaQr: false,
    tipoAccion: "descargar",
  },
  {
    id: "web",
    nombre: "Web",
    estado: "disponible",
    descripcionEstado: "Ábrela directo en tu navegador — sin instalar nada",
    archivo: "/app/",
    nombreArchivo: null,
    viaQr: true,
    tipoAccion: "abrir",
  },
  {
    id: "ios",
    nombre: "iOS",
    estado: "proximamente",
    descripcionEstado: "En revisión por Apple Developer Program",
    archivo: null,
    nombreArchivo: null,
    viaQr: true,
    tipoAccion: "descargar",
  },
  {
    id: "macos",
    nombre: "macOS",
    estado: "proximamente",
    descripcionEstado: "Compilación pendiente de licencia Apple",
    archivo: null,
    nombreArchivo: null,
    viaQr: false,
    tipoAccion: "descargar",
  },
];

export interface FeatureBento {
  id: string;
  titulo: string;
  descripcion: string;
  /** Controla cuántas columnas/filas ocupa en el bento grid desktop. */
  span: "col-2" | "row-2" | "col-2-row-2" | "normal";
  acento: "green" | "violet";
}

export const FEATURES: FeatureBento[] = [
  {
    id: "pedidos",
    titulo: "Pedidos en tiempo real",
    descripcion:
      "Cada pedido se registra al instante y viaja sincronizado entre el cliente y el personal, sin recargar nada.",
    span: "col-2-row-2",
    acento: "green",
  },
  {
    id: "roles",
    titulo: "Roles jerárquicos",
    descripcion:
      "Cliente, Trabajador, Administrador y Super Administrador — cada uno ve exactamente lo que le corresponde.",
    span: "normal",
    acento: "violet",
  },
  {
    id: "pagos",
    titulo: "Pagos con verificación real",
    descripcion:
      "QR real de Yape/Plin, más confirmación manual del personal antes de saldar cualquier deuda.",
    span: "normal",
    acento: "green",
  },
  {
    id: "notificaciones",
    titulo: "Notificaciones push",
    descripcion:
      "Avisos instantáneos cuando cambia el estado de un pedido o se reporta un pago, sin abrir la app.",
    span: "col-2",
    acento: "violet",
  },
  {
    id: "reniec",
    titulo: "Verificación RENIEC/SUNAT",
    descripcion:
      "El registro de clientes valida DNI y RUC contra fuentes oficiales en tiempo real, en vez de confiar a ciegas.",
    span: "normal",
    acento: "green",
  },
  {
    id: "multiplataforma",
    titulo: "Un solo sistema, todos tus dispositivos",
    descripcion:
      "Android, iOS, Windows, macOS y Web comparten la misma base — la misma cuenta, los mismos datos, siempre al día.",
    span: "normal",
    acento: "violet",
  },
];
