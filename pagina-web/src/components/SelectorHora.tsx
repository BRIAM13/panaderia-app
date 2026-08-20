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
// Cuántos píxeles de scroll del mouse/trackpad equivalen a "un paso" —
// una rueda de mouse estándar manda ~100px por clic/muesca, así que esto
// hace que un clic de rueda mueva exactamente un ítem, no tres o cuatro.
const UMBRAL_RUEDA_PX = 100;
// Cuánto se puede mover el cursor entre presionar y soltar y que igual
// cuente como "clic quieto" — un clic real casi nunca es 100% inmóvil
// (temblor de mano, trackpad), así que tiene que perdonar unos píxeles.
const UMBRAL_ARRASTRE_PX = 10;

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
 * mouse/trackpad (un paso por clic de rueda), con clic directo en
 * cualquier valor visible, o con los botones de flecha. Todo el
 * movimiento lo controla este componente a mano (el contenedor no usa el
 * scroll nativo del navegador) — así, cuando `deshabilitado` marca una
 * franja como inválida, es físicamente imposible llegar a mostrarla ni un
 * instante, sin importar el método usado. */
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
  const arrastrandoRef = useRef(false);
  // Distingue un clic real (sin apenas movimiento) de un arrastre — así un
  // clic sobre un ítem no compite con la lógica de asentado del arrastre.
  const arrastroRealRef = useRef(false);
  const arranqueRef = useRef({ y: 0, pos: 0 });
  const deltaAcumuladoRef = useRef(0);
  const animacionRef = useRef<number | null>(null);

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

  /** Anima el giro a mano (en vez de scrollTo del navegador) y actualiza
   * qué ítem se ve resaltado EN CADA CUADRO según la posición visual real
   * — nunca antes de que el giro llegue ahí. Ese adelanto (marcar el
   * siguiente valor en negrita mientras el giro todavía no llega) era
   * justo la causa del "salto" visual reportado: con scrollTo del
   * navegador no hay forma de saber en qué cuadro va la animación, así
   * que el resaltado se actualizaba de una, no cuando correspondía. */
  function irA(pos: number, suave: boolean) {
    const el = ref.current;
    if (!el) return;
    posRef.current = pos;
    if (animacionRef.current !== null) {
      cancelAnimationFrame(animacionRef.current);
      animacionRef.current = null;
    }
    const destinoPx = pos * ALTO_ITEM;
    if (!suave) {
      el.scrollTop = destinoPx;
      setPosCentral(pos);
      return;
    }
    const inicioPx = el.scrollTop;
    const distanciaPx = destinoPx - inicioPx;
    if (Math.abs(distanciaPx) < 0.5) {
      setPosCentral(pos);
      return;
    }
    // Duración corta y proporcional al recorrido — un solo paso se siente
    // instantáneo-pero-suave; varios pasos seguidos (flechas o clic lejos)
    // no se sienten más lentos de la cuenta.
    const duracionMs = Math.min(260, Math.max(120, Math.abs(distanciaPx) * 2.2));
    const inicioTiempo = performance.now();
    const pasoAnimacion = (ahora: number) => {
      const t = Math.min(1, (ahora - inicioTiempo) / duracionMs);
      const suavizado = 1 - (1 - t) ** 3; // ease-out cúbico
      const actualPx = inicioPx + distanciaPx * suavizado;
      el.scrollTop = actualPx;
      const posVisual = Math.round(actualPx / ALTO_ITEM);
      setPosCentral((anterior) => (anterior === posVisual ? anterior : posVisual));
      if (t < 1) {
        animacionRef.current = requestAnimationFrame(pasoAnimacion);
      } else {
        animacionRef.current = null;
        setPosCentral(pos);
      }
    };
    animacionRef.current = requestAnimationFrame(pasoAnimacion);
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
      if (animacionRef.current !== null) {
        cancelAnimationFrame(animacionRef.current);
        animacionRef.current = null;
      }
      const destino = copiaMedia * n + mod(pos, n);
      posRef.current = destino;
      el.scrollTop = destino * ALTO_ITEM;
      setPosCentral(destino);
    }
  }

  // Al montar, el navegador arranca con scrollTop en 0 — no coincide con
  // la copia "del medio" que elegimos como posición inicial (posInicial),
  // así que hay que alinear el scroll real una sola vez, sin animación.
  useEffect(() => {
    irA(posRef.current, false);
    return () => {
      if (animacionRef.current !== null) cancelAnimationFrame(animacionRef.current);
    };
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

  /** Asienta en el ítem más cercano a donde quedó el arrastre (puede
   * caer en una fracción de ítem) y lo confirma. */
  function asentarTrasArrastre() {
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

  function moverPaso(direccion: 1 | -1) {
    const limites = calcularLimites(posRef.current);
    const destino = posRef.current + direccion;
    if (direccion < 0 && limites.min !== -Infinity && destino < limites.min) return;
    if (direccion > 0 && limites.max !== Infinity && destino > limites.max) return;
    irA(destino, true);
    recentrarSiHaceFalta();
    confirmar(destino);
  }

  // El contenedor no usa el scroll nativo del navegador (overflow-hidden):
  // todo el movimiento pasa por acá, nunca compite con el navegador ni se
  // corrige después de mostrarse mal — es imposible dejarlo, ni un
  // instante, en una posición inválida.
  function alWheel(e: React.WheelEvent) {
    e.preventDefault();
    deltaAcumuladoRef.current += e.deltaY;
    let pasos = 0;
    while (Math.abs(deltaAcumuladoRef.current) >= UMBRAL_RUEDA_PX && pasos < 12) {
      const direccion = deltaAcumuladoRef.current > 0 ? 1 : -1;
      deltaAcumuladoRef.current -= direccion * UMBRAL_RUEDA_PX;
      moverPaso(direccion);
      pasos += 1;
    }
  }

  function alPointerDown(e: React.PointerEvent) {
    const el = ref.current;
    if (!el) return;
    arrastrandoRef.current = true;
    arrastroRealRef.current = false;
    arranqueRef.current = { y: e.clientY, pos: posRef.current };
    el.setPointerCapture(e.pointerId);
  }
  function alPointerMove(e: React.PointerEvent) {
    if (!arrastrandoRef.current || !ref.current) return;
    const deltaPx = e.clientY - arranqueRef.current.y;
    // Todavía dentro del margen de "clic con temblor" — no mueve nada
    // hasta que el gesto realmente se confirme como arrastre.
    if (!arrastroRealRef.current && Math.abs(deltaPx) < UMBRAL_ARRASTRE_PX) return;
    arrastroRealRef.current = true;
    if (animacionRef.current !== null) {
      cancelAnimationFrame(animacionRef.current);
      animacionRef.current = null;
    }
    let posFlot = arranqueRef.current.pos - deltaPx / ALTO_ITEM;
    const { min, max } = calcularLimites(arranqueRef.current.pos);
    if (min !== -Infinity) posFlot = Math.max(posFlot, min);
    if (max !== Infinity) posFlot = Math.min(posFlot, max);
    posRef.current = Math.round(posFlot);
    ref.current.scrollTop = posFlot * ALTO_ITEM;
    // El resaltado sigue el dedo/mouse en vivo, igual que durante una
    // animación — nunca se adelanta ni se atrasa respecto a lo que se ve.
    setPosCentral((anterior) => (anterior === posRef.current ? anterior : posRef.current));
  }
  function alPointerUp(e: React.PointerEvent) {
    if (!arrastrandoRef.current) return;
    arrastrandoRef.current = false;
    if (arrastroRealRef.current) {
      asentarTrasArrastre();
      return;
    }
    // Fue un clic quieto (sin arrastre real): acá mismo se calcula, con
    // las coordenadas, qué ítem quedó bajo el cursor al soltar — nunca se
    // usa el evento 'click' del navegador. Con el puntero capturado (hace
    // falta para que el arrastre no se corte si el cursor sale del
    // contenedor), Chrome reasigna ese 'click' al contenedor completo, no
    // al ítem tocado, así que el clic nunca llegaba a su manejador.
    const el = ref.current;
    if (!el) return;
    const rect = el.getBoundingClientRect();
    const offsetEnContenido = e.clientY - rect.top + el.scrollTop;
    const pos = Math.floor((offsetEnContenido - RELLENO) / ALTO_ITEM);
    if (estaDeshabilitado(pos)) return;
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
        onWheel={alWheel}
        onPointerDown={alPointerDown}
        onPointerMove={alPointerMove}
        onPointerUp={alPointerUp}
        onPointerCancel={alPointerUp}
        style={{ height: ALTO_RUEDA, paddingTop: RELLENO, paddingBottom: RELLENO }}
        className="w-16 cursor-grab touch-none select-none overflow-hidden active:cursor-grabbing"
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
              style={{ height: ALTO_ITEM }}
              className={`flex items-center justify-center rounded-lg text-lg tabular-nums transition-all duration-150 ${
                off
                  ? "cursor-not-allowed text-pan-carbon-suave/25"
                  : activo
                    ? "scale-110 font-bold text-pan-terracota"
                    : "cursor-pointer text-pan-carbon-suave/70 hover:bg-pan-terracota-suave/25 hover:text-pan-carbon"
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
  /** "HH:mm": si se pasa, ninguna hora después de esta queda seleccionable
   * (el negocio ya cerró para recoger hoy — ver esMuyTardeHoy). A
   * diferencia de `minimoHoy`, este no cambia con el reloj. */
  maximoHoy?: string;
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
  { id, valor, onChange, placeholder = "Elige una hora", minimoHoy, maximoHoy, puedeAbrir = true, onIntentoBloqueado },
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
  const minutosTope = maximoHoy ? horaTextoAMinutos(maximoHoy) : null;
  function muyPronto(hora12: number, minuto: number, periodo: Periodo): boolean {
    const totalMinutos = horaTextoAMinutos(a24h(hora12, minuto, periodo));
    if (minutosPiso !== null && totalMinutos < minutosPiso) return true;
    if (minutosTope !== null && totalMinutos > minutosTope) return true;
    return false;
  }

  const draftInvalido = muyPronto(draftHora, draftMinuto, draftPeriodo);

  // El piso de tolerancia avanza solo con el reloj (ver `minimoHoy`, que
  // el padre recalcula cada 15s) — si el cliente se queda con la ventana
  // abierta y su elección queda por detrás del nuevo piso, la rueda gira
  // sola hasta el nuevo mínimo en vez de quedarse mostrando una hora que
  // ya no alcanza. Pero si ese mismo avance del reloj ya cruzó el tope
  // (piso > tope: ya no queda ningún minuto válido hoy), no hay a dónde
  // girar — el selector se cierra solo en vez de quedar trabado
  // mostrando un rango imposible con "Aceptar" deshabilitado para
  // siempre.
  useEffect(() => {
    if (!abierto || !minimoHoy) return;
    if (minutosTope !== null && horaTextoAMinutos(minimoHoy) > minutosTope) {
      setAbierto(false);
      return;
    }
    if (muyPronto(draftHora, draftMinuto, draftPeriodo)) {
      const piso = desde24h(minimoHoy);
      setDraftHora(piso.hora12);
      setDraftMinuto(piso.minuto);
      setDraftPeriodo(piso.periodo);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [minimoHoy, maximoHoy, abierto]);

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
            {maximoHoy
              ? `Para hoy, puedes elegir entre las ${formatearHora12(minimoHoy)} y las ${formatearHora12(maximoHoy)}.`
              : `Para hoy, lo más pronto que puedes elegir es ${formatearHora12(minimoHoy)}.`}
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
