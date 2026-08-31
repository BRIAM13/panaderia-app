import { MotionConfig } from "framer-motion";
import { Navbar } from "./components/Navbar";
import { ScrollProgress } from "./components/ScrollProgress";
import { Hero } from "./components/Hero";
import { Nosotros } from "./components/Nosotros";
import { Menu } from "./components/Menu";
import { PedidoForm } from "./components/PedidoForm";
import { SeguimientoPedido } from "./components/SeguimientoPedido";
import { Ubicacion } from "./components/Ubicacion";
import { Footer } from "./components/Footer";

function App() {
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
          <Menu />
          <PedidoForm />
          <SeguimientoPedido />
          <Ubicacion />
        </main>
        <Footer />
      </div>
    </MotionConfig>
  );
}

export default App;
