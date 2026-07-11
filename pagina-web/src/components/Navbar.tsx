import { motion } from "framer-motion";
import { SITE } from "../data/config";

export function Navbar() {
  return (
    <motion.header
      initial={{ opacity: 0, y: -16 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.5, ease: [0.16, 1, 0.3, 1] }}
      className="fixed inset-x-0 top-0 z-50 border-b border-carbon-800/80 bg-carbon-950/70 backdrop-blur-md"
    >
      <div className="mx-auto flex max-w-6xl items-center justify-between px-6 py-4">
        <a href="#" className="font-[family-name:var(--font-display)] text-lg font-bold text-white">
          {SITE.nombre}
        </a>
        <a
          href="#descargar"
          className="rounded-full bg-white px-4 py-2 text-sm font-semibold text-carbon-950 transition-transform hover:scale-105"
        >
          Descargar
        </a>
      </div>
    </motion.header>
  );
}
