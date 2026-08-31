import { motion } from "framer-motion";
import { MapPin, ExternalLink, Navigation, Church } from "lucide-react";
import { UBICACION } from "../data/config";
import { EASE_PREMIUM, VIEWPORT_REVEAL } from "../utils/animacion";
import { EncabezadoSeccion } from "./EncabezadoSeccion";

export function Ubicacion() {
  return (
    <section id="ubicacion" className="textura-grano bg-mesh-panaderia px-6 py-24 sm:py-32">
      <div className="mx-auto grid max-w-5xl items-center gap-10 lg:grid-cols-2">
        <motion.div
          initial={{ opacity: 0, x: -20 }}
          whileInView={{ opacity: 1, x: 0 }}
          viewport={VIEWPORT_REVEAL}
          transition={{ duration: 0.6, ease: EASE_PREMIUM }}
        >
          <EncabezadoSeccion
            etiqueta="Dónde estamos"
            icono={MapPin}
            titulo="Visítanos"
            alineacion="izquierda"
          />

          {/* La dirección pasa a ser una ficha con su propio ícono en vez de
              tres párrafos sueltos: se distingue a simple vista de la
              referencia del altar, que es otra clase de dato. */}
          <div className="mt-8 space-y-4">
            <div className="flex items-start gap-3.5">
              <span className="mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-pan-crema-suave text-pan-terracota shadow-sm shadow-pan-carbon/5">
                <Navigation className="h-4 w-4" strokeWidth={1.75} />
              </span>
              <div>
                <p className="text-lg leading-snug font-medium text-pan-carbon">{UBICACION.direccion}</p>
                <p className="text-lg leading-snug text-pan-carbon-suave">{UBICACION.ciudad}</p>
              </div>
            </div>
            <div className="flex items-start gap-3.5">
              <span className="mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-pan-crema-suave text-pan-bronce-oscuro shadow-sm shadow-pan-carbon/5">
                <Church className="h-4 w-4" strokeWidth={1.75} />
              </span>
              <p className="max-w-sm text-sm leading-relaxed text-pan-carbon-suave">{UBICACION.referencia}</p>
            </div>
          </div>

          <motion.a
            href={UBICACION.mapaUrl}
            target="_blank"
            rel="noopener noreferrer"
            whileHover={{ scale: 1.05, y: -2 }}
            whileTap={{ scale: 0.97 }}
            className="boton-relleno mt-8 inline-flex items-center gap-2 rounded-full border border-pan-borde bg-pan-crema-suave px-5 py-2.5 text-sm font-semibold text-pan-carbon shadow-sm shadow-pan-carbon/5"
          >
            Abrir en Google Maps
            <ExternalLink className="h-4 w-4" strokeWidth={1.75} />
          </motion.a>
        </motion.div>

        <motion.div
          initial={{ opacity: 0, x: 20 }}
          whileInView={{ opacity: 1, x: 0 }}
          viewport={VIEWPORT_REVEAL}
          transition={{ duration: 0.6, ease: EASE_PREMIUM, delay: 0.1 }}
          whileHover={{ scale: 1.015 }}
          className="aspect-4/3 w-full overflow-hidden rounded-3xl border border-pan-borde/25 shadow-sm shadow-pan-carbon/10 transition-shadow duration-300 hover:shadow-xl hover:shadow-pan-carbon/15"
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
