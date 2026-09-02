import { motion } from "framer-motion";
import { EASE_PREMIUM } from "../utils/animacion";
import type { TipoDocumento } from "../hooks/useVerificacionDocumento";

const TIPOS = ["DNI", "RUC"] as const;

interface SelectorTipoDocumentoProps {
  valor: TipoDocumento;
  onChange: (tipo: TipoDocumento) => void;
  /** Cada instancia necesita el suyo: `layoutId` es global en framer-motion
   * y, con el mismo valor en dos selectores montados a la vez, el
   * indicador "vuela" de un selector al otro al cambiar de pestaña. */
  layoutId: string;
  /** El formulario de pedido vive sobre crema (borde visible); el panel de
   * seguimiento, sobre su propio degradado (fondo tenue, sin borde). */
  variante?: "contorno" | "relleno";
}

/** Las dos pestañas DNI / RUC con el indicador que se DESLIZA entre ellas
 * (layoutId) en vez de saltar de un botón al otro. Lo usan el formulario de
 * pedido y el buscador de pedidos, que hasta ahora repetían el mismo bloque
 * casi idéntico y podían quedar distintos al tocar solo uno. */
export function SelectorTipoDocumento({
  valor,
  onChange,
  layoutId,
  variante = "contorno",
}: SelectorTipoDocumentoProps) {
  return (
    <div
      role="radiogroup"
      aria-label="Tipo de documento"
      className={`inline-flex rounded-full p-1 ${
        variante === "contorno" ? "border border-pan-borde bg-pan-crema" : "bg-pan-borde/30"
      }`}
    >
      {TIPOS.map((tipo) => (
        <button
          key={tipo}
          type="button"
          role="radio"
          aria-checked={valor === tipo}
          onClick={() => onChange(tipo)}
          className={`relative min-h-10 rounded-full px-6 text-sm font-semibold transition-colors ${
            valor === tipo ? "text-pan-crema" : "text-pan-carbon-suave hover:text-pan-carbon"
          }`}
        >
          {valor === tipo && (
            <motion.span
              layoutId={layoutId}
              className="absolute inset-0 rounded-full bg-pan-terracota"
              transition={{ duration: 0.25, ease: EASE_PREMIUM }}
            />
          )}
          <span className="relative">{tipo}</span>
        </button>
      ))}
    </div>
  );
}
