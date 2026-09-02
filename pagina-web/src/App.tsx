import { Suspense, lazy, useState } from "react";
import { MotionConfig } from "framer-motion";
import { Navbar } from "./components/Navbar";
import { ScrollProgress } from "./components/ScrollProgress";
import { Hero } from "./components/Hero";
import { Nosotros } from "./components/Nosotros";
import { Menu } from "./components/Menu";
import { ComoFunciona } from "./components/ComoFunciona";
import { PedidoForm } from "./components/PedidoForm";
import { Ubicacion } from "./components/Ubicacion";
import { Footer } from "./components/Footer";
import { BotonWhatsApp } from "./components/BotonWhatsApp";
import { useCatalogoPublico } from "./hooks/useCatalogoPublico";

// Dos bloques que casi nadie necesita al abrir la página: el buscador de
// pedidos (solo le sirve a quien ya pidió antes) y las preguntas
// frecuentes. Van en su propio archivo descargable aparte para que no
// pesen sobre la primera carga, que es la que decide si el visitante se
// queda. Al ir bien abajo, la descarga arranca mientras todavía está
// leyendo lo de arriba.
const SeguimientoPedido = lazy(() =>
  import("./components/SeguimientoPedido").then((m) => ({ default: m.SeguimientoPedido })),
);
const PreguntasFrecuentes = lazy(() =>
  import("./components/PreguntasFrecuentes").then((m) => ({ default: m.PreguntasFrecuentes })),
);

/** Hueco del mismo tamaño y forma que el bloque que se está descargando —
 * el mismo esqueleto con barrido que ya usan el selector de pan y el panel
 * de seguimiento, para que la espera se vea igual en toda la página y el
 * layout no dé un salto al llegar el contenido. */
function EsqueletoSeccion({ className }: { className?: string }) {
  return (
    <div className="px-6 py-16" aria-hidden="true">
      <div className={`esqueleto mx-auto max-w-4xl rounded-3xl ${className ?? ""}`} />
    </div>
  );
}

function App() {
  // El catálogo (precios + horarios) se pide UNA vez acá y se reparte: el
  // menú, el formulario, las preguntas frecuentes y la ficha de "Visítanos"
  // leen todos del mismo fetch. Antes solo lo pedía el formulario, así que
  // el menú de arriba no tenía precios que mostrar y el horario de la
  // tienda no aparecía en ninguna parte fuera del formulario.
  const [pedidoEnviado, setPedidoEnviado] = useState(false);
  const catalogo = useCatalogoPublico({ pausado: pedidoEnviado });

  return (
    // reducedMotion="user" hace que TODA animación de framer-motion del
    // sitio se desactive sola si el visitante pidió menos movimiento en su
    // sistema — incluidas las derivas de fondo y los reveals al hacer
    // scroll, que son las que peor sientan a quien tiene sensibilidad al
    // movimiento. El CSS equivalente vive en index.css.
    <MotionConfig reducedMotion="user">
      <div className="min-h-screen bg-pan-crema">
        <a href="#contenido" className="salto-contenido">
          Saltar al contenido
        </a>
        <ScrollProgress />
        <Navbar />
        <main id="contenido">
          <Hero />
          <Nosotros />
          <Menu catalogo={catalogo} />
          <ComoFunciona />
          <PedidoForm catalogo={catalogo} onPedidoEnviado={setPedidoEnviado} />
          <Suspense fallback={<EsqueletoSeccion className="h-48" />}>
            <SeguimientoPedido />
          </Suspense>
          <Suspense fallback={<EsqueletoSeccion className="h-96" />}>
            <PreguntasFrecuentes horarios={catalogo.horarios} />
          </Suspense>
          <Ubicacion horarios={catalogo.horarios} />
        </main>
        <Footer />
        <BotonWhatsApp />
      </div>
    </MotionConfig>
  );
}

export default App;
