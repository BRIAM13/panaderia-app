// Toda la información editable del sitio vive acá — para cambiar textos,
// productos, la misión/visión o los links de descarga NO hace falta tocar
// ningún componente.

export const SITE = {
  nombre: "Panadería Ronceros",
  nombreCorto: "Ronceros",
  claim: "Pan artesanal de siempre, hecho en familia",
  descripcion:
    "Panadería familiar en Pisco — el mismo pan de toda la vida, hecho a mano con recetas que pasan de generación en generación.",
};

export const HISTORIA = {
  parrafo1:
    "Somos un negocio familiar: el pan que hacemos hoy es la misma receta que se fue pasando de generación en generación en nuestra familia. No es una fórmula nueva ni un experimento — es lo que siempre hemos horneado, hecho como siempre se hizo.",
  parrafo2:
    "Cada mañana empezamos temprano para que el pan llegue caliente a la mesa de nuestros vecinos en Pisco, igual que lleva pasando por años.",
};

export const MISION_VISION = {
  mision:
    "Elaborar cada día pan artesanal de calidad, con las recetas que se transmiten en nuestra familia de generación en generación, llevando a la mesa de cada hogar en Pisco el sabor de siempre, con calidez y a un precio justo.",
  vision:
    "Ser la panadería de referencia en Pisco, reconocida por la calidad de nuestro pan artesanal y por mantener viva, generación tras generación, una tradición familiar que forma parte de la identidad de nuestra comunidad.",
};

export const UBICACION = {
  direccion: "Calle Ayacucho, cuadra 4",
  ciudad: "Pisco, Perú",
  referencia: "Frente a la gruta de la Virgen de Chapi",
  // Búsqueda genérica (sin coordenadas exactas) — abre Google Maps ya
  // centrado en la dirección de texto, sin necesitar una API key de mapas.
  mapaEmbedUrl:
    "https://www.google.com/maps?q=Calle+Ayacucho+cuadra+4,+Pisco,+Peru&output=embed",
  mapaUrl:
    "https://www.google.com/maps/search/?api=1&query=Calle+Ayacucho+cuadra+4,+Pisco,+Peru",
};

export interface ProductoMenu {
  /** Debe coincidir EXACTO con Productos.Nombre en la base de datos — así
   * se cruza con el catálogo real que trae GET /publico/catalogo (mismo
   * nombre = mismo producto, sin necesitar guardar el IdProducto acá). */
  nombreEnCatalogo: string;
  nombre: string;
  descripcion: string;
  /** Ruta dentro de /public, o null si todavía no tiene foto propia (se
   * muestra una tarjeta con ícono en su lugar). */
  imagen: string | null;
}

export const PRODUCTOS: ProductoMenu[] = [
  {
    nombreEnCatalogo: "Pan de Hamburguesa Clásico",
    nombre: "Pan de hamburguesa",
    descripcion: "Suave, dorado y recién horneado — el compañero perfecto para tu hamburguesa.",
    imagen: "/images/productos/pan-de-hamburguesa.jpg",
  },
  {
    nombreEnCatalogo: "Pan de Agua",
    nombre: "Pan de agua",
    descripcion: "El clásico de siempre: corteza crujiente y miga suave, tal como lo recuerdas.",
    imagen: "/images/productos/pan-de-agua.jpg",
  },
  {
    nombreEnCatalogo: "Pan Francés",
    nombre: "Pan francés",
    descripcion: "Corteza dorada y crocante por fuera, ligero por dentro.",
    imagen: "/images/productos/pan-frances.jpg",
  },
  {
    nombreEnCatalogo: "Pan de Yema",
    nombre: "Pan de yema",
    descripcion: "Suave y ligeramente dulce, con ese color dorado característico.",
    imagen: null,
  },
  {
    nombreEnCatalogo: "Pan de Maíz",
    nombre: "Pan de maíz",
    descripcion: "Textura rústica y un sabor único que lo distingue de los demás.",
    imagen: null,
  },
  {
    nombreEnCatalogo: "Pan Integral",
    nombre: "Pan integral",
    descripcion: "Hecho con harina integral, para quienes buscan una opción más natural.",
    imagen: null,
  },
  {
    nombreEnCatalogo: "Pan de Manteca",
    nombre: "Pan de manteca",
    descripcion: "Denso y sabroso, con esa textura característica que lo hace único.",
    imagen: null,
  },
  {
    nombreEnCatalogo: "Petipanes",
    nombre: "Petipanes",
    descripcion: "Panecillos pequeños y suaves, perfectos para acompañar cualquier comida.",
    imagen: null,
  },
];

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
    // Nombre fijo (no versionado): scripts/publicar_actualizacion.ps1
    // sobrescribe este mismo archivo en cada release, así que el botón de
    // la landing siempre sirve la versión más reciente sin tener que tocar
    // este archivo a mano cada vez.
    archivo: "/downloads/CorporacionRonceros-latest.apk",
    nombreArchivo: "CorporacionRonceros.apk",
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

