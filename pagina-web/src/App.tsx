import { Navbar } from "./components/Navbar";
import { Hero } from "./components/Hero";
import { BentoGrid } from "./components/BentoGrid";
import { DownloadSection } from "./components/DownloadSection";
import { Footer } from "./components/Footer";

function App() {
  return (
    <div className="min-h-screen bg-carbon-950">
      <Navbar />
      <main>
        <Hero />
        <BentoGrid />
        <DownloadSection />
      </main>
      <Footer />
    </div>
  );
}

export default App;
