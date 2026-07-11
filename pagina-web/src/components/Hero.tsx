import { useState } from "react";
import { motion } from "framer-motion";
import { PlatformSelector } from "./PlatformSelector";
import { DeviceMockup } from "./DeviceMockup";
import { SITE } from "../data/config";
import type { OS } from "../data/config";

const EASE_PREMIUM = [0.16, 1, 0.3, 1] as const;

export function Hero() {
  const [os, setOs] = useState<OS>("web");

  return (
    <section className="grid-noise relative overflow-hidden border-b border-carbon-800 px-6 pt-28 pb-20 sm:pt-36">
      {/* Glow ambiental — decorativo, no interactivo */}
      <div className="pointer-events-none absolute top-0 left-1/2 h-[500px] w-[900px] -translate-x-1/2 rounded-full bg-cyber-violet/10 blur-[120px]" />

      <div className="relative mx-auto flex max-w-6xl flex-col items-center text-center">
        <motion.div
          initial={{ opacity: 0, y: 16 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, ease: EASE_PREMIUM }}
          className="mb-6 inline-flex items-center gap-2 rounded-full border border-carbon-700 bg-carbon-900 px-4 py-1.5 text-xs font-medium text-carbon-400"
        >
          <span className="h-1.5 w-1.5 rounded-full bg-neon-green shadow-[0_0_8px_2px_rgba(57,255,176,0.6)]" />
          {SITE.claim}
        </motion.div>

        <motion.h1
          initial={{ opacity: 0, y: 24 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.7, ease: EASE_PREMIUM, delay: 0.05 }}
          className="font-[family-name:var(--font-display)] text-5xl leading-[1.05] font-bold tracking-tight text-white sm:text-7xl"
        >
          Un sistema.
          <br />
          <span className="text-gradient-neon">Todos tus dispositivos.</span>
        </motion.h1>

        <motion.p
          initial={{ opacity: 0, y: 16 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, ease: EASE_PREMIUM, delay: 0.15 }}
          className="mt-6 max-w-xl text-lg text-carbon-400"
        >
          {SITE.descripcion}
        </motion.p>

        <motion.div
          initial={{ opacity: 0, y: 16 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, ease: EASE_PREMIUM, delay: 0.25 }}
          className="mt-10"
        >
          <PlatformSelector activo={os} onCambiar={setOs} />
        </motion.div>

        <motion.div
          initial={{ opacity: 0, scale: 0.96 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ duration: 0.7, ease: EASE_PREMIUM, delay: 0.3 }}
          className="mt-8 w-full"
        >
          <DeviceMockup os={os} />
        </motion.div>
      </div>
    </section>
  );
}
