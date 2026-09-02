import { useEffect, useRef, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { EASE_PREMIUM } from "../utils/animacion";

const FRASES_SALUDO = [
  "¡Hola! 👋",
  "¿Ya probaste nuestro pan?",
  "Recién horneado hoy 🍞",
  "¡Haz tu pedido!",
  "Pan de siempre, hecho en familia",
];

const MENSAJE_BIENVENIDA = "Realiza tu pedido aquí 👇";
// Deja terminar de entrar a la cabecera de la sección antes de que aparezca
// el globo: los dos a la vez se pisan.
const RETRASO_BIENVENIDA_MS = 700;

interface MascotaPanaderoProps {
  /** Se pone en true cuando la sección de pedidos entra en pantalla: el
   * panadero saluda solo, una vez. */
  anunciar: boolean;
  /** Se pone en true al confirmarse el pedido: el personaje festeja un
   * instante. Es un gesto puntual, no un bucle que siga solo. */
  celebrando: boolean;
}

/** El panadero que asoma sobre el formulario: saluda al entrar la sección,
 * responde con una frase distinta cada vez que lo tocan y festeja cuando el
 * pedido se confirma. Todo su estado (globo, temporizadores, meneo) vive
 * acá dentro; el formulario solo le dice CUÁNDO pasa algo. */
export function MascotaPanadero({ anunciar, celebrando }: MascotaPanaderoProps) {
  const [agitada, setAgitada] = useState(false);
  const [mensaje, setMensaje] = useState<string | null>(null);
  const mensajeTimeoutRef = useRef<number | undefined>(undefined);
  const agitadoTimeoutRef = useRef<number | undefined>(undefined);

  // Un disparador nuevo siempre interrumpe el mensaje anterior en vez de
  // sumarse: sin cancelar el temporizador pendiente, el cierre del mensaje
  // viejo apagaba el mensaje nuevo antes de tiempo.
  function mostrarMensaje(texto: string, duracionMs = 2200) {
    window.clearTimeout(mensajeTimeoutRef.current);
    setMensaje(texto);
    mensajeTimeoutRef.current = window.setTimeout(() => setMensaje(null), duracionMs);
  }

  function saludar() {
    window.clearTimeout(agitadoTimeoutRef.current);
    setAgitada(true);
    agitadoTimeoutRef.current = window.setTimeout(() => setAgitada(false), 650);
    mostrarMensaje(FRASES_SALUDO[Math.floor(Math.random() * FRASES_SALUDO.length)]);
  }

  useEffect(() => {
    if (!anunciar) return;
    const id = window.setTimeout(() => mostrarMensaje(MENSAJE_BIENVENIDA, 4000), RETRASO_BIENVENIDA_MS);
    return () => window.clearTimeout(id);
  }, [anunciar]);

  useEffect(() => {
    if (!celebrando) return;
    setAgitada(true);
    const id = window.setTimeout(() => setAgitada(false), 1400);
    return () => window.clearTimeout(id);
  }, [celebrando]);

  useEffect(
    () => () => {
      window.clearTimeout(mensajeTimeoutRef.current);
      window.clearTimeout(agitadoTimeoutRef.current);
    },
    [],
  );

  return (
    <>
      <AnimatePresence>
        {mensaje && (
          <motion.div
            initial={{ opacity: 0, y: 8, scale: 0.85 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 8, scale: 0.85 }}
            transition={{ duration: 0.25, ease: EASE_PREMIUM }}
            // La frase más larga del saludo ronda los 220px: en un celular
            // de 375px cabe por poco, pero con un texto nuevo un poco más
            // largo se saldría de la pantalla por la izquierda. Acotado y
            // con salto de línea permitido en celular, el globo crece hacia
            // abajo en vez de hacia afuera.
            className="absolute -top-14 right-6 z-10 max-w-[15rem] -translate-y-full rounded-2xl rounded-br-md bg-pan-crema-suave px-3.5 py-2 text-xs font-semibold text-pan-carbon shadow-lg shadow-pan-carbon/15 sm:-top-20 sm:right-10 sm:max-w-none sm:whitespace-nowrap"
          >
            {mensaje}
          </motion.div>
        )}
      </AnimatePresence>

      <motion.button
        type="button"
        onClick={saludar}
        aria-label="Saludar al panadero"
        initial={{ opacity: 0, y: 20, rotate: -8 }}
        whileInView={{ opacity: 1, y: 0, rotate: -6 }}
        viewport={{ once: true, margin: "-80px" }}
        whileHover={{ scale: 1.05 }}
        whileTap={{ scale: 0.95 }}
        animate={agitada ? { rotate: [-4, 6, -4, 6, -6] } : { rotate: -6 }}
        transition={
          agitada ? { duration: 0.55, ease: "easeInOut" } : { duration: 0.5, ease: EASE_PREMIUM }
        }
        className="absolute -top-14 right-6 z-0 cursor-pointer rounded-2xl sm:-top-20 sm:right-10"
      >
        <img
          src="/images/mascota/panadero.png"
          alt=""
          width={325}
          height={480}
          className="h-28 w-auto drop-shadow-lg sm:h-40"
        />
      </motion.button>
    </>
  );
}
