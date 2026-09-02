import { motion } from "framer-motion";
import { MapPin, ExternalLink, Navigation, Church, Clock } from "lucide-react";
import { CONTACTO, UBICACION, enlaceWhatsApp } from "../data/config";
import type { HorariosPanaderia } from "../services/api";
import { formatearHora12 } from "../utils/horariosPan";
import { EASE_PREMIUM, VIEWPORT_REVEAL } from "../utils/animacion";
import { EncabezadoSeccion } from "./EncabezadoSeccion";
import { IconoWhatsApp } from "./IconoWhatsApp";

export function Ubicacion({ horarios }: { horarios: HorariosPanaderia | null }) {
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

            {/* El horario sale del mismo catálogo que rige el formulario de
                pedido (lo edita el dueño desde la app), así que acá no hay
                ninguna hora escrita a mano que se pueda quedar vieja.
                Mientras no haya llegado, no se muestra nada: mejor sin dato
                que con un horario inventado. */}
            {horarios && (
              <div className="flex items-start gap-3.5">
                <span className="mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-pan-crema-suave text-pan-bronce-oscuro shadow-sm shadow-pan-carbon/5">
                  <Clock className="h-4 w-4" strokeWidth={1.75} />
                </span>
                <div>
                  <p className="text-sm font-semibold text-pan-carbon">Horario de atención</p>
                  <p className="text-sm text-pan-carbon-suave">
                    Todos los días, de {formatearHora12(horarios.horaApertura)} a{" "}
                    {formatearHora12(horarios.horaCierre)}
                  </p>
                </div>
              </div>
            )}

            <div className="flex items-start gap-3.5">
              <span className="mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-pan-crema-suave text-pan-terracota shadow-sm shadow-pan-carbon/5">
                <IconoWhatsApp className="h-4 w-4" />
              </span>
              <div>
                <p className="text-sm font-semibold text-pan-carbon">Escríbenos o llámanos</p>
                <a
                  href={enlaceWhatsApp()}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex min-h-11 items-center rounded text-sm text-pan-carbon-suave transition-colors hover:text-pan-terracota lg:min-h-0"
                >
                  {CONTACTO.telefonoVisible}
                </a>
              </div>
            </div>
          </div>

          <div className="mt-8 flex flex-wrap gap-3">
            <motion.a
              href={UBICACION.mapaUrl}
              target="_blank"
              rel="noopener noreferrer"
              whileHover={{ scale: 1.05, y: -2 }}
              whileTap={{ scale: 0.97 }}
              className="boton-relleno inline-flex items-center gap-2 rounded-full border border-pan-borde bg-pan-crema-suave px-5 py-2.5 text-sm font-semibold text-pan-carbon shadow-sm shadow-pan-carbon/5"
            >
              Abrir en Google Maps
              <ExternalLink className="h-4 w-4" strokeWidth={1.75} />
            </motion.a>
            <motion.a
              href={enlaceWhatsApp()}
              target="_blank"
              rel="noopener noreferrer"
              whileHover={{ scale: 1.05, y: -2 }}
              whileTap={{ scale: 0.97 }}
              className="inline-flex items-center gap-2 rounded-full bg-pan-terracota px-5 py-2.5 text-sm font-semibold text-pan-crema shadow-sm shadow-pan-terracota/25 transition-shadow hover:shadow-md hover:shadow-pan-terracota/35"
            >
              <IconoWhatsApp className="h-4 w-4" />
              Escríbenos por WhatsApp
            </motion.a>
          </div>
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
