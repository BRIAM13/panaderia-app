import { motion } from "framer-motion";
import { BentoCard } from "./BentoCard";
import { FEATURES } from "../data/config";

const EASE_PREMIUM = [0.16, 1, 0.3, 1] as const;

export function BentoGrid() {
  return (
    <section id="funciones" className="mx-auto max-w-6xl px-6 py-28">
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        whileInView={{ opacity: 1, y: 0 }}
        viewport={{ once: true, margin: "-100px" }}
        transition={{ duration: 0.6, ease: EASE_PREMIUM }}
        className="mb-14 max-w-2xl"
      >
        <h2 className="font-[family-name:var(--font-display)] text-4xl font-bold text-white sm:text-5xl">
          Hecho para operar
          <span className="text-gradient-neon"> de verdad.</span>
        </h2>
        <p className="mt-4 text-lg text-carbon-400">
          Cada bloque de acá corre hoy en producción — no son mockups de una idea futura.
        </p>
      </motion.div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        {FEATURES.map((feature, index) => (
          <BentoCard key={feature.id} feature={feature} index={index} />
        ))}
      </div>
    </section>
  );
}
