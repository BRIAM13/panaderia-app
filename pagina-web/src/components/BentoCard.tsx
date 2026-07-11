import { motion } from "framer-motion";
import { useTilt } from "../hooks/useTilt";
import type { FeatureBento } from "../data/config";

const SPAN_CLASES: Record<FeatureBento["span"], string> = {
  normal: "",
  "col-2": "sm:col-span-2",
  "row-2": "sm:row-span-2",
  "col-2-row-2": "sm:col-span-2 sm:row-span-2",
};

const ACENTO_CLASES = {
  green: {
    borde: "group-hover:border-neon-green/50",
    glow: "from-neon-green/15",
    punto: "bg-neon-green shadow-[0_0_10px_2px_rgba(57,255,176,0.5)]",
  },
  violet: {
    borde: "group-hover:border-cyber-violet/50",
    glow: "from-cyber-violet/15",
    punto: "bg-cyber-violet shadow-[0_0_10px_2px_rgba(168,85,247,0.5)]",
  },
} as const;

const EASE_PREMIUM = [0.16, 1, 0.3, 1] as const;

export function BentoCard({ feature, index }: { feature: FeatureBento; index: number }) {
  const { ref, rotateX, rotateY, onMouseMove, onMouseLeave } = useTilt(6);
  const acento = ACENTO_CLASES[feature.acento];

  return (
    <motion.div
      initial={{ opacity: 0, y: 28 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: "-80px" }}
      transition={{ duration: 0.6, ease: EASE_PREMIUM, delay: (index % 3) * 0.08 }}
      className={SPAN_CLASES[feature.span]}
      style={{ perspective: 800 }}
    >
      <motion.div
        ref={ref}
        onMouseMove={onMouseMove}
        onMouseLeave={onMouseLeave}
        style={{ rotateX, rotateY, transformStyle: "preserve-3d" }}
        className={`group relative flex h-full min-h-[180px] flex-col justify-between overflow-hidden rounded-2xl border border-carbon-700 bg-carbon-900 p-6 transition-colors duration-300 ${acento.borde}`}
      >
        <div
          className={`pointer-events-none absolute -top-16 -right-16 h-40 w-40 rounded-full bg-gradient-to-br ${acento.glow} to-transparent opacity-0 blur-2xl transition-opacity duration-500 group-hover:opacity-100`}
        />
        <span className={`h-2 w-2 rounded-full ${acento.punto}`} />
        <div className="relative z-10 mt-6">
          <h3 className="font-[family-name:var(--font-display)] text-xl font-semibold text-white">
            {feature.titulo}
          </h3>
          <p className="mt-2 text-sm leading-relaxed text-carbon-400">{feature.descripcion}</p>
        </div>
      </motion.div>
    </motion.div>
  );
}
