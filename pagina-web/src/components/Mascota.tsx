import { useEffect, useRef, useState } from "react";
import { motion, AnimatePresence, useMotionValue, useSpring, useTransform } from "framer-motion";
import { EVENTO_PEDIDO_ENVIADO } from "../lib/eventos";

const EASE_PREMIUM = [0.16, 1, 0.3, 1] as const;

type Pose = "saluda" | "pensativo" | "senala" | "anima" | "despide" | "celebra";

// Qué sección de la página dispara qué gesto — así el personaje "reacciona"
// a medida que el visitante navega, en vez de solo inclinarse con el mouse.
const SECCION_A_POSE: Record<string, Pose> = {
  nosotros: "pensativo",
  menu: "senala",
  pedido: "anima",
  ubicacion: "despide",
};

const TRANSFORM_POR_POSE: Record<Pose, { rotate: number; scale: number }> = {
  saluda: { rotate: -4, scale: 1 },
  pensativo: { rotate: 3, scale: 0.98 },
  senala: { rotate: -6, scale: 1.02 },
  anima: { rotate: 4, scale: 1.03 },
  despide: { rotate: -4, scale: 1 },
  celebra: { rotate: 0, scale: 1.12 },
};

const FRASES_SALUDO = [
  "¡Hola! 👋",
  "¿Ya probaste nuestro pan?",
  "Recién horneado hoy 🍞",
  "¡Haz tu pedido!",
  "Pan de siempre, hecho en familia",
];

/** Mascota flotante fija en la esquina: saluda al entrar, se inclina hacia
 * el cursor, hace un gesto espontáneo cada tanto, cambia de pose según la
 * sección visible, celebra al confirmar un pedido, y responde al clic con
 * un mensaje — para que se sienta viva, no solo flotando. */
export function Mascota() {
  const [pose, setPose] = useState<Pose>("saluda");
  const [celebrando, setCelebrando] = useState(false);
  const [saludando, setSaludando] = useState(false);
  const [mensaje, setMensaje] = useState<string | null>(null);
  const celebrandoRef = useRef(false);
  const timeoutRef = useRef<number | undefined>(undefined);
  const mensajeTimeoutRef = useRef<number | undefined>(undefined);

  const cursorX = useMotionValue(0);
  const rotateCursor = useSpring(useTransform(cursorX, [-1, 1], [10, -10]), {
    stiffness: 120,
    damping: 14,
  });

  useEffect(() => {
    function alMoverMouse(e: MouseEvent) {
      const centro = window.innerWidth - 96;
      cursorX.set(Math.max(-1, Math.min(1, (e.clientX - centro) / 260)));
    }
    window.addEventListener("mousemove", alMoverMouse);
    return () => window.removeEventListener("mousemove", alMoverMouse);
  }, [cursorX]);

  useEffect(() => {
    celebrandoRef.current = celebrando;
  }, [celebrando]);

  useEffect(() => {
    const secciones = Object.keys(SECCION_A_POSE)
      .map((id) => document.getElementById(id))
      .filter((el): el is HTMLElement => el !== null);
    if (secciones.length === 0) return;

    const observer = new IntersectionObserver(
      (entradas) => {
        if (celebrandoRef.current) return;
        const masVisible = entradas
          .filter((e) => e.isIntersecting)
          .sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];
        if (masVisible) setPose(SECCION_A_POSE[masVisible.target.id] ?? "saluda");
      },
      { threshold: [0.3, 0.5, 0.7], rootMargin: "-15% 0px -15% 0px" },
    );
    secciones.forEach((el) => observer.observe(el));
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    function alConfirmarPedido() {
      window.clearTimeout(timeoutRef.current);
      setCelebrando(true);
      setPose("celebra");
      timeoutRef.current = window.setTimeout(() => setCelebrando(false), 2600);
    }
    window.addEventListener(EVENTO_PEDIDO_ENVIADO, alConfirmarPedido);
    return () => {
      window.removeEventListener(EVENTO_PEDIDO_ENVIADO, alConfirmarPedido);
      window.clearTimeout(timeoutRef.current);
    };
  }, []);

  // Gesto espontáneo cada 7-8s: el personaje saluda solo, aunque nadie
  // haga scroll ni le pase el mouse por encima — para que no se sienta
  // como una imagen estática flotando.
  useEffect(() => {
    const id = window.setInterval(() => {
      if (celebrandoRef.current) return;
      setSaludando(true);
      window.setTimeout(() => setSaludando(false), 900);
    }, 7500);
    return () => window.clearInterval(id);
  }, []);

  function alHacerClic() {
    window.clearTimeout(mensajeTimeoutRef.current);
    setMensaje(FRASES_SALUDO[Math.floor(Math.random() * FRASES_SALUDO.length)]);
    setSaludando(true);
    window.setTimeout(() => setSaludando(false), 700);
    mensajeTimeoutRef.current = window.setTimeout(() => setMensaje(null), 2200);
  }

  const transform = TRANSFORM_POR_POSE[pose];
  const agitado = celebrando || saludando;

  return (
    <div className="fixed bottom-5 right-5 z-50 sm:bottom-8 sm:right-8">
      <motion.div
        initial={{ opacity: 0, scale: 0.4, y: 40 }}
        animate={{ opacity: 1, scale: 1, y: [0, -14, 0] }}
        transition={{
          opacity: { duration: 0.5, delay: 0.5 },
          scale: { duration: 0.5, delay: 0.5, ease: EASE_PREMIUM },
          y: { duration: 2.2, repeat: Infinity, ease: "easeInOut", delay: 1 },
        }}
        style={{ rotate: rotateCursor }}
        className="relative h-24 w-auto sm:h-28"
      >
        <AnimatePresence>
          {mensaje && (
            <motion.div
              initial={{ opacity: 0, y: 8, scale: 0.85 }}
              animate={{ opacity: 1, y: 0, scale: 1 }}
              exit={{ opacity: 0, y: 8, scale: 0.85 }}
              transition={{ duration: 0.25, ease: EASE_PREMIUM }}
              className="absolute -top-2 right-0 -translate-y-full whitespace-nowrap rounded-2xl rounded-br-md bg-pan-crema-suave px-3.5 py-2 text-xs font-semibold text-pan-carbon shadow-lg shadow-pan-carbon/15"
            >
              {mensaje}
            </motion.div>
          )}
        </AnimatePresence>

        <motion.button
          type="button"
          onClick={alHacerClic}
          aria-label="Saludar al panadero de Panadería Ronceros"
          whileHover={{ scale: 1.06 }}
          whileTap={{ scale: 0.93 }}
          className="block cursor-pointer"
        >
          <motion.img
            src="/images/mascota/panadero.png"
            alt=""
            animate={{
              rotate: agitado
                ? [transform.rotate - 10, transform.rotate + 10, transform.rotate - 10]
                : transform.rotate,
              scale: celebrando ? transform.scale : saludando ? transform.scale * 1.05 : transform.scale,
              y: saludando && !celebrando ? [0, -10, 0] : 0,
            }}
            transition={{
              rotate: agitado
                ? { duration: 0.32, repeat: celebrando ? Infinity : 2, ease: "easeInOut" }
                : { duration: 0.6, ease: EASE_PREMIUM },
              scale: { duration: 0.4, ease: EASE_PREMIUM },
              y: { duration: 0.45, ease: EASE_PREMIUM },
            }}
            className="h-full w-auto drop-shadow-lg"
          />
        </motion.button>

        <AnimatePresence>{celebrando && <Confeti />}</AnimatePresence>
      </motion.div>
    </div>
  );
}

function Confeti() {
  const particulas = Array.from({ length: 8 });
  return (
    <>
      {particulas.map((_, i) => {
        const angulo = (i / particulas.length) * Math.PI * 2;
        const distancia = 44 + ((i * 7) % 18);
        return (
          <motion.span
            key={i}
            initial={{ opacity: 1, x: 0, y: 0, scale: 0.5, rotate: 0 }}
            animate={{
              opacity: 0,
              x: Math.cos(angulo) * distancia,
              y: Math.sin(angulo) * distancia - 18,
              scale: 1,
              rotate: (i % 2 === 0 ? 1 : -1) * 140,
            }}
            transition={{ duration: 1.1, ease: EASE_PREMIUM }}
            className="pointer-events-none absolute left-1/2 top-1/3 text-lg"
          >
            🍞
          </motion.span>
        );
      })}
    </>
  );
}
