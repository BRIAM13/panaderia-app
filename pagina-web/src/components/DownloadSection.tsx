import { motion } from "framer-motion";
import { PlatformCard } from "./PlatformCard";
import { useDetectOS } from "../hooks/useDetectOS";
import { PLATAFORMAS } from "../data/config";

const EASE_PREMIUM = [0.16, 1, 0.3, 1] as const;

export function DownloadSection() {
  const detectado = useDetectOS();

  return (
    <section id="descargar" className="border-t border-carbon-800 bg-carbon-950 px-6 py-28">
      <div className="mx-auto max-w-3xl">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, margin: "-100px" }}
          transition={{ duration: 0.6, ease: EASE_PREMIUM }}
          className="mb-12 text-center"
        >
          <span className="mb-4 inline-block rounded-full bg-carbon-800 px-4 py-1.5 text-xs font-medium tracking-wide text-carbon-400 uppercase">
            Para nuestro equipo
          </span>
          <h2 className="font-[family-name:var(--font-display)] text-4xl font-bold text-white sm:text-5xl">
            El sistema de <span className="text-gradient-neon">gestión.</span>
          </h2>
          <p className="mt-4 text-lg text-carbon-400">
            Esto es lo que usa nuestro personal para gestionar pedidos, deudas y pagos — no hace falta
            descargar nada para pedir tu pan, eso ya lo hiciste arriba.
          </p>
        </motion.div>

        <div className="flex flex-col gap-3">
          {PLATAFORMAS.map((plataforma, index) => (
            <motion.div
              key={plataforma.id}
              initial={{ opacity: 0, y: 16 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true, margin: "-60px" }}
              transition={{ duration: 0.5, ease: EASE_PREMIUM, delay: index * 0.06 }}
            >
              <PlatformCard plataforma={plataforma} destacado={detectado === plataforma.id} />
            </motion.div>
          ))}
        </div>
      </div>
    </section>
  );
}
