import { motion } from "framer-motion";
import { ClipboardList, Store } from "lucide-react";
import { EASE_PREMIUM, VIEWPORT_REVEAL } from "../utils/animacion";
import { IconoWhatsApp } from "./IconoWhatsApp";

/** Los tres pasos reales del pedido por la web, tal como funcionan hoy:
 *  1. El formulario de abajo crea el pedido en estado SOLICITADO (ver
 *     publicoController.js) — todavía no está confirmado.
 *  2. El negocio lo confirma a mano, avisando al celular que dejó el
 *     cliente ("Te llamaremos al número que dejaste para confirmarlo").
 *  3. No hay reparto ni cobro en línea en ninguna parte del sistema: el
 *     pedido se recoge en la tienda y se paga ahí.
 * Nada de esto es una promesa nueva: es lo que ya pasa, contado antes de
 * que el visitante se meta en el formulario. */
interface Paso {
  /** Tipado al mínimo común (solo `className`) porque la lista mezcla
   * íconos de lucide con el de WhatsApp, que es un SVG propio. */
  icono: React.ComponentType<{ className?: string }>;
  titulo: string;
  texto: string;
}

const PASOS: Paso[] = [
  {
    icono: ClipboardList,
    titulo: "Haces tu pedido",
    texto: "Eliges tu pan, la cantidad y a qué hora lo quieres recoger. No hace falta crear ninguna cuenta.",
  },
  {
    icono: IconoWhatsApp,
    titulo: "Te confirmamos",
    texto: "Te escribimos o llamamos al celular que dejaste para confirmar que tu pedido está separado.",
  },
  {
    icono: Store,
    titulo: "Recoges y pagas",
    texto: "Pasas por la panadería a la hora acordada, recoges tu pan y lo pagas ahí mismo.",
  },
];

/** Banda corta de tres pasos, justo antes del formulario: contesta "¿y qué
 * pasa después de que envío esto?" antes de pedirle datos a nadie. */
export function ComoFunciona() {
  return (
    <section className="px-6 pt-20 sm:pt-28">
      <div className="mx-auto max-w-4xl">
        <motion.p
          initial={{ opacity: 0, y: 12 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={VIEWPORT_REVEAL}
          transition={{ duration: 0.5, ease: EASE_PREMIUM }}
          className="text-center text-xs font-semibold tracking-[0.18em] text-pan-carbon-suave uppercase"
        >
          Cómo funciona
        </motion.p>

        <ol className="mt-8 grid grid-cols-1 gap-4 sm:grid-cols-3 sm:gap-5">
          {PASOS.map(({ icono: Icono, titulo, texto }, indice) => (
            <motion.li
              key={titulo}
              initial={{ opacity: 0, y: 24 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true, margin: "-60px" }}
              transition={{ duration: 0.55, ease: EASE_PREMIUM, delay: indice * 0.09 }}
              className="tarjeta-realce relative flex gap-4 rounded-2xl border border-pan-borde/25 bg-pan-crema-suave p-5 shadow-sm shadow-pan-carbon/5 transition-shadow duration-300 hover:shadow-lg hover:shadow-pan-carbon/10 sm:flex-col sm:gap-3"
            >
              <span className="relative flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl bg-pan-terracota-suave/60 text-pan-terracota">
                <Icono className="h-5 w-5" />
                {/* El número va como sello sobre el ícono, no como una
                    columna aparte: en celular las tarjetas son horizontales
                    y una tercera columna solo para el dígito las apretaba. */}
                <span
                  aria-hidden="true"
                  className="absolute -top-2 -right-2 flex h-5 w-5 items-center justify-center rounded-full bg-pan-terracota text-[0.6875rem] font-bold text-pan-crema"
                >
                  {indice + 1}
                </span>
              </span>
              <div>
                <p className="font-[family-name:var(--font-display-panaderia)] text-base font-semibold text-pan-carbon">
                  {titulo}
                </p>
                <p className="mt-1 text-sm leading-relaxed text-pan-carbon-suave">{texto}</p>
              </div>
            </motion.li>
          ))}
        </ol>
      </div>
    </section>
  );
}
