import { Navbar } from "./components/Navbar";
import { Hero } from "./components/Hero";
import { Nosotros } from "./components/Nosotros";
import { Menu } from "./components/Menu";
import { PedidoForm } from "./components/PedidoForm";
import { Ubicacion } from "./components/Ubicacion";
import { DownloadSection } from "./components/DownloadSection";
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
        <Ubicacion />
        <DownloadSection />
      </main>
      <Footer />
    </div>
  );
}

export default App;
