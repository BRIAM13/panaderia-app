import { Navbar } from "./components/Navbar";
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
    </div>
  );
}

export default App;
