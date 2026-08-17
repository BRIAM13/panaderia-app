import { motion } from "framer-motion";
import { Wheat, Target, Eye } from "lucide-react";
import { HISTORIA, MISION_VISION } from "../data/config";

const EASE_PREMIUM = [0.16, 1, 0.3, 1] as const;

export function Nosotros() {
  return (
    <section id="nosotros" className="px-6 py-24 sm:py-32">
      <div className="mx-auto max-w-4xl">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, margin: "-100px" }}
          transition={{ duration: 0.6, ease: EASE_PREMIUM }}
          className="text-center"
        >
          <motion.div
            initial={{ opacity: 0, scale: 0.6, rotate: -20 }}
            whileInView={{ opacity: 1, scale: 1, rotate: 0 }}
            viewport={{ once: true, margin: "-100px" }}
            transition={{ duration: 0.6, ease: EASE_PREMIUM }}
            className="mx-auto mb-5 flex h-14 w-14 items-center justify-center rounded-2xl bg-pan-terracota-suave/60 text-pan-terracota"
          >
            <Wheat className="h-7 w-7" />
          </motion.div>
          <h2 className="font-[family-name:var(--font-display-panaderia)] text-4xl font-semibold text-pan-carbon sm:text-5xl">
            Nuestra historia
          </h2>
        </motion.div>

        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, margin: "-80px" }}
          transition={{ duration: 0.6, ease: EASE_PREMIUM, delay: 0.1 }}
          className="mx-auto mt-8 max-w-2xl space-y-4 text-center text-lg text-pan-carbon-suave"
        >
          <p>{HISTORIA.parrafo1}</p>
          <p>{HISTORIA.parrafo2}</p>
        </motion.div>

        <div className="mt-16 grid gap-6 sm:grid-cols-2">
          <motion.div
            initial={{ opacity: 0, y: 24 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true, margin: "-80px" }}
            transition={{ duration: 0.6, ease: EASE_PREMIUM }}
            whileHover={{ y: -6 }}
            className="rounded-3xl bg-pan-crema-suave p-8 shadow-sm shadow-pan-carbon/5 transition-shadow duration-300 hover:shadow-xl hover:shadow-pan-carbon/10"
          >
            <div className="mb-4 flex h-11 w-11 items-center justify-center rounded-xl bg-pan-terracota-suave/60 text-pan-terracota">
              <Target className="h-5 w-5" />
            </div>
            <h3 className="font-[family-name:var(--font-display-panaderia)] text-xl font-semibold text-pan-carbon">
              Misión
            </h3>
            <p className="mt-3 text-pan-carbon-suave">{MISION_VISION.mision}</p>
          </motion.div>

          <motion.div
            initial={{ opacity: 0, y: 24 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true, margin: "-80px" }}
            transition={{ duration: 0.6, ease: EASE_PREMIUM, delay: 0.08 }}
            whileHover={{ y: -6 }}
            className="rounded-3xl bg-pan-crema-suave p-8 shadow-sm shadow-pan-carbon/5 transition-shadow duration-300 hover:shadow-xl hover:shadow-pan-carbon/10"
          >
            <div className="mb-4 flex h-11 w-11 items-center justify-center rounded-xl bg-pan-bronce-suave/60 text-pan-bronce">
              <Eye className="h-5 w-5" />
            </div>
            <h3 className="font-[family-name:var(--font-display-panaderia)] text-xl font-semibold text-pan-carbon">
              Visión
            </h3>
            <p className="mt-3 text-pan-carbon-suave">{MISION_VISION.vision}</p>
          </motion.div>
        </div>
      </div>
    </section>
  );
}
