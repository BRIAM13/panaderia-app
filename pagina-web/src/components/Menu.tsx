import { useEffect, useRef, useState } from "react";
import { motion } from "framer-motion";
import { ArrowRight, Croissant } from "lucide-react";
import { PRODUCTOS, type ProductoMenu } from "../data/config";
import { desplazarASeccion } from "../utils/scroll";
import { EASE_PREMIUM } from "../utils/animacion";
import { EncabezadoSeccion } from "./EncabezadoSeccion";

export function Menu() {
  return (
    <section id="menu" className="textura-grano bg-mesh-panaderia px-6 py-24 sm:py-32">
      <div className="mx-auto max-w-4xl">
        <EncabezadoSeccion
          etiqueta="El pan"
          icono={Croissant}
          titulo="Nuestro"
          tituloDestacado="pan"
          descripcion="El de siempre, hecho como siempre se hizo, fresco todos los días. Pronto sumamos el resto de nuestra variedad con sus propias fotos."
        />

        {/* Las tres columnas arrancan en md (768px), no en sm (640px): a
            640px cada tarjeta quedaba en 180px y la descripción se partía
            en siete renglones de dos o tres palabras. Entre 640 y 767px una
            sola columna a todo el ancho se ve mucho mejor que tres
            comprimidas. */}
        <div className="mt-10 grid grid-cols-1 gap-5 sm:mt-14 sm:gap-6 md:grid-cols-3">
          {PRODUCTOS.map((producto, index) => (
            <TarjetaProducto key={producto.nombreEnCatalogo} producto={producto} index={index} />
          ))}
        </div>
      </div>
    </section>
  );
}

/** Tarjeta que entra en 3D al aparecer en pantalla (se "endereza" al hacer
 * scroll), en vez de inclinarse con el mouse — el efecto va ligado a la
 * navegación por la página, no al cursor. */
function TarjetaProducto({ producto, index }: { producto: ProductoMenu; index: number }) {
  // La foto se revela con un fundido cuando termina de descargarse, sobre
  // un esqueleto del mismo tamaño: sin esto, en una conexión lenta la
  // tarjeta se quedaba con un rectángulo de color plano y la imagen
  // aparecía de golpe.
  const [cargada, setCargada] = useState(false);
  const imgRef = useRef<HTMLImageElement>(null);

  // Si el navegador ya tenía la foto en caché (visita repetida, o varias
  // tarjetas comparten imagen), el evento `load` puede disparar antes de
  // que React llegue a conectar `onLoad` — la tarjeta se quedaba con la
  // foto invisible (opacity:0) para siempre, sin ningún fundido pendiente
  // que lo arregle. `complete` ya viene en true en ese caso, así que un
  // solo chequeo al montar cubre el hueco que deja `onLoad` por sí solo.
  useEffect(() => {
    if (imgRef.current?.complete) setCargada(true);
  }, []);

  return (
    <motion.div
      initial={{ opacity: 0, y: 32, rotateX: 20 }}
      whileInView={{ opacity: 1, y: 0, rotateX: 0 }}
      viewport={{ once: true, margin: "-60px" }}
      transition={{ duration: 0.6, ease: EASE_PREMIUM, delay: index * 0.08 }}
      whileHover={{ y: -8 }}
      style={{ perspective: 800, transformStyle: "preserve-3d" }}
      className="group h-full"
    >
      <article className="shine-sweep tarjeta-realce flex h-full flex-col overflow-hidden rounded-3xl border border-pan-borde/20 bg-pan-crema-suave shadow-sm shadow-pan-carbon/5 transition-shadow duration-300 hover:shadow-2xl hover:shadow-pan-carbon/15">
        {/* En una sola columna la foto cuadrada llegaba a ocupar casi una
            pantalla entera de alto por tarjeta (600px en tablet vertical),
            dejando el nombre y la descripción siempre fuera de cuadro; en
            apaisado (4/3) se ve la foto y su texto de una sola mirada. A
            partir de md vuelve a ser cuadrada, como en escritorio. */}
        <div
          className={`relative aspect-4/3 w-full overflow-hidden md:aspect-square ${cargada ? "" : "esqueleto"}`}
        >
          <img
            ref={imgRef}
            src={producto.imagen}
            alt={producto.nombre}
            loading="lazy"
            decoding="async"
            onLoad={() => setCargada(true)}
            className={`h-full w-full object-cover transition-[transform,opacity,filter] duration-700 ease-[cubic-bezier(0.16,1,0.3,1)] group-hover:scale-110 ${
              cargada ? "scale-100 opacity-100 blur-0" : "scale-105 opacity-0 blur-md"
            }`}
          />
          {/* Velo que se oscurece al pasar el mouse: da profundidad a la
              foto y separa mejor el texto que aparece encima. */}
          <div className="pointer-events-none absolute inset-0 bg-gradient-to-t from-pan-carbon/35 via-transparent to-transparent opacity-0 transition-opacity duration-500 group-hover:opacity-100" />
        </div>
        <div className="flex flex-1 flex-col p-5">
          <h3 className="font-[family-name:var(--font-display-panaderia)] text-lg font-semibold text-pan-carbon">
            {producto.nombre}
          </h3>
          <p className="mt-1 flex-1 text-sm leading-relaxed text-pan-carbon-suave">{producto.descripcion}</p>
          {/* Atajo directo al formulario desde cada pan: antes había que
              volver al menú o al botón del inicio para pedir algo que ya
              se estaba mirando. */}
          <button
            type="button"
            onClick={() => desplazarASeccion("pedido")}
            className="mt-2 -ml-1 inline-flex min-h-11 w-fit items-center gap-1.5 rounded px-1 text-sm font-semibold text-pan-terracota transition-colors hover:text-pan-terracota-profundo"
          >
            Pedir este pan
            <ArrowRight className="h-3.5 w-3.5 transition-transform duration-300 group-hover:translate-x-1" />
          </button>
        </div>
      </article>
    </motion.div>
  );
}
