import { motion } from "framer-motion";
import { PackageSearch, ArrowRight } from "lucide-react";

const EASE_PREMIUM = [0.16, 1, 0.3, 1] as const;

/** CTA hacia /app/ (la misma app Flutter completa a la que lleva "Iniciar
 * sesión" del Navbar) — ahí, al loguearse, lo primero que ve el cliente es
 * justamente sus pedidos pendientes y su historial. */
export function SeguimientoPedido() {
  return (
    <section className="px-6 py-16">
      <motion.div
        initial={{ opacity: 0, y: 24 }}
        whileInView={{ opacity: 1, y: 0 }}
        viewport={{ once: true, margin: "-80px" }}
        transition={{ duration: 0.6, ease: EASE_PREMIUM }}
        className="mx-auto flex max-w-4xl flex-col items-center gap-6 rounded-3xl bg-pan-terracota px-8 py-12 text-center shadow-lg shadow-pan-terracota/20 sm:flex-row sm:text-left"
      >
        <div className="flex h-14 w-14 shrink-0 items-center justify-center rounded-2xl bg-white/15 text-pan-crema">
          <PackageSearch className="h-7 w-7" />
        </div>
        <div className="flex-1">
          <h3 className="font-[family-name:var(--font-display-panaderia)] text-2xl font-semibold text-pan-crema">
            ¿Ya hiciste un pedido antes?
          </h3>
          <p className="mt-1 text-pan-crema/85">
            Inicia sesión con tu DNI para ver en qué va tu pedido y revisar todo lo que ya pediste antes.
          </p>
        </div>
        <a
          href="/app/"
          className="inline-flex shrink-0 items-center gap-2 rounded-full bg-pan-crema px-6 py-3.5 font-semibold text-pan-terracota transition-transform hover:scale-105"
        >
          Ver mi pedido
          <ArrowRight className="h-4 w-4" />
        </a>
      </motion.div>
    </section>
  );
}
