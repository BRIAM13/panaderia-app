import { useEffect, useRef, useState } from "react";
import { ChevronDown, ChevronUp, Clock } from "lucide-react";
import { formatearHora12 } from "../utils/horariosPan";
import { SelectorModal } from "./SelectorModal";

const HORAS_12 = Array.from({ length: 12 }, (_, i) => i + 1);
const MINUTOS_60 = Array.from({ length: 60 }, (_, i) => i);
const PERIODOS = ["AM", "PM"] as const;
type Periodo = (typeof PERIODOS)[number];

const ALTO_ITEM = 40;
const FILAS_VISIBLES = 5;
const ALTO_RUEDA = ALTO_ITEM * FILAS_VISIBLES;
const RELLENO = ALTO_ITEM * Math.floor(FILAS_VISIBLES / 2);

/** "HH:mm" (24h) -> { hora12, minuto, periodo } para mostrar/editar en
 * formato de 12 horas con AM/PM explícito. */
function desde24h(valor: string): { hora12: number; minuto: number; periodo: Periodo } {
  const [h, m] = valor.split(":").map(Number);
  const periodo: Periodo = h >= 12 ? "PM" : "AM";
  const hora12 = h % 12 === 0 ? 12 : h % 12;
  return { hora12, minuto: m, periodo };
}

function a24h(hora12: number, minuto: number, periodo: Periodo): string {
  let h = hora12 % 12;
  if (periodo === "PM") h += 12;
  return `${String(h).padStart(2, "0")}:${String(minuto).padStart(2, "0")}`;
}

function horaTextoAMinutos(horaTexto: string): number {
  const [h, m] = horaTexto.split(":").map(Number);
  return h * 60 + m;
}

interface RuedaProps<T> {
  valores: readonly T[];
  indice: number;
  onCambio: (indice: number) => void;
  deshabilitado?: (valor: T) => boolean;
  render: (valor: T) => string;
  ariaLabel: string;
}

/** Una columna de la rueda: desliza con el dedo/mouse (arrastre), con el
 * scroll de la rueda del mouse, o con los botones de flecha — el valor
 * centrado (con el marco resaltado detrás) es el elegido. Usa
 * scroll-snap nativo para el "click" de cada parada; el arrastre con
 * mouse mueve `scrollTop` a mano porque el navegador no lo hace solo. */
function Rueda<T>({ valores, indice, onCambio, deshabilitado, render, ariaLabel }: RuedaProps<T>) {
  const ref = useRef<HTMLDivElement>(null);
  const timeoutRef = useRef<number | undefined>(undefined);
  const arrastrandoRef = useRef(false);
  const arranqueRef = useRef({ y: 0, scroll: 0 });

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const destino = indice * ALTO_ITEM;
    if (Math.abs(el.scrollTop - destino) > 1) {
      el.scrollTo({ top: destino, behavior: "smooth" });
    }
  }, [indice]);

  function indiceMasCercano(): number {
    const el = ref.current;
    if (!el) return indice;
    return Math.min(valores.length - 1, Math.max(0, Math.round(el.scrollTop / ALTO_ITEM)));
  }

  function siguienteHabilitado(desde: number, direccion: 1 | -1): number {
    let i = desde;
    while (i >= 0 && i < valores.length) {
      if (!deshabilitado?.(valores[i])) return i;
      i += direccion;
    }
    return desde;
  }

  function confirmarDesdeScroll() {
    const cercano = indiceMasCercano();
    const valido = deshabilitado?.(valores[cercano]) ? siguienteHabilitado(cercano, 1) : cercano;
    if (valido !== indice) onCambio(valido);
  }

  function alScroll() {
    if (arrastrandoRef.current) return;
    window.clearTimeout(timeoutRef.current);
    timeoutRef.current = window.setTimeout(confirmarDesdeScroll, 120);
  }

  function alPointerDown(e: React.PointerEvent) {
    const el = ref.current;
    if (!el) return;
    arrastrandoRef.current = true;
    arranqueRef.current = { y: e.clientY, scroll: el.scrollTop };
    el.setPointerCapture(e.pointerId);
  }
  function alPointerMove(e: React.PointerEvent) {
    if (!arrastrandoRef.current || !ref.current) return;
    const delta = e.clientY - arranqueRef.current.y;
    ref.current.scrollTop = arranqueRef.current.scroll - delta;
  }
  function alPointerUp() {
    if (!arrastrandoRef.current) return;
    arrastrandoRef.current = false;
    confirmarDesdeScroll();
  }

  return (
    <div className="flex flex-col items-center">
      <button
        type="button"
        aria-label={`${ariaLabel} anterior`}
        onClick={() => onCambio(siguienteHabilitado(Math.max(0, indice - 1), -1))}
        className="rounded-full p-1 text-pan-carbon-suave transition-colors hover:bg-pan-crema-muted hover:text-pan-carbon"
      >
        <ChevronUp className="h-4 w-4" />
      </button>
      <div
        ref={ref}
        role="listbox"
        aria-label={ariaLabel}
        onScroll={alScroll}
        onPointerDown={alPointerDown}
        onPointerMove={alPointerMove}
        onPointerUp={alPointerUp}
        onPointerCancel={alPointerUp}
        style={{
          height: ALTO_RUEDA,
          paddingTop: RELLENO,
          paddingBottom: RELLENO,
          scrollSnapType: "y mandatory",
          scrollbarWidth: "none",
        }}
        className="w-16 cursor-grab touch-pan-y select-none overflow-y-auto overscroll-contain [&::-webkit-scrollbar]:hidden active:cursor-grabbing"
      >
        {valores.map((v, i) => {
          const off = deshabilitado?.(v) ?? false;
          return (
            <div
              key={i}
              role="option"
              aria-selected={i === indice}
              aria-disabled={off}
              style={{ height: ALTO_ITEM, scrollSnapAlign: "center" }}
              onClick={() => !off && onCambio(i)}
              className={`flex items-center justify-center text-lg tabular-nums transition-all duration-150 ${
                off
                  ? "cursor-not-allowed text-pan-carbon-suave/25"
                  : i === indice
                    ? "scale-110 font-bold text-pan-terracota"
                    : "cursor-pointer text-pan-carbon-suave/70"
              }`}
            >
              {render(v)}
            </div>
          );
        })}
      </div>
      <button
        type="button"
        aria-label={`${ariaLabel} siguiente`}
        onClick={() => onCambio(siguienteHabilitado(Math.min(valores.length - 1, indice + 1), 1))}
        className="rounded-full p-1 text-pan-carbon-suave transition-colors hover:bg-pan-crema-muted hover:text-pan-carbon"
      >
        <ChevronDown className="h-4 w-4" />
      </button>
    </div>
  );
}

interface SelectorHoraProps {
  id?: string;
  /** "HH:mm" en formato 24h, o "" si todavía no eligió. */
  valor: string;
  onChange: (hora: string) => void;
  placeholder?: string;
  /** "HH:mm": si se pasa, ninguna hora anterior a esta queda seleccionable
   * (usado cuando la fecha elegida es hoy, para respetar los minutos de
   * tolerancia — ver esMuyProntoHoy en utils/horariosPan.ts). */
  minimoHoy?: string;
}

/** Selector de hora estilo rueda de celular: tres columnas (hora, minuto,
 * AM/PM) que se deslizan hasta centrar el valor elegido, con flechas para
 * quien prefiera hacer clic. Abre en una ventana emergente con
 * Cancelar/Aceptar, para que el cliente pueda ver bien lo que eligió antes
 * de aplicarlo. */
export function SelectorHora({ id, valor, onChange, placeholder = "Elige una hora", minimoHoy }: SelectorHoraProps) {
  const [abierto, setAbierto] = useState(false);
  const [draftHora, setDraftHora] = useState(12);
  const [draftMinuto, setDraftMinuto] = useState(0);
  const [draftPeriodo, setDraftPeriodo] = useState<Periodo>("AM");

  function abrir() {
    const base = valor
      ? desde24h(valor)
      : minimoHoy
        ? desde24h(minimoHoy)
        : { hora12: 12, minuto: 0, periodo: "AM" as Periodo };
    setDraftHora(base.hora12);
    setDraftMinuto(base.minuto);
    setDraftPeriodo(base.periodo);
    setAbierto(true);
  }

  function aceptar() {
    onChange(a24h(draftHora, draftMinuto, draftPeriodo));
    setAbierto(false);
  }

  const minutosPiso = minimoHoy ? horaTextoAMinutos(minimoHoy) : null;
  function muyPronto(hora12: number, minuto: number, periodo: Periodo): boolean {
    if (minutosPiso === null) return false;
    return horaTextoAMinutos(a24h(hora12, minuto, periodo)) < minutosPiso;
  }

  const draftInvalido = muyPronto(draftHora, draftMinuto, draftPeriodo);

  return (
    <div className="relative">
      <button
        id={id}
        type="button"
        onClick={abrir}
        className={`flex w-full items-center gap-2.5 rounded-xl border border-pan-borde bg-pan-crema px-4 py-3 text-left outline-none focus:border-pan-terracota ${
          valor ? "text-pan-carbon" : "text-pan-carbon-suave"
        }`}
      >
        <Clock className="h-4 w-4 shrink-0 text-pan-terracota" />
        <span>{valor ? formatearHora12(valor) : placeholder}</span>
      </button>

      <SelectorModal
        abierto={abierto}
        titulo="Elige la hora de recojo"
        onCancelar={() => setAbierto(false)}
        onAceptar={aceptar}
        aceptarDeshabilitado={draftInvalido}
      >
        {minimoHoy && (
          <p className="mb-3 text-center text-xs text-pan-carbon-suave">
            Para hoy, lo más pronto que puedes elegir es {formatearHora12(minimoHoy)}.
          </p>
        )}
        <div className="relative">
          <div className="pointer-events-none absolute inset-x-0 top-1/2 h-10 -translate-y-1/2 rounded-xl border-y-2 border-pan-terracota/40 bg-pan-terracota-suave/20" />
          <div className="flex items-start justify-center gap-1">
            <Rueda
              valores={HORAS_12}
              indice={draftHora - 1}
              onCambio={(i) => setDraftHora(HORAS_12[i])}
              deshabilitado={(h) => muyPronto(h, draftMinuto, draftPeriodo)}
              render={(h) => String(h)}
              ariaLabel="Hora"
            />
            <span className="mt-2.5 text-lg font-bold text-pan-carbon-suave">:</span>
            <Rueda
              valores={MINUTOS_60}
              indice={draftMinuto}
              onCambio={(i) => setDraftMinuto(MINUTOS_60[i])}
              deshabilitado={(m) => muyPronto(draftHora, m, draftPeriodo)}
              render={(m) => String(m).padStart(2, "0")}
              ariaLabel="Minuto"
            />
            <Rueda
              valores={PERIODOS}
              indice={draftPeriodo === "AM" ? 0 : 1}
              onCambio={(i) => setDraftPeriodo(PERIODOS[i])}
              deshabilitado={(p) => muyPronto(draftHora, draftMinuto, p)}
              render={(p) => p}
              ariaLabel="AM o PM"
            />
          </div>
        </div>
      </SelectorModal>
    </div>
  );
}
