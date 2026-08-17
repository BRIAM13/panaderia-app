import { Navbar } from "./components/Navbar";
import { ScrollProgress } from "./components/ScrollProgress";
import { Mascota } from "./components/Mascota";
import { Hero } from "./components/Hero";
import { Nosotros } from "./components/Nosotros";
import { Menu } from "./components/Menu";
import { PedidoForm } from "./components/PedidoForm";
import { SeguimientoPedido } from "./components/SeguimientoPedido";
import { Ubicacion } from "./components/Ubicacion";
import { Footer } from "./components/Footer";

function App() {
  return (
    <div className="min-h-screen bg-pan-crema">
      <ScrollProgress />
      <Navbar />
      <main>
        <Hero />
        <Nosotros />
        <Menu />
        <PedidoForm />
        <SeguimientoPedido />
        <Ubicacion />
      </main>
      <Footer />
      <Mascota />
    </div>
  );
}

export default App;
