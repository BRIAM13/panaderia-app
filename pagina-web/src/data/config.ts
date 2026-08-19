// Toda la información editable del sitio vive acá — para cambiar textos,
// productos o la misión/visión NO hace falta tocar ningún componente.

export const SITE = {
  nombre: "Panadería Ronceros",
  nombreCorto: "Ronceros",
  claim: "Pan artesanal de siempre, hecho en familia",
  descripcion:
    "Somos una panadería familiar en Pisco y horneamos el mismo pan de toda la vida, hecho a mano con recetas que pasan de generación en generación.",
  // "Panadería Ronceros" es la marca de cara al cliente; el nombre
  // comercial formal y el RUC (persona natural) van solo en el pie de
  // página, por transparencia con el cliente.
  nombreComercial: "Panadería y Pastelería Briam",
  ruc: "10223034255",
};

export const HISTORIA = {
  parrafo1:
    "Somos un negocio familiar. El pan que hacemos hoy es la misma receta que se fue pasando de generación en generación dentro de nuestra familia, así que no encontrarás aquí ninguna fórmula nueva ni ningún experimento, sino lo que siempre hemos horneado y como siempre lo hicimos.",
  parrafo2:
    "Cada mañana empezamos temprano para que el pan llegue caliente a la mesa de nuestros vecinos en Pisco, tal como lleva sucediendo por años.",
};

export const MISION_VISION = {
  mision:
    "Elaborar cada día pan artesanal de calidad, con las recetas que se transmiten en nuestra familia de generación en generación, llevando a la mesa de cada hogar en Pisco el sabor de siempre, con calidez y a un precio justo.",
  vision:
    "Ser la panadería de referencia en Pisco, reconocida por la calidad de nuestro pan artesanal y por mantener viva, generación tras generación, una tradición familiar que forma parte de la identidad de nuestra comunidad.",
};

export const UBICACION = {
  // Dirección real del local, la que se muestra al visitante.
  direccion: "Calle Ayacucho, cuadra 4",
  ciudad: "Pisco, Perú",
  // El altar de la Virgen de Chapi está en la propia fachada del local —es
  // de la familia— y es la referencia más fácil de reconocer desde la
  // calle, mucho más que un número de puerta.
  referencia: "Busca el altar de la Virgen de Chapi en la fachada: es nuestro y te ayuda a encontrarnos fácil.",
  // Google Maps no ubica bien una dirección genérica tipo "cuadra 4", pero
  // sí encuentra correctamente el 475 (esa misma cuadra, a un paso del
  // altar) — se usa ese número solo para que el mapa abra en el lugar
  // correcto, aunque el texto que lee el cliente arriba no lo mencione.
  mapaEmbedUrl: "https://www.google.com/maps?q=C.+Ayacucho+475,+Pisco,+Peru&output=embed",
  mapaUrl: "https://www.google.com/maps/search/?api=1&query=C.+Ayacucho+475,+Pisco,+Peru",
};

export interface ProductoMenu {
  /** Debe coincidir EXACTO con Productos.Nombre en la base de datos, así se
   * cruza con el catálogo real que trae GET /publico/catalogo (mismo
   * nombre, mismo producto, sin necesitar guardar el IdProducto acá). */
  nombreEnCatalogo: string;
  nombre: string;
  descripcion: string;
  imagen: string;
}

// Solo los panes que ya tienen foto propia — el resto del catálogo (pan de
// yema, de maíz, integral, de manteca, petipanes) se agrega acá apenas
// tengan su foto; hasta entonces no se muestran ni se pueden pedir desde
// la página, aunque ya existan en la base de datos.
export const PRODUCTOS: ProductoMenu[] = [
  {
    nombreEnCatalogo: "Pan de Hamburguesa Clásico",
    nombre: "Pan de hamburguesa",
    descripcion: "Suave, dorado y recién horneado, el compañero perfecto para tu hamburguesa.",
    imagen: "/images/productos/pan-de-hamburguesa.jpg",
  },
  {
    nombreEnCatalogo: "Pan de Agua",
    nombre: "Pan de agua",
    descripcion: "El clásico de siempre, con esa corteza crujiente y esa miga suave que ya conoces.",
    imagen: "/images/productos/pan-de-agua.jpg",
  },
  {
    nombreEnCatalogo: "Pan Francés",
    nombre: "Pan francés",
    descripcion: "Dorado y crocante por fuera, ligero por dentro.",
    imagen: "/images/productos/pan-frances.jpg",
  },
];


