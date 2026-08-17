import { motion, useMotionValue, useSpring, useTransform } from "framer-motion";
import { PRODUCTOS, type ProductoMenu } from "../data/config";

const EASE_PREMIUM = [0.16, 1, 0.3, 1] as const;

export function Menu() {
  return (
    <section id="menu" className="bg-mesh-panaderia px-6 py-24 sm:py-32">
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
            <TarjetaProducto key={producto.nombreEnCatalogo} producto={producto} index={index} />
          ))}
        </div>
      </div>
    </section>
  );
}

/** Tarjeta con inclinación 3D que sigue al cursor — mismo espíritu que el
 * efecto "Tarjeta3D" ya usado en toda la app móvil (lib/widgets/tarjeta_3d.dart),
 * ahora también en la web, para que el pan se sienta "tocable". */
function TarjetaProducto({ producto, index }: { producto: ProductoMenu; index: number }) {
  const tiltX = useMotionValue(0);
  const tiltY = useMotionValue(0);
  const spring = { stiffness: 260, damping: 22 };
  const rotateX = useSpring(useTransform(tiltY, [-0.5, 0.5], [10, -10]), spring);
  const rotateY = useSpring(useTransform(tiltX, [-0.5, 0.5], [-10, 10]), spring);

  function manejarMovimiento(e: React.MouseEvent<HTMLDivElement>) {
    const rect = e.currentTarget.getBoundingClientRect();
    tiltX.set((e.clientX - rect.left) / rect.width - 0.5);
    tiltY.set((e.clientY - rect.top) / rect.height - 0.5);
  }

  function resetear() {
    tiltX.set(0);
    tiltY.set(0);
  }

  return (
    <motion.div
      initial={{ opacity: 0, y: 24 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: "-60px" }}
      transition={{ duration: 0.5, ease: EASE_PREMIUM, delay: index * 0.08 }}
      style={{ perspective: 800 }}
      onMouseMove={manejarMovimiento}
      onMouseLeave={resetear}
      className="group"
    >
      <motion.div
        style={{ rotateX, rotateY }}
        className="shine-sweep overflow-hidden rounded-3xl bg-pan-crema-suave shadow-sm shadow-pan-carbon/5 transition-shadow duration-300 hover:shadow-2xl hover:shadow-pan-carbon/15"
      >
        <div className="aspect-square w-full overflow-hidden bg-pan-terracota-suave/40">
          <img
            src={producto.imagen}
            alt={producto.nombre}
            className="h-full w-full object-cover transition-transform duration-500 group-hover:scale-110"
          />
        </div>
        <div className="p-5" style={{ transform: "translateZ(20px)" }}>
          <h3 className="font-[family-name:var(--font-display-panaderia)] text-lg font-semibold text-pan-carbon">
            {producto.nombre}
          </h3>
          <p className="mt-1 text-sm text-pan-carbon-suave">{producto.descripcion}</p>
        </div>
      </motion.div>
    </motion.div>
  );
}
