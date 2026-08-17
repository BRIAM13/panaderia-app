import { motion, useScroll, useSpring } from "framer-motion";

/** Barra delgada bajo el navbar que crece con el avance del scroll — un
 * detalle de página profesional que además le da al visitante una
 * referencia visual de cuánto le falta. `useSpring` suaviza el avance para
 * que no se sienta "a saltos" al hacer scroll rápido. */
export function ScrollProgress() {
  const { scrollYProgress } = useScroll();
  const progreso = useSpring(scrollYProgress, {
    stiffness: 220,
    damping: 30,
    restDelta: 0.001,
  });

  return (
    <motion.div
      style={{ scaleX: progreso }}
      className="fixed inset-x-0 top-0 z-[60] h-[3px] origin-left bg-gradient-to-r from-pan-terracota via-pan-oro to-pan-bronce"
    />
  );
}
