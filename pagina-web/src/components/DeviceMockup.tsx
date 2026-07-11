import { AnimatePresence, motion } from "framer-motion";
import type { OS } from "../data/config";

// Dimensiones/forma "objetivo" por plataforma — lo que hace que el marco
// se sienta como un teléfono, un navegador o una laptop al cambiar de tab.
const FORMA: Record<OS, { width: number; height: number; radius: number; tipo: "movil" | "ventana" }> = {
  android: { width: 220, height: 460, radius: 34, tipo: "movil" },
  ios: { width: 220, height: 460, radius: 44, tipo: "movil" },
  windows: { width: 480, height: 320, radius: 12, tipo: "ventana" },
  macos: { width: 480, height: 320, radius: 14, tipo: "ventana" },
  web: { width: 520, height: 340, radius: 16, tipo: "ventana" },
};

const EASE_PREMIUM = [0.16, 1, 0.3, 1] as const;

export function DeviceMockup({ os }: { os: OS }) {
  const forma = FORMA[os];

  return (
    <div className="flex h-[500px] w-full items-center justify-center [perspective:1200px]">
      <motion.div
        animate={{
          width: forma.width,
          height: forma.height,
          borderRadius: forma.radius,
        }}
        transition={{ duration: 0.65, ease: EASE_PREMIUM }}
        className="relative flex flex-col overflow-hidden border border-carbon-600 bg-carbon-800 shadow-[0_0_80px_-20px_rgba(57,255,176,0.25)]"
      >
        {/* Barra superior: notch de teléfono o titlebar de ventana */}
        {forma.tipo === "movil" ? (
          <div className="flex h-7 shrink-0 items-center justify-center bg-carbon-900">
            <div className="h-1.5 w-16 rounded-full bg-carbon-700" />
          </div>
        ) : (
          <div className="flex h-8 shrink-0 items-center gap-1.5 bg-carbon-900 px-3">
            <span className="h-2.5 w-2.5 rounded-full bg-[#ff5f56]" />
            <span className="h-2.5 w-2.5 rounded-full bg-[#ffbd2e]" />
            <span className="h-2.5 w-2.5 rounded-full bg-[#27c93f]" />
          </div>
        )}

        {/* "Pantalla": contenido que se desvanece/cruza al cambiar de OS */}
        <div className="relative flex-1 bg-gradient-to-br from-carbon-900 to-carbon-800 p-3">
          <AnimatePresence mode="wait">
            <motion.div
              key={os}
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -10 }}
              transition={{ duration: 0.35, ease: EASE_PREMIUM }}
              className="flex h-full flex-col gap-2"
            >
              <div className="h-6 w-2/3 rounded-md bg-gradient-to-r from-neon-green/40 to-cyber-violet/40" />
              <div className="grid flex-1 grid-cols-2 gap-2">
                <div className="rounded-lg border border-carbon-600 bg-carbon-800/60" />
                <div className="rounded-lg border border-carbon-600 bg-carbon-800/60" />
                <div className="col-span-2 rounded-lg border border-neon-green/30 bg-neon-green/5" />
              </div>
              <div className="h-8 rounded-lg bg-carbon-700/80" />
            </motion.div>
          </AnimatePresence>
        </div>
      </motion.div>
    </div>
  );
}
