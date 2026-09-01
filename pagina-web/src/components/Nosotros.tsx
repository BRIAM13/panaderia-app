import { motion } from "framer-motion";
import { Wheat, Target, Eye, type LucideIcon } from "lucide-react";
import { HISTORIA, MISION_VISION } from "../data/config";
import { EASE_PREMIUM, VIEWPORT_REVEAL, contenedorEscalonado, subirAlAparecer } from "../utils/animacion";
import { EncabezadoSeccion } from "./EncabezadoSeccion";

const PILARES = [
  {
    icono: Target,
    etiqueta: "Lo que hacemos",
    titulo: "Misión",
    texto: MISION_VISION.mision,
    tono: "terracota" as const,
  },
  {
    icono: Eye,
    etiqueta: "Hacia dónde vamos",
    titulo: "Visión",
    texto: MISION_VISION.vision,
    tono: "bronce" as const,
  },
];

const TONOS_PILAR = {
  terracota: "bg-pan-terracota-suave/60 text-pan-terracota",
  bronce: "bg-pan-bronce-suave/70 text-pan-bronce-oscuro",
} as const;

export function Nosotros() {
  return (
    <section id="nosotros" className="px-6 py-24 sm:py-32">
      <div className="mx-auto max-w-4xl">
        <EncabezadoSeccion
          etiqueta="Nuestra casa"
          icono={Wheat}
          titulo="Nuestra"
          tituloDestacado="historia"
        />

        <motion.div
          variants={contenedorEscalonado(0.12, 0.05)}
          initial="oculto"
          whileInView="visible"
          viewport={VIEWPORT_REVEAL}
          className="mx-auto mt-10 max-w-2xl text-center"
        >
          {/* El primer párrafo hace de entradilla (más grande, más aire) y
              el segundo baja de tamaño: antes los dos pesaban igual y el
              bloque se leía como un muro de texto sin punto de entrada. */}
          <motion.p
            variants={subirAlAparecer}
            className="text-lg leading-relaxed text-pan-carbon-suave sm:text-xl md:text-[1.32rem]"
          >
            {HISTORIA.parrafo1}
          </motion.p>
          <motion.p
            variants={subirAlAparecer}
            className="mt-5 text-base leading-relaxed text-pan-carbon-suave sm:text-lg"
          >
            {HISTORIA.parrafo2}
          </motion.p>
        </motion.div>

        {/* Igual que en el menú, las dos columnas esperan a md: a 640px cada
            pilar quedaba en 270px menos 64px de relleno interno, y la
            misión/visión (párrafos largos) se leían como una tira angosta
            de doce renglones. */}
        <div className="mt-12 grid gap-5 sm:mt-16 sm:gap-6 md:grid-cols-2">
          {PILARES.map((pilar, indice) => (
            <TarjetaPilar key={pilar.titulo} {...pilar} indice={indice} />
          ))}
        </div>
      </div>
    </section>
  );
}

function TarjetaPilar({
  icono: Icono,
  etiqueta,
  titulo,
  texto,
  tono,
  indice,
}: {
  icono: LucideIcon;
  etiqueta: string;
  titulo: string;
  texto: string;
  tono: keyof typeof TONOS_PILAR;
  indice: number;
}) {
  return (
    <motion.article
      initial={{ opacity: 0, y: 26 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={VIEWPORT_REVEAL}
      transition={{ duration: 0.6, ease: EASE_PREMIUM, delay: indice * 0.09 }}
      whileHover={{ y: -6 }}
      className="tarjeta-realce group rounded-3xl border border-pan-borde/25 bg-pan-crema-suave p-6 shadow-sm sm:p-8 shadow-pan-carbon/5 transition-shadow duration-300 hover:shadow-xl hover:shadow-pan-carbon/10"
    >
      <div className="flex items-center gap-3">
        <span
          className={`flex h-11 w-11 shrink-0 items-center justify-center rounded-xl transition-transform duration-500 ease-[cubic-bezier(0.16,1,0.3,1)] group-hover:-rotate-6 group-hover:scale-110 ${TONOS_PILAR[tono]}`}
        >
          <Icono className="h-5 w-5" strokeWidth={1.75} />
        </span>
        <span className="text-[11px] font-semibold tracking-[0.16em] text-pan-carbon-suave uppercase">
          {etiqueta}
        </span>
      </div>
      <h3 className="mt-5 font-[family-name:var(--font-display-panaderia)] text-2xl font-semibold text-pan-carbon">
        {titulo}
      </h3>
      <p className="mt-3 leading-relaxed text-pan-carbon-suave">{texto}</p>
    </motion.article>
  );
}
