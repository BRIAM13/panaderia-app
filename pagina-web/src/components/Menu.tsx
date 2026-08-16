import { motion } from "framer-motion";
import { PRODUCTOS } from "../data/config";

const EASE_PREMIUM = [0.16, 1, 0.3, 1] as const;

export function Menu() {
  return (
    <section id="menu" className="bg-pan-crema-muted/60 px-6 py-24 sm:py-32">
      <div className="mx-auto max-w-4xl">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, margin: "-100px" }}
          transition={{ duration: 0.6, ease: EASE_PREMIUM }}
          className="mx-auto max-w-xl text-center"
        >
          <h2 className="font-[family-name:var(--font-display-panaderia)] text-4xl font-semibold text-pan-carbon sm:text-5xl">
            Nuestro <span className="text-gradient-pan">pan</span>
          </h2>
          <p className="mt-4 text-lg text-pan-carbon-suave">
            El de siempre, hecho como siempre se hizo, fresco todos los días. Pronto sumamos el resto de
            nuestra variedad con sus propias fotos.
          </p>
        </motion.div>

        <div className="mt-14 grid grid-cols-1 gap-6 sm:grid-cols-3">
          {PRODUCTOS.map((producto, index) => (
            <motion.div
              key={producto.nombreEnCatalogo}
              initial={{ opacity: 0, y: 24 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true, margin: "-60px" }}
              transition={{ duration: 0.5, ease: EASE_PREMIUM, delay: index * 0.08 }}
              className="group overflow-hidden rounded-3xl bg-pan-crema-suave shadow-sm shadow-pan-carbon/5 transition-shadow hover:shadow-md hover:shadow-pan-carbon/10"
            >
              <div className="aspect-square w-full overflow-hidden bg-pan-terracota-suave/40">
                <img
                  src={producto.imagen}
                  alt={producto.nombre}
                  className="h-full w-full object-cover transition-transform duration-500 group-hover:scale-105"
                />
              </div>
              <div className="p-5">
                <h3 className="font-[family-name:var(--font-display-panaderia)] text-lg font-semibold text-pan-carbon">
                  {producto.nombre}
                </h3>
                <p className="mt-1 text-sm text-pan-carbon-suave">{producto.descripcion}</p>
              </div>
            </motion.div>
          ))}
        </div>
      </div>
    </section>
  );
}
