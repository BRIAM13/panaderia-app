import { forwardRef, useEffect, useImperativeHandle, useRef, useState } from "react";
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

function mod(n: number, m: number): number {
  return ((n % m) + m) % m;
}

interface RuedaProps<T> {
  valores: readonly T[];
  indice: number;
  onCambio: (indice: number) => void;
  deshabilitado?: (valor: T) => boolean;
  render: (valor: T) => string;
  ariaLabel: string;
  /** false = tope fijo en los dos extremos del arreglo, sin repetirlo ni
   * dar la vuelta — pensado para AM/PM: con solo 2 valores, una rueda
   * infinita se ve rara (cada fila alterna A, P, A, P...). Hora y minuto sí
   * quedan infinitos por defecto. */
  infinito?: boolean;
}

interface Limites {
  min: number;
  max: number;
}

/** Una columna de la rueda: gira sin fin (como una ruleta real, del 12
 * vuelve a salir el 1) deslizando con el dedo/mouse, con el scroll del
 * mouse, o con los botones de flecha. Cuando `deshabilitado` marca una
 * franja como inválida (el piso de minutos de tolerancia), la rueda no dej
 * a arrastrarse ni girar hacia ese lado — no es un salto después de
 * soltar, es una pared física en el mismo gesto. */
function Rueda<T>({ valores, indice, onCambio, deshabilitado, render, ariaLabel, infinito = true }: RuedaProps<T>) {
  const n = valores.length;
  // Suficientes copias para que nunca se note el "reciclado": entre más
  // chico el arreglo (ej. AM/PM con solo 2 valores), más copias hacen falta.
  const copias = infinito ? Math.max(5, Math.ceil(24 / n)) : 1;
  const total = copias * n;
  const copiaMedia = Math.floor(copias / 2);
  const posInicial = copiaMedia * n + indice;

  const ref = useRef<HTMLDivElement>(null);
  const posRef = useRef(posInicial);
  // Estado (no ref) porque de esto depende qué ítem se dibuja resaltado —
  // con copias repetidas, más de una fila puede compartir el mismo valor
  // lógico a la vez dentro de lo visible, así que el resaltado se decide
  // por posición física centrada, no por valor.
  const [posCentral, setPosCentral] = useState(posInicial);
  const timeoutRef = useRef<number | undefined>(undefined);
  const arrastrandoRef = useRef(false);
  const arranqueRef = useRef({ y: 0, pos: 0 });
  // Un scrollTo/scrollTop propio (flecha, clic en ítem, sincronización de
  // afuera) también dispara el evento 'scroll' del navegador — sin esta
  // bandera, el listener de scroll lo trataría como si fuera el usuario
  // arrastrando, compitiendo consigo mismo cuando se hacen varios clics
  // seguidos rápido.
  const programaticoRef = useRef(false);
  const programaticoTimeoutRef = useRef<number | undefined>(undefined);

  function estaDeshabilitado(pos: number): boolean {
    return deshabilitado?.(valores[mod(pos, n)]) ?? false;
  }

  /** Explora hasta una vuelta completa en cada sentido desde `pos` (que
   * debe ser una posición válida) para encontrar la franja deshabilitada
   * más cercana — así sabe dónde está la "pared". Si no encuentra ninguna
   * en toda la vuelta, ese lado queda libre (sin tope). */
  function calcularLimites(pos: number): Limites {
    let min = -Infinity;
    let max = Infinity;
    for (let paso = 1; paso <= n; paso++) {
      if (estaDeshabilitado(pos - paso)) {
        min = pos - paso + 1;
        break;
      }
    }
    for (let paso = 1; paso <= n; paso++) {
      if (estaDeshabilitado(pos + paso)) {
        max = pos + paso - 1;
        break;
      }
    }
    if (!infinito) {
      // Sin vuelta: además del piso de tolerancia, tampoco se puede pasar
      // de los bordes reales del arreglo (ej. AM/PM solo tiene 2 paradas).
      min = Math.max(min, 0);
      max = Math.min(max, n - 1);
    }
    return { min, max };
  }

  function marcarProgramatico() {
    programaticoRef.current = true;
    window.clearTimeout(programaticoTimeoutRef.current);
    programaticoTimeoutRef.current = window.setTimeout(() => {
      programaticoRef.current = false;
    }, 320);
  }

  function irA(pos: number, suave: boolean) {
    const el = ref.current;
    if (!el) return;
    posRef.current = pos;
    marcarProgramatico();
    el.scrollTo({ top: pos * ALTO_ITEM, behavior: suave ? "smooth" : "instant" });
  }

  /** Si la posición actual quedó demasiado cerca del principio/final del
   * lote de copias renderizadas, salta en silencio a la copia del medio
   * (mismo valor visual, otra copia física) — así nunca se acaban las
   * copias sin importar cuánto siga girando. */
  function recentrarSiHaceFalta() {
    if (!infinito) return;
    const el = ref.current;
    if (!el) return;
    const pos = posRef.current;
    const copiaActual = Math.floor(pos / n);
    if (copiaActual <= 0 || copiaActual >= copias - 1) {
      const destino = copiaMedia * n + mod(pos, n);
      posRef.current = destino;
      marcarProgramatico();
      el.scrollTop = destino * ALTO_ITEM;
      setPosCentral(destino);
    }
  }

  // Al montar, el navegador arranca con scrollTop en 0 — no coincide con
  // la copia "del medio" que elegimos como posición inicial (posInicial),
  // así que hay que alinear el scroll real una sola vez, sin animación.
  useEffect(() => {
    irA(posRef.current, false);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Sincroniza cuando `indice` cambia desde afuera (al abrir el modal, al
  // hacer clic en un botón de flecha o en un ítem, o cuando el piso de
  // tolerancia avanza solo con el reloj y empuja el valor elegido hacia
  // adelante) — busca la ocurrencia de ese valor más cercana a la posición
  // física actual, para no saltar visualmente de copia.
  useEffect(() => {
    if (!infinito) {
      // Sin copias repetidas, la posición física ES el índice lógico —
      // nada que buscar, solo ir directo ahí si no coincide ya.
      if (indice !== posRef.current) {
        irA(indice, true);
        setPosCentral(indice);
      }
      return;
    }
    const posActual = posRef.current;
    const base = Math.round(posActual / n) * n + indice;
    let masCercana = base;
    for (const candidata of [base - n, base, base + n]) {
      if (Math.abs(candidata - posActual) < Math.abs(masCercana - posActual)) masCercana = candidata;
    }
    if (masCercana !== posActual) {
      irA(masCercana, true);
      setPosCentral(masCercana);
      window.setTimeout(recentrarSiHaceFalta, 260);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [indice, infinito]);

  function confirmar(pos: number) {
    posRef.current = pos;
    setPosCentral(pos);
    const logico = mod(pos, n);
    if (logico !== indice) onCambio(logico);
  }

  function confirmarDesdeScroll() {
    const el = ref.current;
    if (!el) return;
    let pos = Math.round(el.scrollTop / ALTO_ITEM);
    if (estaDeshabilitado(pos)) {
      // El ancla para calcular el límite tiene que ser una posición
      // válida — se usa `posRef.current` (la última confirmada) en vez de
      // `pos` (que en este punto ya sabemos que es inválida).
      const limites = calcularLimites(posRef.current);
      if (limites.min !== -Infinity && pos < limites.min) pos = limites.min;
      else if (limites.max !== Infinity && pos > limites.max) pos = limites.max;
    }
    irA(pos, true);
    recentrarSiHaceFalta();
    confirmar(pos);
  }

  function alScroll() {
    if (arrastrandoRef.current || programaticoRef.current) return;
    // Mientras la rueda se mueve sola (scroll nativo del mouse, o el
    // "vuelo" después de soltar el dedo), se corrige en caliente si se
    // sale de los límites — así nunca llega a mostrarse una franja
    // inválida, ni un instante. Los límites se calculan frescos en cada
    // evento (no se cachean): así funciona igual con scroll del mouse,
    // que nunca pasa por pointerdown/pointermove.
    const el = ref.current;
    if (el) {
      const { min, max } = calcularLimites(posRef.current);
      const posFlot = el.scrollTop / ALTO_ITEM;
      if (min !== -Infinity && posFlot < min) el.scrollTop = min * ALTO_ITEM;
      else if (max !== Infinity && posFlot > max) el.scrollTop = max * ALTO_ITEM;
    }
    window.clearTimeout(timeoutRef.current);
    timeoutRef.current = window.setTimeout(confirmarDesdeScroll, 120);
  }

  function alPointerDown(e: React.PointerEvent) {
    const el = ref.current;
    if (!el) return;
    arrastrandoRef.current = true;
    arranqueRef.current = { y: e.clientY, pos: posRef.current };
    el.setPointerCapture(e.pointerId);
  }
  function alPointerMove(e: React.PointerEvent) {
    if (!arrastrandoRef.current || !ref.current) return;
    const deltaPx = e.clientY - arranqueRef.current.y;
    let posFlot = arranqueRef.current.pos - deltaPx / ALTO_ITEM;
    const { min, max } = calcularLimites(arranqueRef.current.pos);
    if (min !== -Infinity) posFlot = Math.max(posFlot, min);
    if (max !== Infinity) posFlot = Math.min(posFlot, max);
    posRef.current = Math.round(posFlot);
    ref.current.scrollTop = posFlot * ALTO_ITEM;
  }
  function alPointerUp() {
    if (!arrastrandoRef.current) return;
    arrastrandoRef.current = false;
    confirmarDesdeScroll();
  }

  function moverPaso(direccion: 1 | -1) {
    const limites = calcularLimites(posRef.current);
    const destino = posRef.current + direccion;
    if (direccion < 0 && limites.min !== -Infinity && destino < limites.min) return;
    if (direccion > 0 && limites.max !== Infinity && destino > limites.max) return;
    irA(destino, true);
    recentrarSiHaceFalta();
    confirmar(destino);
  }

  function alClicItem(pos: number, off: boolean) {
    if (off) return;
    irA(pos, true);
    recentrarSiHaceFalta();
    confirmar(pos);
  }

  return (
    <div className="flex flex-col items-center">
      <button
        type="button"
        aria-label={`${ariaLabel} anterior`}
        onClick={() => moverPaso(-1)}
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
        {Array.from({ length: total }, (_, pos) => {
          const logico = mod(pos, n);
          const v = valores[logico];
          const off = deshabilitado?.(v) ?? false;
          const activo = pos === posCentral;
          return (
            <div
              key={pos}
              role="option"
              aria-selected={activo}
              aria-disabled={off}
              style={{ height: ALTO_ITEM, scrollSnapAlign: "center" }}
              onClick={() => alClicItem(pos, off)}
              className={`flex items-center justify-center text-lg tabular-nums transition-all duration-150 ${
                off
                  ? "cursor-not-allowed text-pan-carbon-suave/25"
                  : activo
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
        onClick={() => moverPaso(1)}
        className="rounded-full p-1 text-pan-carbon-suave transition-colors hover:bg-pan-crema-muted hover:text-pan-carbon"
      >
        <ChevronDown className="h-4 w-4" />
      </button>
    </div>
  );
}

export interface SelectorHoraHandle {
  abrir: () => void;
}

interface SelectorHoraProps {
  id?: string;
  /** "HH:mm" en formato 24h, o "" si todavía no eligió. */
  valor: string;
  onChange: (hora: string) => void;
  placeholder?: string;
  /** "HH:mm": si se pasa, ninguna hora anterior a esta queda seleccionable
   * (usado cuando la fecha elegida es hoy, para respetar los minutos de
   * tolerancia — ver esMuyProntoHoy en utils/horariosPan.ts). Cambia solo
   * con el reloj (cada minuto), así que si el cliente deja el selector
   * abierto un buen rato, el piso lo sigue empujando hacia adelante. */
  minimoHoy?: string;
  /** false = el botón no abre este selector al tocarlo, sino que dispara
   * `onIntentoBloqueado` (usado para exigir elegir la fecha primero). */
  puedeAbrir?: boolean;
  onIntentoBloqueado?: () => void;
}

/** Selector de hora estilo rueda de celular: tres columnas (hora, minuto,
 * AM/PM) que giran sin fin hasta centrar el valor elegido, con flechas
 * para quien prefiera hacer clic. Abre en una ventana emergente con
 * Cancelar/Aceptar, para que el cliente pueda ver bien lo que eligió antes
 * de aplicarlo. */
export const SelectorHora = forwardRef<SelectorHoraHandle, SelectorHoraProps>(function SelectorHora(
  { id, valor, onChange, placeholder = "Elige una hora", minimoHoy, puedeAbrir = true, onIntentoBloqueado },
  ref,
) {
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

  useImperativeHandle(ref, () => ({ abrir }));

  function alPresionarBoton() {
    if (!puedeAbrir) {
      onIntentoBloqueado?.();
      return;
    }
    abrir();
  }

  const minutosPiso = minimoHoy ? horaTextoAMinutos(minimoHoy) : null;
  function muyPronto(hora12: number, minuto: number, periodo: Periodo): boolean {
    if (minutosPiso === null) return false;
    return horaTextoAMinutos(a24h(hora12, minuto, periodo)) < minutosPiso;
  }

  const draftInvalido = muyPronto(draftHora, draftMinuto, draftPeriodo);

  // El piso de tolerancia avanza solo con el reloj (ver `minimoHoy`, que
  // el padre recalcula cada 15s) — si el cliente se queda con la ventana
  // abierta y su elección queda por detrás del nuevo piso, la rueda gira
  // sola hasta el nuevo mínimo en vez de quedarse mostrando una hora que
  // ya no alcanza.
  useEffect(() => {
    if (!abierto || !minimoHoy) return;
    if (muyPronto(draftHora, draftMinuto, draftPeriodo)) {
      const piso = desde24h(minimoHoy);
      setDraftHora(piso.hora12);
      setDraftMinuto(piso.minuto);
      setDraftPeriodo(piso.periodo);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [minimoHoy, abierto]);

  return (
    <div className="relative">
      <button
        id={id}
        type="button"
        onClick={alPresionarBoton}
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
            <div className="flex flex-col items-center">
              {/* Mismo alto que los botones de flecha de las ruedas
                  (h-4 + p-1 de cada lado = 24px), para que el ":" quede
                  centrado en la misma franja que el valor resaltado, no
                  en el alto total de la columna (que incluye flechas). */}
              <div className="h-6 shrink-0" aria-hidden="true" />
              <div style={{ height: ALTO_RUEDA }} className="flex items-center justify-center">
                <span className="text-lg font-bold text-pan-carbon-suave">:</span>
              </div>
              <div className="h-6 shrink-0" aria-hidden="true" />
            </div>
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
              infinito={false}
            />
          </div>
        </div>
      </SelectorModal>
    </div>
  );
});
