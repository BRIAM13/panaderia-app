import { useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { ChevronDown, HelpCircle } from "lucide-react";
import { CANTIDAD_MINIMA_UNIDAD, UBICACION } from "../data/config";
import type { HorariosPanaderia } from "../services/api";
import { formatearHora12 } from "../utils/horariosPan";
import { EASE_PREMIUM, VIEWPORT_REVEAL } from "../utils/animacion";
import { EncabezadoSeccion } from "./EncabezadoSeccion";

interface Pregunta {
  id: string;
  pregunta: string;
  respuesta: React.ReactNode;
}

/** Solo preguntas que la propia página ya puede contestar con certeza:
 * el recojo (el sistema no tiene reparto en ninguna parte), el mínimo por
 * unidad (el mismo número que valida el backend) y el horario, que llega
 * en vivo con el catálogo. Nada inventado: si un dato no está en el código,
 * no hay pregunta sobre él. */
function armarPreguntas(horarios: HorariosPanaderia | null): Pregunta[] {
  return [
    {
      id: "delivery",
      pregunta: "¿Hacen delivery?",
      respuesta: (
        <>
          Por ahora no: todos los pedidos son para recoger en la panadería, en {UBICACION.direccion},{" "}
          {UBICACION.ciudad}. Al hacer tu pedido eliges el día y la hora en que vas a pasar, y lo
          dejamos separado y recién horneado para ese momento.
        </>
      ),
    },
    {
      id: "minimo",
      pregunta: `¿Por qué el pedido mínimo es de ${CANTIDAD_MINIMA_UNIDAD} panes?`,
      respuesta: (
        <>
          Porque el pan por unidad lo horneamos por tandas: separar un pedido para una hora concreta
          significa reservarte parte de una hornada. Debajo de {CANTIDAD_MINIMA_UNIDAD} panes no nos
          alcanza para apartar la tanda, así que ese es nuestro mínimo para pedidos por encargo. Si
          solo quieres unos cuantos panes, pásate por la tienda y te atendemos al momento, sin
          mínimo de nada.
        </>
      ),
    },
    {
      id: "horario",
      pregunta: "¿En qué horario puedo recoger mi pedido?",
      respuesta: horarios ? (
        <>
          Atendemos de {formatearHora12(horarios.horaApertura)} a {formatearHora12(horarios.horaCierre)}.
          Los pedidos que entran antes de las {formatearHora12(horarios.horaLimitePedido)} se pueden
          recoger el mismo día desde las {formatearHora12(horarios.horaRecojoMismoDia)}; después de
          esa hora, el recojo pasa al día siguiente. Necesitamos al menos{" "}
          {horarios.minutosTolerancia} minutos de anticipación para cualquier pedido del mismo día.
        </>
      ) : (
        <>
          Nuestro horario de atención aparece en el formulario de pedido al elegir la hora de recojo.
          Si la página todavía no cargó, dale un momento: el servidor puede estar despertando.
        </>
      ),
    },
    {
      id: "cuenta",
      pregunta: "¿Necesito crear una cuenta para pedir?",
      respuesta: (
        <>
          No. Desde esta página basta con tu DNI o RUC y tu número de celular. La cuenta con
          contraseña es otra cosa: sirve para ver tu historial completo y tus deudas dentro de
          nuestra app, y es opcional.
        </>
      ),
    },
  ];
}

/** Las dudas que frenan un pedido, resueltas antes de que alguien tenga que
 * escribir para preguntarlas. Mismo acordeón que el panel de seguimiento:
 * un solo bloque abierto a la vez, con el alto animado. */
export function PreguntasFrecuentes({ horarios }: { horarios: HorariosPanaderia | null }) {
  const [abierta, setAbierta] = useState<string | null>(null);
  const preguntas = armarPreguntas(horarios);

  return (
    <section id="preguntas" className="px-6 py-24 sm:py-32">
      <div className="mx-auto max-w-3xl">
        <EncabezadoSeccion
          etiqueta="Dudas"
          icono={HelpCircle}
          titulo="Preguntas"
          tituloDestacado="frecuentes"
          tono="bronce"
          descripcion="Lo que más nos preguntan antes de hacer un pedido."
        />

        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={VIEWPORT_REVEAL}
          transition={{ duration: 0.6, ease: EASE_PREMIUM, delay: 0.1 }}
          className="mt-10 space-y-3 sm:mt-14"
        >
          {preguntas.map((item) => {
            const estaAbierta = abierta === item.id;
            return (
              <div
                key={item.id}
                className="overflow-hidden rounded-2xl border border-pan-borde/40 bg-pan-crema-suave shadow-sm shadow-pan-carbon/5 transition-colors duration-300 hover:border-pan-borde/70"
              >
                <h3>
                  <button
                    type="button"
                    onClick={() => setAbierta((actual) => (actual === item.id ? null : item.id))}
                    aria-expanded={estaAbierta}
                    aria-controls={`respuesta-${item.id}`}
                    className="flex w-full min-h-14 items-center justify-between gap-4 px-5 py-4 text-left transition-colors hover:bg-pan-terracota-suave/20"
                  >
                    <span className="font-semibold text-pan-carbon">{item.pregunta}</span>
                    <ChevronDown
                      aria-hidden="true"
                      className={`h-4.5 w-4.5 shrink-0 text-pan-terracota transition-transform duration-300 ${
                        estaAbierta ? "rotate-180" : ""
                      }`}
                      strokeWidth={2}
                    />
                  </button>
                </h3>
                <AnimatePresence initial={false}>
                  {estaAbierta && (
                    <motion.div
                      id={`respuesta-${item.id}`}
                      initial={{ height: 0, opacity: 0 }}
                      animate={{ height: "auto", opacity: 1 }}
                      exit={{ height: 0, opacity: 0 }}
                      transition={{ duration: 0.3, ease: EASE_PREMIUM }}
                      className="overflow-hidden"
                    >
                      <p className="border-t border-pan-borde/30 bg-pan-crema/60 px-5 py-4 text-sm leading-relaxed text-pan-carbon-suave">
                        {item.respuesta}
                      </p>
                    </motion.div>
                  )}
                </AnimatePresence>
              </div>
            );
          })}
        </motion.div>
      </div>
    </section>
  );
}
