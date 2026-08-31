import { motion } from "framer-motion";
import type { LucideIcon } from "lucide-react";
import { EASE_PREMIUM, VIEWPORT_REVEAL, contenedorEscalonado, subirAlAparecer } from "../utils/animacion";

interface EncabezadoSeccionProps {
  /** Etiqueta corta sobre el título ("Nuestra casa", "El pan", …). Da a
   * cada sección un primer escalón de jerarquía antes del titular. */
  etiqueta: string;
  icono: LucideIcon;
  /** El título completo. Para resaltar una parte con el degradado de la
   * marca, se pasa aparte en `tituloDestacado` (se agrega al final). */
  titulo: string;
  tituloDestacado?: string;
  descripcion?: string;
  alineacion?: "centro" | "izquierda";
  /** Tono del recuadro del ícono — permite alternar entre secciones sin
   * que cada una invente su propia combinación de colores. */
  tono?: "terracota" | "bronce";
  className?: string;
}

const TONOS = {
  terracota: "bg-pan-terracota-suave/60 text-pan-terracota",
  bronce: "bg-pan-bronce-suave/70 text-pan-bronce-oscuro",
} as const;

/** Cabecera compartida por todas las secciones (Nosotros, Nuestro pan,
 * Haz tu pedido, Visítanos). Antes cada una armaba la suya a mano y
 * terminaron distintas entre sí: unas con ícono y otras sin él, unas con
 * bajada y otras sin ella, ninguna con una etiqueta que las ubicara. Con
 * una sola pieza compartida la jerarquía (etiqueta -> título -> bajada) y
 * el ritmo de entrada son idénticos en toda la página. */
export function EncabezadoSeccion({
  etiqueta,
  icono: Icono,
  titulo,
  tituloDestacado,
  descripcion,
  alineacion = "centro",
  tono = "terracota",
  className = "",
}: EncabezadoSeccionProps) {
  const centrado = alineacion === "centro";

  return (
    <motion.div
      variants={contenedorEscalonado(0.09)}
      initial="oculto"
      whileInView="visible"
      viewport={VIEWPORT_REVEAL}
      className={`${centrado ? "mx-auto max-w-2xl text-center" : "text-left"} ${className}`}
    >
      <motion.div
        variants={subirAlAparecer}
        className={`flex items-center gap-3 ${centrado ? "justify-center" : ""}`}
      >
        <motion.span
          initial={{ scale: 0.5, rotate: -18 }}
          whileInView={{ scale: 1, rotate: 0 }}
          viewport={VIEWPORT_REVEAL}
          transition={{ duration: 0.6, ease: EASE_PREMIUM, delay: 0.05 }}
          className={`flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl ${TONOS[tono]}`}
        >
          <Icono className="h-5 w-5" strokeWidth={1.75} />
        </motion.span>
        <span className="text-xs font-semibold tracking-[0.18em] text-pan-carbon-suave uppercase">
          {etiqueta}
        </span>
      </motion.div>

      <motion.h2
        variants={subirAlAparecer}
        className="equilibrar-texto mt-5 font-[family-name:var(--font-display-panaderia)] text-4xl leading-[1.1] font-semibold text-pan-carbon sm:text-5xl"
      >
        {titulo}
        {tituloDestacado && <> <span className="text-gradient-pan">{tituloDestacado}</span></>}
      </motion.h2>

      {descripcion && (
        <motion.p
          variants={subirAlAparecer}
          className={`mt-4 text-lg leading-relaxed text-pan-carbon-suave ${centrado ? "mx-auto max-w-xl" : "max-w-md"}`}
        >
          {descripcion}
        </motion.p>
      )}

      {/* Filete decorativo que cierra la cabecera: crece hasta su ancho al
          entrar en pantalla, en vez de aparecer ya dibujado. */}
      <motion.span
        initial={{ scaleX: 0, opacity: 0 }}
        whileInView={{ scaleX: 1, opacity: 1 }}
        viewport={VIEWPORT_REVEAL}
        transition={{ duration: 0.8, ease: EASE_PREMIUM, delay: 0.25 }}
        aria-hidden="true"
        className={`mt-7 block h-px ${
          centrado
            ? "mx-auto w-32 origin-center bg-gradient-to-r from-transparent via-pan-bronce to-transparent"
            : "w-24 origin-left bg-gradient-to-r from-pan-terracota via-pan-bronce to-transparent"
        }`}
      />
    </motion.div>
  );
}
