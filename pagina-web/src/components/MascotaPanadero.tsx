import { useEffect, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { EASE_PREMIUM } from "../utils/animacion";

// UNA sola frase, siempre la misma. El personaje ya saluda solo, sin parar,
// así que el globo no tiene que llamar la atención: solo deja dicho, una
// vez y para siempre, lo único que importa — que abajo se hace el pedido.
// Corta a propósito: en celular el globo se acota a 15rem y en pantalla
// grande va en una sola línea (whitespace-nowrap), así que no debería pasar
// de unos 34 caracteres. Y no promete nada que el sitio no haga: se recoge
// en la tienda, se paga ahí, y no hace falta cuenta.
const MENSAJE_SALUDO = "Te ayudo con tu pedido 👇";
const MENSAJE_CELEBRACION = "¡Gracias! Te lo separamos 🎉";
// Deja terminar de entrar a la cabecera de la sección antes de que aparezca
// el globo: los dos a la vez se pisan.
const RETRASO_GLOBO_MS = 700;

interface MascotaPanaderoProps {
  /** Se pone en true cuando la sección de pedidos entra en pantalla (y ya
   * no vuelve a false): a partir de ahí aparece el globo con la frase. El
   * saludo del personaje NO depende de esto — el clip está siempre en
   * bucle, igual que en el login de la app. */
  anunciar: boolean;
  /** Se pone en true al confirmarse el pedido: el globo cambia de frase. No
   * hay un gesto distinto para festejar (en la app solo existen el saludo y
   * el reposo), así que el personaje sigue saludando debajo. */
  celebrando: boolean;
}

/** El panadero que asoma sobre el formulario, con el MISMO saludo que la
 * pantalla de login de la app: `saludo.webp` es un WebP animado de 179
 * cuadros a 24fps (7,458s de ciclo) armado a partir de
 * `assets/mascota/frames_saludo/`, los mismos archivos que allá cicla el
 * widget `MascotaVideo` en `ModoMascota.soloSaludo`. El navegador lo
 * decodifica y lo repite solo, sin una línea de JavaScript: el personaje
 * saluda una y otra vez, sin pasar nunca a reposo. La secuencia ya viene
 * recortada para que el paso del último cuadro al primero se lea como un
 * paso más del gesto, así que el bucle no tiene costura visible.
 *
 * El archivo NO es una recompresión de esos cuadros: se armó copiando tal
 * cual los datos comprimidos de cada WebP (sus chunks ALPH y VP8) dentro de
 * un contenedor animado, así que lo que se ve acá son exactamente los mismos
 * píxeles que muestra la app, cuadro por cuadro. Cualquier recompresión
 * —incluso a calidad alta— se notaba como "no es el mismo clip", y encima
 * pesaba MÁS que copiar los originales.
 *
 * La separación contra el crema de la tarjeta la da el contorno mocha
 * semitransparente que los propios cuadros ya traen horneado (viene del
 * render, no de un CSS que lo imite): por eso acá no hay ni borde ni sombra
 * dibujados encima, igual que en la app.
 *
 * Lo único que este componente maneja es el globo de diálogo. Antes vivía
 * acá toda una coreografía de temporizadores (un meneo de CSS cada 7s con su
 * frase, que era el "saludo") porque una imagen fija no se mueve sola; con
 * un clip que se mueve de verdad esa maquinaria sobra. */
export function MascotaPanadero({ anunciar, celebrando }: MascotaPanaderoProps) {
  const [globoVisible, setGloboVisible] = useState(false);
  // Cada toque al personaje vuelve a montar el globo para que repita su
  // animación de entrada: es el acuse de recibo del clic, ya que el saludo
  // en sí no puede "hacerse más" — nunca se detiene.
  const [latido, setLatido] = useState(0);

  useEffect(() => {
    if (!anunciar) return;
    const id = window.setTimeout(() => setGloboVisible(true), RETRASO_GLOBO_MS);
    return () => window.clearTimeout(id);
  }, [anunciar]);

  // El mensaje no se apaga solo: mientras se llena el formulario la frase
  // que corresponde es la del saludo, y desde que el pedido entra la que
  // corresponde es la del festejo (al lado del resumen de confirmación, que
  // es lo que la tarjeta muestra a partir de ahí).
  const mensaje = celebrando ? MENSAJE_CELEBRACION : MENSAJE_SALUDO;

  return (
    <>
      <AnimatePresence mode="wait">
        {globoVisible && (
          <motion.div
            key={`${mensaje}-${latido}`}
            initial={{ opacity: 0, y: 8, scale: 0.85 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 8, scale: 0.85 }}
            transition={{ duration: 0.25, ease: EASE_PREMIUM }}
            // La frase ronda los 190px: en un celular de 375px cabe, pero
            // con un texto un poco más largo (el del festejo, o el día que
            // se cambie el saludo) se saldría de la pantalla por la
            // izquierda. Acotado y con salto de línea permitido en celular,
            // el globo crece hacia abajo en vez de hacia afuera.
            //
            // El `-top` es el mismo que el del personaje: el globo apoya
            // justo sobre el gorro.
            className="absolute -top-24 right-6 z-10 max-w-[15rem] -translate-y-full rounded-2xl rounded-br-md bg-pan-crema-suave px-3.5 py-2 text-xs font-semibold text-pan-carbon shadow-lg shadow-pan-carbon/15 sm:-top-32 sm:right-10 sm:max-w-none sm:whitespace-nowrap"
          >
            {mensaje}
          </motion.div>
        )}
      </AnimatePresence>

      {/* Sin `initial`/`whileInView` propios: la entrada la maneja el div
          que envuelve a la mascota Y a la tarjeta (ver PedidoForm), para que
          los dos aparezcan en el mismo movimiento. Cuando cada uno tenía su
          propio disparador de scroll, el panadero —que está más arriba en la
          página— cruzaba el umbral antes y aparecía solo, con el formulario
          llegando después. */}
      <motion.button
        type="button"
        onClick={() => {
          setGloboVisible(true);
          setLatido((n) => n + 1);
        }}
        aria-label="Saludar al panadero"
        whileHover={{ scale: 1.05 }}
        whileTap={{ scale: 0.95 }}
        transition={{ duration: 0.25, ease: EASE_PREMIUM }}
        className="absolute -top-24 right-6 z-0 cursor-pointer rounded-2xl sm:-top-32 sm:right-10"
      >
        <img
          src="/images/mascota/saludo.webp"
          alt=""
          // Medidas reales del clip (las mismas de los cuadros de la app) —
          // van declaradas para que el navegador reserve el hueco antes de
          // descargarlo y no haya salto de maquetación.
          width={350}
          height={448}
          // Pesa ~3,7MB: son 179 cuadros de verdad, sin recomprimir, no un
          // truco de CSS. Va en diferido a propósito — la mascota vive muy
          // por debajo del pliegue, así que no compite con la primera
          // pantalla; el navegador la pide cuando el visitante se acerca a
          // la sección.
          loading="lazy"
          decoding="async"
          // El encuadre es de medio cuerpo, así que la mitad de arriba del
          // clip (gorro, cara y la mano que saluda) es justo lo que asoma
          // por encima de la tarjeta: el `-top` de acá recorta a esa altura
          // — 96px en celular sobre 176 de alto, 128 sobre 240 desde sm—.
          // Menos asomo y la mano quedaba cortada a mitad del saludo, que
          // era lo único que había que ver.
          className="h-44 w-auto sm:h-60"
        />
      </motion.button>
    </>
  );
}
