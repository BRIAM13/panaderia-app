import { motion } from "framer-motion";
import { enlaceWhatsApp } from "../data/config";
import { EASE_PREMIUM } from "../utils/animacion";
import { IconoWhatsApp } from "./IconoWhatsApp";

/** Botón flotante para escribirle a la panadería sin tener que buscar el
 * número ni bajar hasta el pie de página. Es la vía real de contacto del
 * negocio: acá se responde a mano, no es un chatbot.
 *
 * Detalles de ubicación que sí importan:
 *  - `z-40`, por debajo del navbar y de las hojas emergentes (z-50): con un
 *    selector de fecha/hora abierto, el botón queda detrás del velo, no
 *    flotando sobre un diálogo modal.
 *  - El margen inferior descuenta la barra de gestos del iPhone
 *    (safe-area-inset-bottom): sin eso, en pantalla completa el botón queda
 *    justo debajo de la barra del sistema y no se puede tocar.
 *  - Esquina inferior DERECHA: el menú de navegación se despliega desde
 *    arriba y la flecha de "bajar" del inicio va centrada, así que no se
 *    cruza con ninguno de los dos. */
export function BotonWhatsApp() {
  return (
    <motion.a
      href={enlaceWhatsApp()}
      target="_blank"
      rel="noopener noreferrer"
      initial={{ opacity: 0, scale: 0.6, y: 12 }}
      animate={{ opacity: 1, scale: 1, y: 0 }}
      transition={{ duration: 0.5, ease: EASE_PREMIUM, delay: 1.1 }}
      whileHover={{ scale: 1.06, y: -2 }}
      whileTap={{ scale: 0.95 }}
      aria-label="Escríbenos por WhatsApp"
      className="group fixed right-5 bottom-[max(1.25rem,calc(env(safe-area-inset-bottom)+0.75rem))] z-40 flex h-14 items-center gap-0 rounded-full bg-gradient-to-br from-pan-terracota to-pan-terracota-profundo pr-0 pl-0 text-pan-crema shadow-lg shadow-pan-terracota/35 transition-shadow duration-300 hover:shadow-xl hover:shadow-pan-terracota/45 sm:right-8"
    >
      {/* El ícono siempre ocupa un cuadro de 56px (el círculo completo) y la
          etiqueta se despliega a su izquierda solo con el mouse encima: en
          celular sería una barra permanente tapando contenido, y en
          escritorio un círculo suelto no dice a qué lleva. El texto se anima
          con ancho/opacidad, no montándose y desmontándose, para que la
          transición sea continua en los dos sentidos. */}
      <span className="max-w-0 overflow-hidden whitespace-nowrap text-sm font-semibold transition-[max-width,padding] duration-500 ease-[cubic-bezier(0.16,1,0.3,1)] group-hover:max-w-[12rem] group-hover:pl-5 group-focus-visible:max-w-[12rem] group-focus-visible:pl-5">
        Escríbenos
      </span>
      <span className="flex h-14 w-14 shrink-0 items-center justify-center">
        {/* Halo que late una vez cada tanto, para que el botón se note sin
            volverse una animación permanente que distraiga. */}
        <span
          aria-hidden="true"
          className="absolute inset-y-0 right-0 w-14 animate-ping rounded-full bg-pan-terracota/25 [animation-duration:3.5s]"
        />
        <IconoWhatsApp className="relative h-7 w-7" />
      </span>
    </motion.a>
  );
}
