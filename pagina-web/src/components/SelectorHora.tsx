import { useEffect, useRef, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { Clock } from "lucide-react";

const EASE_PREMIUM = [0.16, 1, 0.3, 1] as const;
const HORAS_12 = Array.from({ length: 12 }, (_, i) => i + 1);
const MINUTOS = [0, 15, 30, 45];

/** "HH:mm" (24h) -> { hora12, minuto, periodo } para mostrar/editar en
 * formato de 12 horas con AM/PM explícito. */
function desde24h(valor: string): { hora12: number; minuto: number; periodo: "AM" | "PM" } {
  const [h, m] = valor.split(":").map(Number);
  const periodo: "AM" | "PM" = h >= 12 ? "PM" : "AM";
  const hora12 = h % 12 === 0 ? 12 : h % 12;
  return { hora12, minuto: m, periodo };
}

function a24h(hora12: number, minuto: number, periodo: "AM" | "PM"): string {
  let h = hora12 % 12;
  if (periodo === "PM") h += 12;
  return `${String(h).padStart(2, "0")}:${String(minuto).padStart(2, "0")}`;
}

function formatearBonito(valor: string): string {
  const { hora12, minuto, periodo } = desde24h(valor);
  return `${hora12}:${String(minuto).padStart(2, "0")} ${periodo === "AM" ? "a. m." : "p. m."}`;
}

interface SelectorHoraProps {
  id?: string;
  /** "HH:mm" en formato 24h, o "" si todavía no eligió. */
  valor: string;
  onChange: (hora: string) => void;
  placeholder?: string;
}

/** Selector de hora propio, con AM/PM como dos botones bien diferenciados
 * (en vez de un pequeño toggle fácil de leer mal) — evita la confusión
 * típica de los relojes de 24h o del <input type=time> nativo, cuyo
 * formato depende del idioma del sistema operativo. */
export function SelectorHora({ id, valor, onChange, placeholder = "Elige una hora" }: SelectorHoraProps) {
  const [abierto, setAbierto] = useState(false);
  const actual = valor ? desde24h(valor) : { hora12: 12, minuto: 0, periodo: "AM" as const };
  const [hora12, setHora12] = useState(actual.hora12);
  const [minuto, setMinuto] = useState(actual.minuto);
  const [periodo, setPeriodo] = useState<"AM" | "PM">(actual.periodo);
  const contenedorRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    function alClickAfuera(e: MouseEvent) {
      if (contenedorRef.current && !contenedorRef.current.contains(e.target as Node)) {
        setAbierto(false);
      }
    }
    document.addEventListener("mousedown", alClickAfuera);
    return () => document.removeEventListener("mousedown", alClickAfuera);
  }, []);

  function aplicar(nuevoHora12: number, nuevoMinuto: number, nuevoPeriodo: "AM" | "PM") {
    setHora12(nuevoHora12);
    setMinuto(nuevoMinuto);
    setPeriodo(nuevoPeriodo);
    onChange(a24h(nuevoHora12, nuevoMinuto, nuevoPeriodo));
  }

  return (
    <div ref={contenedorRef} className="relative">
      <button
        id={id}
        type="button"
        onClick={() => setAbierto((v) => !v)}
        className={`flex w-full items-center gap-2.5 rounded-xl border border-pan-borde bg-pan-crema px-4 py-3 text-left outline-none focus:border-pan-terracota ${
          valor ? "text-pan-carbon" : "text-pan-carbon-suave"
        }`}
      >
        <Clock className="h-4 w-4 shrink-0 text-pan-terracota" />
        <span>{valor ? formatearBonito(valor) : placeholder}</span>
      </button>

      <AnimatePresence>
        {abierto && (
          <motion.div
            initial={{ opacity: 0, y: -6, scale: 0.97 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: -6, scale: 0.97 }}
            transition={{ duration: 0.18, ease: EASE_PREMIUM }}
            className="absolute left-1/2 z-20 mt-2 w-72 max-w-[calc(100vw-2.5rem)] -translate-x-1/2 rounded-2xl border border-pan-borde bg-pan-crema-suave p-4 shadow-xl shadow-pan-carbon/15"
          >
            <div className="mb-3 flex overflow-hidden rounded-full border border-pan-borde">
              {(["AM", "PM"] as const).map((p) => (
                <button
                  key={p}
                  type="button"
                  onClick={() => aplicar(hora12, minuto, p)}
                  className={`flex-1 py-2 text-sm font-bold transition-colors ${
                    periodo === p
                      ? "bg-pan-terracota text-pan-crema"
                      : "bg-pan-crema text-pan-carbon-suave hover:text-pan-carbon"
                  }`}
                >
                  {p === "AM" ? "AM · mañana" : "PM · tarde/noche"}
                </button>
              ))}
            </div>

            <p className="mb-1.5 text-[11px] font-semibold tracking-wide text-pan-carbon-suave uppercase">Hora</p>
            <div className="mb-3 grid grid-cols-6 gap-1.5">
              {HORAS_12.map((h) => (
                <button
                  key={h}
                  type="button"
                  onClick={() => aplicar(h, minuto, periodo)}
                  className={`rounded-lg py-1.5 text-sm font-medium transition-colors ${
                    hora12 === h
                      ? "bg-pan-terracota text-pan-crema"
                      : "bg-pan-crema text-pan-carbon hover:bg-pan-terracota-suave/50"
                  }`}
                >
                  {h}
                </button>
              ))}
            </div>

            <p className="mb-1.5 text-[11px] font-semibold tracking-wide text-pan-carbon-suave uppercase">Minutos</p>
            <div className="grid grid-cols-4 gap-1.5">
              {MINUTOS.map((m) => (
                <button
                  key={m}
                  type="button"
                  onClick={() => aplicar(hora12, m, periodo)}
                  className={`rounded-lg py-1.5 text-sm font-medium transition-colors ${
                    minuto === m
                      ? "bg-pan-terracota text-pan-crema"
                      : "bg-pan-crema text-pan-carbon hover:bg-pan-terracota-suave/50"
                  }`}
                >
                  {String(m).padStart(2, "0")}
                </button>
              ))}
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
