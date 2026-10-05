import { motion } from "framer-motion";
import { Bike, Check, Store } from "lucide-react";
import { EASE_PREMIUM } from "../utils/animacion";
import { COSTO_ENVIO_ESTIMADO, type TipoEntrega } from "../utils/entrega";

/** Mismo degradado que la opción "Tarjeta" del checkout
 * (`PagoCulqiSelectorMetodo`): carbón → terracota profundo → terracota. Para
 * el recojo, la tienda. */
const FONDO_RECOJO =
  "linear-gradient(135deg, var(--color-pan-carbon) 0%, var(--color-pan-terracota-profundo) 55%, var(--color-pan-terracota) 100%)";
/** Para el delivery, los tonos cálidos de la marca: bronce oscuro → bronce →
 * oro. Se distingue de un vistazo de la otra opción sin salirse de la paleta. */
const FONDO_DELIVERY =
  "linear-gradient(135deg, var(--color-pan-bronce-oscuro) 0%, var(--color-pan-bronce) 60%, var(--color-pan-oro) 100%)";

interface SelectorTipoEntregaProps {
  /** null = todavía no eligió. A propósito NINGUNA opción viene marcada por
   * defecto: es una decisión que cambia qué campos siguen y cuánto paga. */
  valor: TipoEntrega | null;
  onChange: (tipo: TipoEntrega) => void;
}

/**
 * "¿Cómo quieres recibir tu pedido?": dos tarjetas grandes, Recoger en tienda
 * y Delivery a domicilio. El mismo lenguaje que el selector de medio de pago
 * del checkout (ícono en cuadro con degradado + título + bajada), con una
 * diferencia: acá la elección SE QUEDA en pantalla —no lleva a otro paso—,
 * así que la opción elegida se marca (borde terracota + check) y se puede
 * cambiar tocando la otra.
 *
 * Solo aparece para Panadería (pan por unidad). El pan de hamburguesa no
 * tiene delivery y ni ve esto.
 */
export function SelectorTipoEntrega({ valor, onChange }: SelectorTipoEntregaProps) {
  return (
    <div role="group" aria-labelledby="titulo-tipo-entrega">
      <p id="titulo-tipo-entrega" className="mb-1.5 block text-sm font-medium text-pan-carbon">
        ¿Cómo quieres recibir tu pedido?
      </p>
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <OpcionEntrega
          titulo="Recoger en tienda"
          descripcion="Sin costo. Eliges el día y la hora."
          fondoIcono={FONDO_RECOJO}
          Icono={Store}
          elegida={valor === "RECOJO"}
          onClick={() => onChange("RECOJO")}
        />
        <OpcionEntrega
          titulo="Delivery a domicilio"
          // "aprox." a propósito: es el estimado de la web, el monto real lo
          // confirma el servidor al registrar el pedido.
          descripcion={`Solo en Pisco. Envío aprox. S/ ${COSTO_ENVIO_ESTIMADO.toFixed(2)}.`}
          fondoIcono={FONDO_DELIVERY}
          Icono={Bike}
          elegida={valor === "DELIVERY"}
          onClick={() => onChange("DELIVERY")}
        />
      </div>
    </div>
  );
}

interface OpcionEntregaProps {
  titulo: string;
  descripcion: string;
  fondoIcono: string;
  Icono: typeof Store;
  elegida: boolean;
  onClick: () => void;
}

/**
 * Una opción: ícono en cuadro con degradado, nombre, bajada y, a la derecha,
 * un círculo que se llena con un check al elegirla (en vez de la flecha
 * "esto lleva a otro paso" del selector de pago, porque acá no lleva a
 * ningún lado). Levanta y enciende el borde al pasar el mouse; elegida, el
 * borde queda terracota fijo y el fondo apenas más cálido.
 */
function OpcionEntrega({ titulo, descripcion, fondoIcono, Icono, elegida, onClick }: OpcionEntregaProps) {
  return (
    <motion.button
      type="button"
      onClick={onClick}
      aria-pressed={elegida}
      whileHover={{ y: -3 }}
      whileTap={{ scale: 0.98 }}
      transition={{ duration: 0.25, ease: EASE_PREMIUM }}
      className={`group flex min-h-20 w-full cursor-pointer items-center gap-4 rounded-2xl border p-4 text-left shadow-sm shadow-pan-carbon/5 transition-[border-color,box-shadow,background-color] duration-300 focus-visible:border-pan-terracota sm:p-5 ${
        elegida
          ? "border-pan-terracota bg-pan-terracota-suave/30 shadow-md shadow-pan-terracota/10"
          : "border-pan-borde/50 bg-pan-crema-suave hover:border-pan-terracota hover:shadow-lg hover:shadow-pan-terracota/15"
      }`}
    >
      <span
        aria-hidden="true"
        className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl text-pan-crema shadow-md shadow-pan-carbon/15 transition-transform duration-500 ease-[cubic-bezier(0.16,1,0.3,1)] group-hover:-rotate-6 group-hover:scale-110"
        style={{ background: fondoIcono }}
      >
        <Icono className="h-6 w-6" strokeWidth={1.75} />
      </span>
      <span className="min-w-0 flex-1">
        <span className="block text-base font-semibold text-pan-carbon">{titulo}</span>
        <span className="mt-0.5 block text-[13px] leading-snug text-pan-carbon-suave">{descripcion}</span>
      </span>
      {/* El "radio" dibujado a mano: vacío con borde fino, y al elegir se
          llena de terracota con el check entrando con un pequeño rebote. */}
      <span
        aria-hidden="true"
        className={`flex h-6 w-6 shrink-0 items-center justify-center rounded-full border-2 transition-colors duration-300 ${
          elegida ? "border-pan-terracota bg-pan-terracota text-pan-crema" : "border-pan-borde/60 bg-transparent"
        }`}
      >
        <motion.span
          initial={false}
          animate={{ scale: elegida ? 1 : 0, opacity: elegida ? 1 : 0 }}
          transition={{ type: "spring", stiffness: 420, damping: 20 }}
          className="flex"
        >
          <Check className="h-3.5 w-3.5" strokeWidth={3} />
        </motion.span>
      </span>
    </motion.button>
  );
}
