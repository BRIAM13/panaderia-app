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
  direccion: "Calle Ayacucho 478",
  ciudad: "Pisco, Perú",
  referencia: "Frente a la gruta de la Virgen de Chapi",
  // Google Maps no siempre ubica bien el 478 exacto, pero sí encuentra
  // correctamente el 475 (misma cuadra, a un paso) — se usa ese número solo
  // para que el mapa abra en el lugar correcto, aunque el texto que lee el
  // cliente arriba siga mostrando la dirección real.
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


