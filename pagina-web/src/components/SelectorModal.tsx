import { useEffect } from "react";
import { createPortal } from "react-dom";
import { AnimatePresence, motion } from "framer-motion";

const EASE_PREMIUM = [0.16, 1, 0.3, 1] as const;

interface SelectorModalProps {
  abierto: boolean;
  titulo: string;
  onCancelar: () => void;
  onAceptar?: () => void;
  aceptarDeshabilitado?: boolean;
  /** false = sin pie de Cancelar/Aceptar — para listas donde elegir un
   * ítem ya aplica y cierra de una vez (ej. el selector de pan), en vez
   * del patrón de "borrador + Aceptar" de fecha/hora. */
  mostrarPie?: boolean;
  children: React.ReactNode;
}

/** Ventana emergente compartida por los selectores del formulario. Por
 * defecto sigue el patrón "borrador + Aceptar" (usado por SelectorFecha y
 * SelectorHora): el cliente arma su elección adentro y solo se aplica al
 * presionar "Aceptar" — "Cancelar" o tocar fuera descarta el borrador y
 * deja el valor que ya estaba. Con `mostrarPie={false}` (ej. el selector
 * de pan) no hay borrador: cada clic en un ítem ya aplica y cierra.
 *
 * Se renderiza vía portal directo a `document.body`: si quedara anidado
 * dentro de un ancestro con `transform` (ej. cualquier `motion.div` de
 * framer-motion ya animado), ese ancestro se vuelve el "contenedor" del
 * `position: fixed` y la ventana emergente queda comprimida a su alto en
 * vez de cubrir toda la pantalla — un portal la saca de ese árbol por
 * completo, sin importar dónde se use este componente. */
export function SelectorModal({
  abierto,
  titulo,
  onCancelar,
  onAceptar,
  aceptarDeshabilitado,
  mostrarPie = true,
  children,
}: SelectorModalProps) {
  useEffect(() => {
    if (!abierto) return;
    const original = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = original;
    };
  }, [abierto]);

  return createPortal(
    <AnimatePresence>
      {abierto && (
        <motion.div
          key="fondo"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          transition={{ duration: 0.18 }}
          className="fixed inset-0 z-50 flex items-end justify-center bg-pan-carbon/50 backdrop-blur-sm sm:items-center sm:p-4"
          onClick={onCancelar}
        >
          <motion.div
            key="panel"
            initial={{ opacity: 0, y: 28, scale: 0.97 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 28, scale: 0.97 }}
            transition={{ duration: 0.22, ease: EASE_PREMIUM }}
            onClick={(e) => e.stopPropagation()}
            className="w-full max-w-sm rounded-t-3xl border border-pan-borde/60 bg-pan-crema-suave p-5 pb-6 shadow-2xl shadow-pan-carbon/25 sm:rounded-3xl sm:pb-5"
          >
            <p className="mb-4 text-center text-xs font-semibold tracking-wide text-pan-carbon-suave uppercase">
              {titulo}
            </p>

            {children}

            {mostrarPie && (
              <div className="mt-5 flex gap-3">
                <button
                  type="button"
                  onClick={onCancelar}
                  className="flex-1 rounded-full border border-pan-borde py-2.5 text-sm font-semibold text-pan-carbon-suave transition-colors hover:text-pan-carbon"
                >
                  Cancelar
                </button>
                <button
                  type="button"
                  onClick={onAceptar}
                  disabled={aceptarDeshabilitado}
                  className="flex-1 rounded-full bg-pan-terracota py-2.5 text-sm font-semibold text-pan-crema transition-opacity hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-50"
                >
                  Aceptar
                </button>
              </div>
            )}
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>,
    document.body,
  );
}
