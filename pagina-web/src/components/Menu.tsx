import { useEffect, useRef, useState } from "react";
import { motion } from "framer-motion";
import { ArrowRight, Croissant, Info } from "lucide-react";
import { CANTIDAD_MINIMA_UNIDAD, FOTO_PRODUCTO, PRODUCTOS, type ProductoMenu } from "../data/config";
import type { ProductoPublico } from "../services/api";
import type { CatalogoPublico } from "../hooks/useCatalogoPublico";
import { desplazarASeccion } from "../utils/scroll";
import { EASE_PREMIUM, VIEWPORT_REVEAL } from "../utils/animacion";
import { EncabezadoSeccion } from "./EncabezadoSeccion";

export function Menu({ catalogo }: { catalogo: CatalogoPublico }) {
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

        {/* El mínimo por encargo se dice ACÁ, antes de que nadie abra el
            formulario: es la condición que más pedidos frena y estaba
            escondida en un campo de ayuda del último paso. */}
        <motion.p
          initial={{ opacity: 0, y: 12 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={VIEWPORT_REVEAL}
          transition={{ duration: 0.5, ease: EASE_PREMIUM, delay: 0.15 }}
          className="mx-auto mt-8 flex max-w-xl items-start gap-2.5 rounded-2xl border border-pan-borde/30 bg-pan-crema-suave/80 px-4 py-3 text-sm leading-relaxed text-pan-carbon-suave"
        >
          <Info className="mt-0.5 h-4 w-4 shrink-0 text-pan-terracota" strokeWidth={1.75} />
          <span>
            Los pedidos por encargo del pan por unidad son desde{" "}
            <strong className="font-semibold text-pan-carbon">{CANTIDAD_MINIMA_UNIDAD} panes</strong>. El pan de
            hamburguesa se pide por paquetes de 12. Para menos cantidad, pásate por la tienda y te
            atendemos al momento.
          </span>
        </motion.p>

        {/* Las tres columnas arrancan en md (768px), no en sm (640px): a
            640px cada tarjeta quedaba en 180px y la descripción se partía
            en siete renglones de dos o tres palabras. Entre 640 y 767px una
            sola columna a todo el ancho se ve mucho mejor que tres
            comprimidas. */}
        <div className="mt-8 grid grid-cols-1 gap-5 sm:mt-10 sm:gap-6 md:grid-cols-3">
          {PRODUCTOS.map((producto, index) => (
            <TarjetaProducto
              key={producto.nombreEnCatalogo}
              producto={producto}
              // El precio sale del catálogo real (el mismo fetch que usa el
              // formulario), nunca de una copia escrita a mano acá: así no
              // hay forma de que el menú muestre un precio y el pedido
              // cobre otro.
              enCatalogo={catalogo.productos.find((p) => p.nombre === producto.nombreEnCatalogo)}
              cargandoPrecio={catalogo.cargando}
              index={index}
            />
          ))}
        </div>
      </div>
    </section>
  );
}

/** Tarjeta que entra en 3D al aparecer en pantalla (se "endereza" al hacer
 * scroll), en vez de inclinarse con el mouse — el efecto va ligado a la
 * navegación por la página, no al cursor. */
function TarjetaProducto({
  producto,
  enCatalogo,
  cargandoPrecio,
  index,
}: {
  producto: ProductoMenu;
  enCatalogo: ProductoPublico | undefined;
  cargandoPrecio: boolean;
  index: number;
}) {
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
          {/* WebP primero y JPEG de respaldo: la misma foto, ~25% menos de
              descarga en cualquier navegador de los últimos años. */}
          <picture>
            <source srcSet={producto.imagenWebp} type="image/webp" />
            <img
              ref={imgRef}
              src={producto.imagen}
              alt={producto.nombre}
              width={FOTO_PRODUCTO.ancho}
              height={FOTO_PRODUCTO.alto}
              loading="lazy"
              decoding="async"
              onLoad={() => setCargada(true)}
              className={`h-full w-full object-cover transition-[transform,opacity,filter] duration-700 ease-[cubic-bezier(0.16,1,0.3,1)] group-hover:scale-110 ${
                cargada ? "scale-100 opacity-100 blur-0" : "scale-105 opacity-0 blur-md"
              }`}
            />
          </picture>
          {/* Velo que se oscurece al pasar el mouse: da profundidad a la
              foto y separa mejor el texto que aparece encima. */}
          <div className="pointer-events-none absolute inset-0 bg-gradient-to-t from-pan-carbon/35 via-transparent to-transparent opacity-0 transition-opacity duration-500 group-hover:opacity-100" />
        </div>
        <div className="flex flex-1 flex-col p-5">
          <h3 className="font-[family-name:var(--font-display-panaderia)] text-lg font-semibold text-pan-carbon">
            {producto.nombre}
          </h3>
          {/* El precio va en su propio renglón, no compartiendo fila con el
              nombre: en tres columnas la tarjeta mide ~280px y "Pan de
              hamburguesa" se partía en dos renglones para hacerle sitio. */}
          <PrecioProducto producto={enCatalogo} cargando={cargandoPrecio} />
          <p className="mt-1.5 flex-1 text-sm leading-relaxed text-pan-carbon-suave">{producto.descripcion}</p>
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

/** El precio real del pan, tal como lo devuelve el catálogo. Mientras
 * llega, ocupa su lugar un esqueleto del mismo tamaño para que el título no
 * se reacomode al aparecer la cifra; si el servidor no responde (o ese pan
 * ya no está en el catálogo), simplemente no se muestra ningún precio antes
 * que arriesgarse a mostrar uno equivocado. */
function PrecioProducto({ producto, cargando }: { producto: ProductoPublico | undefined; cargando: boolean }) {
  if (cargando) {
    return <span aria-hidden="true" className="esqueleto mt-1.5 block h-4 w-28 rounded-md" />;
  }
  if (!producto) return null;
  return (
    <p className="mt-1 text-sm">
      <span className="font-semibold text-pan-terracota">S/ {producto.precioUnitario.toFixed(2)}</span>{" "}
      <span className="text-pan-carbon-suave">
        {producto.esPaquete ? "el paquete de 12" : "por unidad"}
      </span>
    </p>
  );
}
