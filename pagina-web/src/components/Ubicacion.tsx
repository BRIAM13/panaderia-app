import { motion } from "framer-motion";
import { MapPin, ExternalLink } from "lucide-react";
import { UBICACION } from "../data/config";

const EASE_PREMIUM = [0.16, 1, 0.3, 1] as const;

export function Ubicacion() {
  return (
    <section id="ubicacion" className="bg-mesh-panaderia px-6 py-24 sm:py-32">
      <div className="mx-auto grid max-w-5xl items-center gap-10 lg:grid-cols-2">
        <motion.div
          initial={{ opacity: 0, x: -20 }}
          whileInView={{ opacity: 1, x: 0 }}
          viewport={{ once: true, margin: "-100px" }}
          transition={{ duration: 0.6, ease: EASE_PREMIUM }}
        >
          <motion.div
            animate={{ y: [0, -6, 0] }}
            transition={{ duration: 2.6, repeat: Infinity, ease: "easeInOut" }}
            className="mb-5 flex h-14 w-14 items-center justify-center rounded-2xl bg-pan-terracota-suave/60 text-pan-terracota"
          >
            <MapPin className="h-7 w-7" />
          </motion.div>
          <h2 className="font-[family-name:var(--font-display-panaderia)] text-4xl font-semibold text-pan-carbon sm:text-5xl">
            Visítanos
          </h2>
          <p className="mt-4 text-lg text-pan-carbon-suave">{UBICACION.direccion}</p>
          <p className="text-lg text-pan-carbon-suave">{UBICACION.ciudad}</p>
          <p className="mt-2 text-sm text-pan-carbon-suave">Referencia: {UBICACION.referencia}</p>
          <motion.a
            href={UBICACION.mapaUrl}
            target="_blank"
            rel="noopener noreferrer"
            whileHover={{ scale: 1.05, y: -2 }}
            whileTap={{ scale: 0.97 }}
            className="boton-relleno mt-6 inline-flex items-center gap-2 rounded-full border border-pan-bronce-suave bg-pan-crema-suave px-5 py-2.5 text-sm font-semibold text-pan-carbon shadow-sm shadow-pan-carbon/5"
          >
            Abrir en Google Maps
            <ExternalLink className="h-4 w-4" />
          </motion.a>
        </motion.div>

        <motion.div
          initial={{ opacity: 0, x: 20 }}
          whileInView={{ opacity: 1, x: 0 }}
          viewport={{ once: true, margin: "-100px" }}
          transition={{ duration: 0.6, ease: EASE_PREMIUM, delay: 0.1 }}
          whileHover={{ scale: 1.015 }}
          className="aspect-4/3 w-full overflow-hidden rounded-3xl shadow-sm shadow-pan-carbon/10 transition-shadow duration-300 hover:shadow-xl hover:shadow-pan-carbon/15"
        >
          <iframe
            title="Ubicación de Panadería Ronceros"
            src={UBICACION.mapaEmbedUrl}
            className="h-full w-full border-0"
            loading="lazy"
            referrerPolicy="no-referrer-when-downgrade"
          />
        </motion.div>
      </div>
    </section>
  );
}
