import { useEffect, useId, useRef } from "react";
import { createPortal } from "react-dom";
import { AnimatePresence, motion } from "framer-motion";
import { EASE_PREMIUM } from "../utils/animacion";

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
 * completo, sin importar dónde se use este componente.
 *
 * Accesibilidad: se anuncia como diálogo modal, se cierra con Escape, el
 * foco entra al panel al abrirse y vuelve al botón que lo abrió al
 * cerrarse, y el tabulador no se escapa al formulario de atrás. Sin esto,
 * quien navegaba con teclado seguía tabulando por la página que quedaba
 * debajo del modal, sin forma de cerrarlo con el teclado. */
export function SelectorModal({
  abierto,
  titulo,
  onCancelar,
  onAceptar,
  aceptarDeshabilitado,
  mostrarPie = true,
  children,
}: SelectorModalProps) {
  const panelRef = useRef<HTMLDivElement>(null);
  const elementoPrevioRef = useRef<HTMLElement | null>(null);
  const tituloId = useId();

  useEffect(() => {
    if (!abierto) return;
    const original = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = original;
    };
  }, [abierto]);

  useEffect(() => {
    if (!abierto) return;
    elementoPrevioRef.current = document.activeElement as HTMLElement | null;
    // Un cuadro de espera para que el panel ya exista en el DOM (la
    // animación de entrada de AnimatePresence lo monta en este mismo
    // ciclo) antes de intentar enfocarlo.
    const id = window.requestAnimationFrame(() => panelRef.current?.focus());
    return () => {
      window.cancelAnimationFrame(id);
      elementoPrevioRef.current?.focus?.();
    };
  }, [abierto]);

  useEffect(() => {
    if (!abierto) return;
    function alPresionar(e: KeyboardEvent) {
      if (e.key === "Escape") {
        e.stopPropagation();
        onCancelar();
        return;
      }
      if (e.key !== "Tab") return;
      const panel = panelRef.current;
      if (!panel) return;
      const enfocables = panel.querySelectorAll<HTMLElement>(
        'a[href], button:not([disabled]), input, select, textarea, [tabindex]:not([tabindex="-1"])',
      );
      if (enfocables.length === 0) {
        e.preventDefault();
        panel.focus();
        return;
      }
      const primero = enfocables[0];
      const ultimo = enfocables[enfocables.length - 1];
      const activo = document.activeElement;
      // El foco da la vuelta dentro del panel en vez de salirse a la
      // página de atrás, que sigue visible pero ya no es operable.
      if (e.shiftKey && (activo === primero || activo === panel)) {
        e.preventDefault();
        ultimo.focus();
      } else if (!e.shiftKey && activo === ultimo) {
        e.preventDefault();
        primero.focus();
      }
    }
    window.addEventListener("keydown", alPresionar, true);
    return () => window.removeEventListener("keydown", alPresionar, true);
  }, [abierto, onCancelar]);

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
            ref={panelRef}
            role="dialog"
            aria-modal="true"
            aria-labelledby={tituloId}
            tabIndex={-1}
            initial={{ opacity: 0, y: 28, scale: 0.97 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 28, scale: 0.97 }}
            transition={{ duration: 0.22, ease: EASE_PREMIUM }}
            onClick={(e) => e.stopPropagation()}
            className="w-full max-w-sm rounded-t-3xl border border-pan-borde/60 bg-pan-crema-suave p-5 pb-6 shadow-2xl shadow-pan-carbon/25 outline-none sm:rounded-3xl sm:pb-5"
          >
            {/* Agarradera visual: en móvil el panel entra desde abajo como
                una hoja, y esta barrita comunica que se trata de una capa
                sobre el formulario. */}
            <span
              aria-hidden="true"
              className="mx-auto mb-3 block h-1 w-10 rounded-full bg-pan-borde/45 sm:hidden"
            />
            <p
              id={tituloId}
              className="mb-4 text-center text-xs font-semibold tracking-[0.16em] text-pan-carbon-suave uppercase"
            >
              {titulo}
            </p>

            {children}

            {mostrarPie && (
              <div className="mt-5 flex gap-3">
                <button
                  type="button"
                  onClick={onCancelar}
                  className="boton-relleno flex-1 rounded-full border border-pan-borde py-2.5 text-sm font-semibold text-pan-carbon-suave"
                  style={
                    {
                      "--color-relleno": "var(--color-pan-crema-muted)",
                      "--color-relleno-texto": "var(--color-pan-carbon)",
                    } as React.CSSProperties
                  }
                >
                  Cancelar
                </button>
                <button
                  type="button"
                  onClick={onAceptar}
                  disabled={aceptarDeshabilitado}
                  className="flex-1 rounded-full bg-pan-terracota py-2.5 text-sm font-semibold text-pan-crema shadow-sm shadow-pan-terracota/25 transition-all duration-300 hover:shadow-md hover:shadow-pan-terracota/35 disabled:cursor-not-allowed disabled:opacity-50 disabled:shadow-none"
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
