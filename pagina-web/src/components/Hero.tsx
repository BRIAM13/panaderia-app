import { useRef } from "react";
import { motion, useReducedMotion, useScroll, useSpring, useTransform } from "framer-motion";
import { ArrowRight, ChevronDown, Croissant, MapPin, Sunrise, Users } from "lucide-react";
import { SITE, UBICACION } from "../data/config";
import { desplazarASeccion } from "../utils/scroll";
import { EASE_PREMIUM } from "../utils/animacion";

/** Tres razones cortas, todas verdaderas y ya contadas en el resto del
 * sitio, justo debajo de los botones: le dan al visitante el "por qué" en
 * un vistazo sin obligarlo a bajar hasta Nosotros, y equilibran el peso
 * visual de la columna de texto frente a la foto. */
const RAZONES = [
  { icono: Sunrise, texto: "Horneado cada mañana" },
  { icono: Users, texto: "Receta de familia" },
  { icono: Croissant, texto: "Pedido sin crear cuenta" },
] as const;

export function Hero() {
  const ref = useRef<HTMLElement>(null);
  const sinMovimiento = useReducedMotion();
  const { scrollYProgress } = useScroll({ target: ref, offset: ["start start", "end start"] });

  // El parallax pasa por un muelle: al hacer scroll con rueda (que avanza
  // a saltos de ~100px) el desplazamiento directo se ve escalonado, y
  // suavizarlo es lo que separa un parallax "barato" de uno que se siente
  // parte de la página.
  const avance = useSpring(scrollYProgress, { stiffness: 90, damping: 26, restDelta: 0.001 });
  const yImagen = useTransform(avance, [0, 1], [0, 110]);
  const escalaImagen = useTransform(avance, [0, 1], [1, 1.06]);
  // El texto se va un poco más lento que la foto: esa diferencia de
  // velocidad es la que da la sensación de profundidad entre las dos
  // columnas, en vez de que todo el bloque suba en bloque.
  const yTexto = useTransform(avance, [0, 1], [0, 40]);
  const opacidad = useTransform(scrollYProgress, [0, 0.8], [1, 0]);

  return (
    <section
      ref={ref}
      className="relative overflow-hidden pt-32 pb-20 sm:pt-40 sm:pb-28"
    >
      {/* Manchas de color de fondo con deriva lenta y continua — textura
          "viva" de fondo, nunca tan rápida como para competir con el
          contenido. */}
      <div className="pointer-events-none absolute inset-0 -z-10">
        <motion.div
          animate={{ x: [0, 30, -10, 0], y: [0, -20, 10, 0] }}
          transition={{ duration: 22, repeat: Infinity, ease: "easeInOut" }}
          className="absolute -top-24 -left-24 h-96 w-96 rounded-full bg-pan-terracota-suave/50 blur-3xl"
        />
        <motion.div
          animate={{ x: [0, -25, 15, 0], y: [0, 20, -15, 0] }}
          transition={{ duration: 26, repeat: Infinity, ease: "easeInOut" }}
          className="absolute top-1/3 -right-32 h-96 w-96 rounded-full bg-pan-bronce-suave/50 blur-3xl"
        />
        <motion.div
          animate={{ scale: [1, 1.15, 1] }}
          transition={{ duration: 10, repeat: Infinity, ease: "easeInOut" }}
          className="absolute top-8 right-[18%] h-3 w-3 rounded-full bg-pan-oro/70 blur-[1px]"
        />
        <motion.div
          animate={{ scale: [1, 1.25, 1] }}
          transition={{ duration: 8, repeat: Infinity, ease: "easeInOut", delay: 1.2 }}
          className="absolute top-1/2 left-[8%] h-2 w-2 rounded-full bg-pan-terracota/50 blur-[1px]"
        />
      </div>

      <motion.div style={{ opacity: opacidad }} className="mx-auto grid max-w-6xl items-center gap-12 px-6 lg:grid-cols-2">
        <motion.div style={{ y: yTexto }}>
          <motion.p
            initial={{ opacity: 0, y: 14 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6, ease: EASE_PREMIUM }}
            className="mb-4 inline-flex items-center gap-2 rounded-full border border-pan-terracota/15 bg-pan-terracota-suave/60 px-4 py-1.5 text-sm font-medium text-pan-terracota-profundo"
          >
            <MapPin className="h-4 w-4" strokeWidth={1.75} />
            {UBICACION.ciudad}
          </motion.p>

          <motion.h1
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.7, ease: EASE_PREMIUM, delay: 0.05 }}
            // 48px era demasiado para 375px de ancho: "hecho en familia" no
            // entraba en una línea y "familia" caía sola en un cuarto
            // renglón, con el titular ocupando media pantalla antes de que
            // se leyera una palabra del resto. La escala sube en dos
            // escalones y a partir de sm queda idéntica al diseño de
            // escritorio ya aprobado.
            className="font-[family-name:var(--font-display-panaderia)] text-4xl leading-[1.05] font-semibold tracking-[-0.015em] text-pan-carbon min-[480px]:text-5xl sm:text-6xl"
          >
            {/* `equilibrar-texto` reparte esta primera frase en dos líneas
                parejas ("Pan artesanal / de siempre") en vez de dejar la
                palabra "siempre" sola colgando en su propia línea, que es
                como caía al no entrar completa en el ancho de la columna. */}
            <span className="equilibrar-texto block">
              Pan artesanal <span className="text-gradient-pan">de siempre</span>
            </span>
            <span className="block">hecho en familia</span>
          </motion.h1>

          <motion.p
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.7, ease: EASE_PREMIUM, delay: 0.12 }}
            className="mt-6 max-w-md text-lg leading-relaxed text-pan-carbon-suave"
          >
            {SITE.descripcion}
          </motion.p>

          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.7, ease: EASE_PREMIUM, delay: 0.18 }}
            // En celular los dos botones se apilan a todo el ancho en vez
            // de quedar uno debajo del otro con anchos distintos (que es
            // como caían al envolverse): una columna pareja de acciones se
            // toca mejor con el pulgar y se lee como una jerarquía clara.
            className="mt-8 flex flex-col gap-3 min-[480px]:flex-row min-[480px]:flex-wrap min-[480px]:gap-4"
          >
            <motion.a
              href="#pedido"
              onClick={(e) => {
                e.preventDefault();
                desplazarASeccion("pedido");
              }}
              whileHover={{ scale: 1.05, y: -2 }}
              whileTap={{ scale: 0.97 }}
              className="group inline-flex w-full items-center justify-center gap-2 rounded-full bg-pan-terracota px-6 py-3.5 font-semibold text-pan-crema shadow-lg shadow-pan-terracota/20 transition-shadow hover:shadow-xl hover:shadow-pan-terracota/30 min-[480px]:w-auto"
            >
              Hacer un pedido
              <ArrowRight className="h-4 w-4 transition-transform duration-300 group-hover:translate-x-1" />
            </motion.a>
            <motion.a
              href="#menu"
              onClick={(e) => {
                e.preventDefault();
                desplazarASeccion("menu");
              }}
              whileHover={{ scale: 1.05, y: -2 }}
              whileTap={{ scale: 0.97 }}
              className="boton-relleno inline-flex w-full items-center justify-center gap-2 rounded-full border border-pan-borde bg-pan-crema-suave px-6 py-3.5 font-semibold text-pan-carbon min-[480px]:w-auto"
            >
              Ver nuestro pan
            </motion.a>
          </motion.div>

          <motion.ul
            initial={{ opacity: 0, y: 16 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.7, ease: EASE_PREMIUM, delay: 0.26 }}
            className="mt-10 flex flex-wrap items-center gap-x-5 gap-y-3 border-t border-pan-borde/35 pt-6"
          >
            {RAZONES.map(({ icono: Icono, texto }) => (
              <li key={texto} className="flex items-center gap-2 text-[0.8125rem] font-medium text-pan-carbon-suave">
                <Icono className="h-4 w-4 shrink-0 text-pan-bronce-oscuro" strokeWidth={1.75} />
                {texto}
              </li>
            ))}
          </motion.ul>
        </motion.div>

        <motion.div
          style={{ y: yImagen }}
          initial={{ opacity: 0, scale: 0.94 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ duration: 0.8, ease: EASE_PREMIUM, delay: 0.15 }}
          className="relative mx-auto aspect-square w-full max-w-md"
        >
          {/* Halo cálido detrás de la foto: separa la imagen del fondo sin
              recurrir a un marco duro. */}
          <div
            aria-hidden="true"
            className="pointer-events-none absolute -inset-6 -z-10 rounded-[3rem] bg-gradient-to-br from-pan-bronce-suave/60 via-transparent to-pan-terracota-suave/60 blur-2xl"
          />

          <div className="relative h-full w-full overflow-hidden rounded-[2.5rem] shadow-2xl shadow-pan-carbon/15">
            {/* La foto se agranda muy despacio mientras se hace scroll: el
                encuadre "respira" en vez de quedarse congelado. */}
            <motion.img
              style={{ scale: escalaImagen }}
              src="/images/productos/pan-de-agua.jpg"
              alt="Pan de agua recién horneado de Panadería Ronceros"
              className="h-full w-full object-cover"
            />
            <div className="pointer-events-none absolute inset-0 bg-gradient-to-t from-pan-carbon/15 via-transparent to-transparent" />

            {/* Vapor: tres hilos de humo tenues que suben y se disuelven
                sobre el pan. Es el gesto que más "recién horneado" comunica
                y no cuesta ni una dependencia nueva. Se apaga solo si el
                visitante pidió menos movimiento. */}
            {!sinMovimiento && (
              <div aria-hidden="true" className="pointer-events-none absolute inset-x-0 top-0 h-1/2">
                {[
                  { izquierda: "34%", retraso: 0, duracion: 6.5 },
                  { izquierda: "50%", retraso: 1.6, duracion: 7.4 },
                  { izquierda: "64%", retraso: 3.1, duracion: 6.9 },
                ].map((hilo) => (
                  <motion.span
                    key={hilo.izquierda}
                    initial={{ opacity: 0, y: 40, scaleX: 0.6 }}
                    animate={{ opacity: [0, 0.5, 0], y: [40, -60], scaleX: [0.6, 1.5] }}
                    transition={{
                      duration: hilo.duracion,
                      repeat: Infinity,
                      delay: hilo.retraso,
                      ease: "easeOut",
                    }}
                    style={{ left: hilo.izquierda }}
                    className="absolute top-1/2 h-24 w-10 -translate-x-1/2 rounded-full bg-gradient-to-t from-white/0 via-white/45 to-white/0 blur-md"
                  />
                ))}
              </div>
            )}
          </div>

          <motion.div
            animate={{ y: [0, -10, 0] }}
            transition={{ duration: 4, repeat: Infinity, ease: "easeInOut" }}
            // En celular la foto ya ocupa casi todo el ancho, así que un
            // desplazamiento negativo dejaba la ficha rozando el borde de
            // la pantalla; recién cuando hay margen alrededor (sm) vuelve a
            // salirse de la foto como en el diseño de escritorio.
            className="absolute -bottom-4 left-0 flex items-center gap-3 rounded-2xl border border-pan-borde/30 bg-pan-crema-suave/95 px-4 py-3 shadow-lg shadow-pan-carbon/10 backdrop-blur-sm sm:-bottom-5 sm:-left-8"
          >
            {/* Punto que late: señala que el dato es "de hoy", en vivo, no
                una etiqueta decorativa cualquiera. */}
            <span className="relative flex h-2.5 w-2.5 shrink-0">
              <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-pan-terracota/60" />
              <span className="relative inline-flex h-2.5 w-2.5 rounded-full bg-pan-terracota" />
            </span>
            <span>
              <span className="block font-[family-name:var(--font-display-panaderia)] text-sm font-semibold text-pan-carbon">
                Horneado hoy
              </span>
              <span className="block text-xs text-pan-carbon-suave">Fresco cada mañana</span>
            </span>
          </motion.div>
        </motion.div>
      </motion.div>

      <motion.a
        href="#nosotros"
        onClick={(e) => {
          e.preventDefault();
          desplazarASeccion("nosotros");
        }}
        style={{ opacity: opacidad }}
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ duration: 0.6, delay: 0.6 }}
        aria-label="Bajar a la siguiente sección"
        className="absolute inset-x-0 bottom-6 mx-auto hidden w-fit rounded-full p-2 text-pan-carbon-suave/70 transition-colors hover:text-pan-terracota sm:block"
      >
        <motion.div
          animate={{ y: [0, 8, 0] }}
          transition={{ duration: 1.8, repeat: Infinity, ease: "easeInOut" }}
        >
          <ChevronDown className="h-6 w-6" />
        </motion.div>
      </motion.a>
    </section>
  );
}
