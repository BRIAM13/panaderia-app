import { useRef } from "react";
import { motion, useScroll, useTransform } from "framer-motion";
import { ArrowRight, MapPin } from "lucide-react";
import { SITE, UBICACION } from "../data/config";

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
      {/* Manchas de color de fondo, muy suaves — solo textura, nunca compiten con el contenido. */}
      <div className="pointer-events-none absolute inset-0 -z-10">
        <div className="absolute -top-24 -left-24 h-96 w-96 rounded-full bg-pan-terracota-suave/50 blur-3xl" />
        <div className="absolute top-1/3 -right-32 h-96 w-96 rounded-full bg-pan-bronce-suave/50 blur-3xl" />
      </div>

      <motion.div style={{ opacity: opacidad }} className="mx-auto grid max-w-6xl items-center gap-12 px-6 lg:grid-cols-2">
        <div>
          <motion.p
            initial={{ opacity: 0, y: 14 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6, ease: EASE_PREMIUM }}
            className="mb-4 inline-flex items-center gap-2 rounded-full bg-pan-terracota-suave/60 px-4 py-1.5 text-sm font-medium text-pan-terracota"
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
            <a
              href="#pedido"
              className="inline-flex items-center gap-2 rounded-full bg-pan-terracota px-6 py-3.5 font-semibold text-pan-crema shadow-lg shadow-pan-terracota/20 transition-transform hover:scale-105"
            >
              Hacer un pedido
              <ArrowRight className="h-4 w-4" />
            </a>
            <a
              href="#menu"
              className="inline-flex items-center gap-2 rounded-full border border-pan-bronce-suave bg-pan-crema-suave px-6 py-3.5 font-semibold text-pan-carbon transition-colors hover:bg-pan-crema-muted"
            >
              Ver nuestro pan
            </a>
          </motion.div>
        </div>

        <motion.div
          style={{ y: yImagen }}
          initial={{ opacity: 0, scale: 0.94 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ duration: 0.8, ease: EASE_PREMIUM, delay: 0.15 }}
          className="relative mx-auto aspect-square w-full max-w-md overflow-hidden rounded-[2.5rem] shadow-2xl shadow-pan-carbon/15"
        >
          <img
            src="/images/productos/pan-de-agua.jpg"
            alt="Pan de agua recién horneado de Panadería Ronceros"
            className="h-full w-full object-cover"
          />
        </motion.div>
      </motion.div>
    </section>
  );
}
