import { useRef } from "react";
import { useMotionValue, useSpring, useTransform } from "framer-motion";

/**
 * Inclinación 3D sutil que sigue al mouse dentro de la tarjeta — el efecto
 * "tilt" del bento grid. Se apoya en springs de Framer Motion para que el
 * regreso al reposo se sienta elástico, no un salto brusco.
 */
export function useTilt(intensidad = 10) {
  const ref = useRef<HTMLDivElement>(null);
  const x = useMotionValue(0);
  const y = useMotionValue(0);

  const spring = { stiffness: 150, damping: 20, mass: 0.5 };
  const rotateX = useSpring(useTransform(y, [-0.5, 0.5], [intensidad, -intensidad]), spring);
  const rotateY = useSpring(useTransform(x, [-0.5, 0.5], [-intensidad, intensidad]), spring);

  function onMouseMove(e: React.MouseEvent<HTMLDivElement>) {
    const el = ref.current;
    if (!el) return;
    const rect = el.getBoundingClientRect();
    x.set((e.clientX - rect.left) / rect.width - 0.5);
    y.set((e.clientY - rect.top) / rect.height - 0.5);
  }

  function onMouseLeave() {
    x.set(0);
    y.set(0);
  }

  return { ref, rotateX, rotateY, onMouseMove, onMouseLeave };
}
