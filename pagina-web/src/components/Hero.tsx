import { useRef } from "react";
import { motion, useScroll, useTransform } from "framer-motion";
import { ArrowRight, ChevronDown, MapPin } from "lucide-react";
import { SITE, UBICACION } from "../data/config";
import { desplazarASeccion } from "../utils/scroll";

const EASE_PREMIUM = [0.16, 1, 0.3, 1] as const;

export function Hero() {
  const ref = useRef<HTMLElement>(null);
  const { scrollYProgress } = useScroll({ target: ref, offset: ["start start", "end start"] });
  const yImagen = useTransform(scrollYProgress, [0, 1], [0, 90]);
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
        <div>
          <motion.p
            initial={{ opacity: 0, y: 14 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6, ease: EASE_PREMIUM }}
            className="mb-4 inline-flex items-center gap-2 rounded-full bg-pan-terracota-suave/60 px-4 py-1.5 text-sm font-medium text-pan-terracota-profundo"
          >
            <MapPin className="h-4 w-4" />
            {UBICACION.ciudad}
          </motion.p>

          <motion.h1
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.7, ease: EASE_PREMIUM, delay: 0.05 }}
            className="font-[family-name:var(--font-display-panaderia)] text-5xl leading-[1.05] font-semibold text-pan-carbon sm:text-6xl"
          >
            <span className="block">
              Pan artesanal <span className="text-gradient-pan">de siempre</span>
            </span>
            <span className="block">hecho en familia</span>
          </motion.h1>

          <motion.p
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.7, ease: EASE_PREMIUM, delay: 0.12 }}
            className="mt-6 max-w-md text-lg text-pan-carbon-suave"
          >
            {SITE.descripcion}
          </motion.p>

          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.7, ease: EASE_PREMIUM, delay: 0.18 }}
            className="mt-8 flex flex-wrap gap-4"
          >
            <motion.a
              href="#pedido"
              onClick={(e) => {
                e.preventDefault();
                desplazarASeccion("pedido");
              }}
              whileHover={{ scale: 1.05, y: -2 }}
              whileTap={{ scale: 0.97 }}
              className="inline-flex items-center gap-2 rounded-full bg-pan-terracota px-6 py-3.5 font-semibold text-pan-crema shadow-lg shadow-pan-terracota/20 transition-shadow hover:shadow-xl hover:shadow-pan-terracota/30"
            >
              Hacer un pedido
              <ArrowRight className="h-4 w-4" />
            </motion.a>
            <motion.a
              href="#menu"
              onClick={(e) => {
                e.preventDefault();
                desplazarASeccion("menu");
              }}
              whileHover={{ scale: 1.05, y: -2 }}
              whileTap={{ scale: 0.97 }}
              className="boton-relleno inline-flex items-center gap-2 rounded-full border border-pan-bronce-suave bg-pan-crema-suave px-6 py-3.5 font-semibold text-pan-carbon"
            >
              Ver nuestro pan
            </motion.a>
          </motion.div>
        </div>

        <motion.div
          style={{ y: yImagen }}
          initial={{ opacity: 0, scale: 0.94 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ duration: 0.8, ease: EASE_PREMIUM, delay: 0.15 }}
          className="relative mx-auto aspect-square w-full max-w-md"
        >
          <div className="relative h-full w-full overflow-hidden rounded-[2.5rem] shadow-2xl shadow-pan-carbon/15">
            <img
              src="/images/productos/pan-de-agua.jpg"
              alt="Pan de agua recién horneado de Panadería Ronceros"
              className="h-full w-full object-cover"
            />
            <div className="pointer-events-none absolute inset-0 bg-gradient-to-t from-pan-carbon/15 via-transparent to-transparent" />
          </div>
          <motion.div
            animate={{ y: [0, -10, 0] }}
            transition={{ duration: 4, repeat: Infinity, ease: "easeInOut" }}
            className="absolute -bottom-5 -left-5 rounded-2xl bg-pan-crema-suave px-4 py-3 shadow-lg shadow-pan-carbon/10 sm:-left-8"
          >
            <p className="font-[family-name:var(--font-display-panaderia)] text-sm font-semibold text-pan-carbon">
              Horneado hoy
            </p>
            <p className="text-xs text-pan-carbon-suave">Fresco cada mañana</p>
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
        className="absolute inset-x-0 bottom-6 mx-auto hidden w-fit text-pan-carbon-suave/70 transition-colors hover:text-pan-terracota sm:block"
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
