import type { Variants } from "framer-motion";

/** La misma curva de easing premium que define `--ease-premium` en
 * index.css, para que lo que anima framer-motion y lo que anima CSS se
 * sientan exactamente igual. Antes estaba copiada a mano en cada
 * componente; ahora vive en un solo lugar. */
export const EASE_PREMIUM = [0.16, 1, 0.3, 1] as const;

/** Margen de disparo compartido por los reveals de scroll: el contenido
 * empieza a aparecer un poco ANTES de tocar el borde de la pantalla, así
 * nunca se ve "aparecer de golpe" a mitad de la sección. */
export const VIEWPORT_REVEAL = { once: true, margin: "-90px" } as const;

/** Contenedor que escalona la entrada de sus hijos. Al orquestar la
 * secuencia desde el padre (en vez de darle a cada hijo su propio `delay`
 * fijo) el ritmo se mantiene aunque cambie el número de elementos. */
export const contenedorEscalonado = (retrasoHijos = 0.08, retrasoInicial = 0): Variants => ({
  oculto: {},
  visible: {
    transition: { staggerChildren: retrasoHijos, delayChildren: retrasoInicial },
  },
});

/** Hijo estándar de un `contenedorEscalonado`: sube unos píxeles mientras
 * aparece. El desenfoque inicial es mínimo a propósito — da la sensación
 * de "enfocar" sin volverse un efecto llamativo. */
export const subirAlAparecer: Variants = {
  oculto: { opacity: 0, y: 22, filter: "blur(6px)" },
  visible: {
    opacity: 1,
    y: 0,
    filter: "blur(0px)",
    transition: { duration: 0.65, ease: EASE_PREMIUM },
  },
};
