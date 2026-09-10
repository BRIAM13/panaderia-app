// Prepara las fotos de producto para la web y arma la imagen social
// (og:image). Las fotos salen de la cámara en 2048x2048 y ~2.7MB cada una,
// pero en la página no se muestran nunca por encima de ~448px de ancho:
// servirlas tal cual era, de lejos, lo más pesado de todo el sitio.
//
// Cómo se usa cuando entra una foto nueva:
//   1. Se deja el archivo original (JPEG, el que salga de la cámara) en
//      pagina-web/fotos-originales/ con el nombre que va a usar el sitio.
//   2. npm run optimizar-imagenes
//
// De cada original deja dos archivos en public/images/productos/ (que es
// lo único que se publica):
//   nombre.webp  -> el que carga cualquier navegador moderno (<source>)
//   nombre.jpg   -> el mismo recorte en JPEG, como respaldo del <picture>
//
// Los originales viven FUERA de public/ a propósito: son el archivo
// maestro del que se vuelve a generar todo, no algo que haya que
// descargarle a nadie (8MB entre las tres, sin que ninguna página las
// pida).
//
// Y, aparte, public/og-image.jpg: el recorte 1200x630 que usan Facebook,
// WhatsApp y X al compartir el enlace, más los tres íconos del sitio
// (favicon-32, favicon-64 y apple-touch-icon), que salen todos del dibujo
// de la mascota. Si se cambia el panadero, basta volver a correr esto para
// que la pestaña del navegador y el ícono de iOS queden al día.

import { mkdir, readdir, stat } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import sharp from "sharp";

const RAIZ = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const DIR_ORIGINALES = path.join(RAIZ, "fotos-originales");
const DIR_PUBLICO = path.join(RAIZ, "public", "images", "productos");

// 1200px de lado mayor: más del doble del tamaño máximo al que se muestra
// (448px en la tarjeta del menú y en la foto de portada), así se ve nítida
// también en pantallas de densidad 2x sin cargar 2048px de nada.
const LADO_MAXIMO = 1200;
const CALIDAD_WEBP = 80;
const CALIDAD_JPEG = 82;

// Medidas que piden Open Graph y Twitter para la tarjeta grande.
const OG_ANCHO = 1200;
const OG_ALTO = 630;
// La foto del pan de agua es la misma que abre la página (el hero), así
// que la vista previa al compartir coincide con lo primero que se ve.
const OG_ORIGEN = "pan-de-agua.jpg";

function kb(bytes) {
  return `${(bytes / 1024).toFixed(0)} KB`;
}

async function tamano(archivo) {
  return (await stat(archivo)).size;
}

async function optimizarProducto(nombreArchivo) {
  const origen = path.join(DIR_ORIGINALES, nombreArchivo);
  const base = nombreArchivo.replace(/\.jpe?g$/i, "");
  const destinoWebp = path.join(DIR_PUBLICO, `${base}.webp`);
  const destinoJpg = path.join(DIR_PUBLICO, `${base}.jpg`);

  const redimensionada = () =>
    sharp(origen).resize({
      width: LADO_MAXIMO,
      height: LADO_MAXIMO,
      fit: "inside",
      withoutEnlargement: true,
    });

  await redimensionada().webp({ quality: CALIDAD_WEBP }).toFile(destinoWebp);
  await redimensionada().jpeg({ quality: CALIDAD_JPEG, mozjpeg: true }).toFile(destinoJpg);

  const meta = await sharp(destinoWebp).metadata();
  console.log(
    `  ${nombreArchivo}: ${kb(await tamano(origen))} -> ` +
      `${meta.width}x${meta.height} · webp ${kb(await tamano(destinoWebp))} · ` +
      `jpg ${kb(await tamano(destinoJpg))}`,
  );
}

async function generarOgImage() {
  const origen = path.join(DIR_ORIGINALES, OG_ORIGEN);
  const destino = path.join(RAIZ, "public", "og-image.jpg");
  await sharp(origen)
    // `cover` + `attention` recorta la franja apaisada quedándose con la
    // zona con más detalle de la foto cuadrada, en vez de cortar por el
    // centro geométrico a ciegas.
    .resize(OG_ANCHO, OG_ALTO, { fit: "cover", position: sharp.strategy.attention })
    .jpeg({ quality: CALIDAD_JPEG, mozjpeg: true })
    .toFile(destino);
  console.log(`  og-image.jpg: ${OG_ANCHO}x${OG_ALTO} · ${kb(await tamano(destino))}`);
}

// Los tres íconos del sitio (pestaña del navegador y pantalla de inicio de
// iOS) salen del mismo sitio: un recorte de la CABEZA de la mascota. El
// cuerpo entero no sirve para esto — a 32px, un panadero de cuerpo entero
// es una mancha de tres píxeles de ancho; la cara con gorro se reconoce
// hasta ahí. El encuadre va en proporciones y no en píxeles para que siga
// valiendo si el dibujo del panadero cambia de tamaño: un cuadrado que
// arranca justo arriba del gorro, baja hasta los hombros (un tercio del
// alto de la figura) y se centra en el eje de la cabeza, que cae un pelo a
// la izquierda del centro del dibujo.
const CABEZA_ALTO = 0.328; // del alto del dibujo: gorro + cara + hombros
const CABEZA_CENTRO = 0.491; // del ancho: dónde cae el eje de la cabeza
const FAVICONS = [64, 32];
const ICONO_IOS = 180;
// Todos van opacos sobre el crema de la marca: iOS rellena de negro las
// transparencias, y en la pestaña de un navegador en modo oscuro la cara
// del panadero quedaría flotando sin fondo.
const CREMA = { r: 253, g: 246, b: 236 };

const ORIGEN_MASCOTA = path.join(RAIZ, "public", "images", "mascota", "panadero.png");

async function recorteCabeza() {
  const { width, height } = await sharp(ORIGEN_MASCOTA).metadata();
  const lado = Math.round(height * CABEZA_ALTO);
  const left = Math.max(0, Math.min(width - lado, Math.round(width * CABEZA_CENTRO - lado / 2)));
  return { left, top: 0, width: lado, height: lado };
}

async function generarIconos() {
  const cabeza = await recorteCabeza();
  for (const medida of FAVICONS) {
    const destino = path.join(RAIZ, "public", `favicon-${medida}.png`);
    await sharp(ORIGEN_MASCOTA)
      .extract(cabeza)
      .resize(medida, medida)
      .flatten({ background: CREMA })
      .png()
      .toFile(destino);
    console.log(`  favicon-${medida}.png: ${medida}x${medida} · ${kb(await tamano(destino))}`);
  }

  // El de iOS lleva 12px de aire alrededor: el sistema le recorta las
  // esquinas para redondearlo y, a sangre, se comería parte del gorro.
  const destino = path.join(RAIZ, "public", "apple-touch-icon.png");
  await sharp(ORIGEN_MASCOTA)
    .extract(cabeza)
    .resize(ICONO_IOS - 24, ICONO_IOS - 24)
    .extend({ top: 12, bottom: 12, left: 12, right: 12, background: CREMA })
    .flatten({ background: CREMA })
    .png()
    .toFile(destino);
  console.log(`  apple-touch-icon.png: ${ICONO_IOS}x${ICONO_IOS} · ${kb(await tamano(destino))}`);
}

async function principal() {
  await mkdir(DIR_PUBLICO, { recursive: true });
  const archivos = (await readdir(DIR_ORIGINALES)).filter((f) => /\.jpe?g$/i.test(f)).sort();

  console.log(`Optimizando ${archivos.length} foto(s) de producto…`);
  for (const archivo of archivos) {
    await optimizarProducto(archivo);
  }

  console.log("Generando la imagen social (og:image) y los íconos…");
  await generarOgImage();
  await generarIconos();
  console.log("Listo.");
}

principal().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
