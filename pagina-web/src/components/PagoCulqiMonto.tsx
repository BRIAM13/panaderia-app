import { useEffect, useId, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { Info, Wallet } from "lucide-react";
import {
  calcularMontoConComision,
  limpiarMonto,
  montoMinimoAPagar,
  saldoPendiente,
} from "../utils/pagoAdelanto";
import { EASE_PREMIUM } from "../utils/animacion";
import type { MetodoPagoCulqi } from "./PagoCulqiSelectorMetodo";

/**
 * El control de "¿cuánto pagas ahora?" del checkout de Culqi (`PagoCulqi.tsx`)
 * y el desglose en vivo que va debajo. Vive en su propio archivo por el mismo
 * motivo que `PagoCulqiYape.tsx`: tamaño. Quien decide el monto final, lo
 * acota al rango y lo manda al servidor sigue siendo `PagoCulqi`; esto solo
 * pinta el control y avisa cada vez que el cliente lo mueve.
 *
 * LA REGLA (decisión del dueño, 2026-09-28): el cliente puede "separar" su
 * pedido pagando AHORA cualquier monto entre la mitad del total y el total.
 * Lo que falte lo paga al recoger. Por defecto se le propone el total.
 *
 * TRES FORMAS DE ELEGIR, para tres tipos de cliente: los dos atajos ("La
 * mitad" / "Todo") para el que solo quiere separar o pagar completo y no
 * pensar más; el deslizador, para tantear "cuánto me alcanza hoy" viendo el
 * saldo moverse; y el campo de texto, para el que ya sabe la cifra exacta.
 * Los tres pasan por el mismo `onCambiar` y el padre acota SIEMPRE
 * (`acotarMontoElegido`), así que en pantalla nunca hay un número que el
 * servidor vaya a rechazar.
 *
 * El campo de texto es el único que necesita un estado propio: mientras el
 * cliente escribe "6" camino a "60" el texto tiene que poder ser "6" aunque
 * el monto efectivo (el que muestra el desglose y el botón de pagar) ya esté
 * acotado al mínimo. Al soltar el campo, el texto se reescribe con el monto
 * efectivo, así el cliente ve exactamente con qué se queda.
 */

/** Cuánto vale `montoElegido` como porcentaje del total, para el aria del
 * deslizador y la etiqueta al lado del campo. Entero, sin decimales: el
 * cliente piensa "la mitad", "más o menos dos tercios", no "66,7%". */
function porcentajeDelTotal(total: number, monto: number): number {
  if (!(total > 0)) return 100;
  return Math.round((monto / total) * 100);
}

interface SelectorMontoPagoProps {
  total: number;
  /** El monto efectivo, YA acotado por el padre. Es lo que muestra el
   * desglose y lo que va en el botón de pagar. */
  montoElegido: number;
  /** Se llama con el monto CRUDO que pidió la interacción (puede estar fuera
   * de rango); el padre lo acota. */
  onCambiar: (monto: number) => void;
  metodo: MetodoPagoCulqi;
  /** Mientras se está cobrando no se puede tocar: cambiar el monto con un
   * token en vuelo sería cobrar una cosa y mostrar otra. */
  deshabilitado: boolean;
}

export function SelectorMontoPago({ total, montoElegido, onCambiar, metodo, deshabilitado }: SelectorMontoPagoProps) {
  const minimo = montoMinimoAPagar(total) ?? total;
  const desglose = calcularMontoConComision(montoElegido);
  const montoACobrar = desglose?.montoACobrar ?? montoElegido;
  const comision = desglose?.comision ?? 0;
  const saldo = saldoPendiente(total, montoElegido);
  const pagaTodo = saldo === 0;
  const pagaMinimo = montoElegido === minimo && !pagaTodo;
  const porcentaje = porcentajeDelTotal(total, montoElegido);
  const medio = metodo === "YAPE" ? "Yape" : "tarjeta";

  // ---- Campo de texto ----
  // `texto` es lo que el cliente ve escrito; `editando` dice si tiene el
  // foco. Mientras NO lo tiene, el texto sigue al monto efectivo (que puede
  // cambiar desde el deslizador o los atajos). Mientras SÍ lo tiene, se le
  // deja escribir en paz y recién al soltar se reescribe con lo acotado.
  const [texto, setTexto] = useState(() => montoElegido.toFixed(2));
  const [editando, setEditando] = useState(false);
  useEffect(() => {
    if (!editando) setTexto(montoElegido.toFixed(2));
  }, [montoElegido, editando]);

  const valorTexto = Number(texto);
  // Aviso mientras escribe un monto por debajo del mínimo: no es un error
  // (a lo mejor va a seguir tecleando), es para que sepa por qué el desglose
  // de abajo no baja de ahí.
  const textoBajoMinimo =
    editando && texto.length > 0 && Number.isFinite(valorTexto) && valorTexto < minimo;

  function alEscribir(valor: string) {
    const limpio = limpiarMonto(valor);
    const numero = Number(limpio);
    // Por ENCIMA del total no se deja escribir: seguir tecleando solo puede
    // agrandarlo, así que se corta acá y el campo queda en el total. Por
    // DEBAJO del mínimo sí se deja (ver el encabezado): el monto efectivo se
    // acota igual del lado del padre.
    if (limpio.length > 0 && Number.isFinite(numero) && numero > total) {
      setTexto(total.toFixed(2));
      onCambiar(total);
      return;
    }
    setTexto(limpio);
    if (limpio.length > 0 && Number.isFinite(numero)) onCambiar(numero);
  }

  function alSoltar() {
    setEditando(false);
    setTexto(montoElegido.toFixed(2));
  }

  const idCampo = useId();
  const idAyuda = `${idCampo}-ayuda`;

  return (
    <section
      aria-labelledby={`${idCampo}-titulo`}
      className="rounded-2xl border border-pan-borde/40 bg-pan-crema px-4 py-3.5 sm:px-5 sm:py-4"
    >
      <div className="flex items-start gap-2.5">
        <span className="mt-0.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-lg bg-pan-terracota/10 text-pan-terracota">
          <Wallet className="h-4 w-4" strokeWidth={1.75} />
        </span>
        <div className="min-w-0 flex-1">
          <h4
            id={`${idCampo}-titulo`}
            className="font-[family-name:var(--font-display-panaderia)] text-base font-semibold text-pan-carbon sm:text-lg"
          >
            ¿Cuánto pagas ahora?
          </h4>
          <p className="mt-0.5 text-[13px] leading-snug text-pan-carbon-suave">
            Puedes separar tu pedido pagando desde la mitad. Lo que falte lo pagas al recogerlo.
          </p>
        </div>
      </div>

      {/* Campo exacto + los dos atajos. En celular van apilados (el campo
          arriba, ancho completo); desde `sm` en una fila. */}
      <div className="mt-3 flex flex-col gap-2.5 sm:flex-row sm:items-stretch">
        <div className="relative min-w-0 flex-1">
          <label htmlFor={idCampo} className="sr-only">
            Monto a pagar ahora, en soles
          </label>
          <span
            aria-hidden="true"
            className="pointer-events-none absolute inset-y-0 left-4 flex items-center text-sm font-semibold text-pan-carbon-suave"
          >
            S/
          </span>
          <input
            id={idCampo}
            inputMode="decimal"
            autoComplete="off"
            value={texto}
            onChange={(e) => alEscribir(e.target.value)}
            onFocus={() => setEditando(true)}
            onBlur={alSoltar}
            disabled={deshabilitado}
            aria-describedby={idAyuda}
            aria-invalid={textoBajoMinimo || undefined}
            className={`campo-pan select-text text-lg font-semibold tabular-nums ${
              textoBajoMinimo ? "border-amber-400" : ""
            }`}
            // El relleno va inline y no como `pl-10 pr-16`: `.campo-pan` fija
            // su `padding` en CSS sin capa, que le gana a cualquier utilidad
            // de Tailwind, y el "S/" de la izquierda y el porcentaje de la
            // derecha se pisaban con el número.
            style={{ paddingLeft: "2.5rem", paddingRight: "4.25rem" }}
          />
          {/* El porcentaje del total, como referencia rápida ("66%") — se
              anima al cambiar para que se note que respondió. */}
          <span className="pointer-events-none absolute inset-y-0 right-3.5 flex items-center">
            <AnimatePresence mode="popLayout" initial={false}>
              <motion.span
                key={porcentaje}
                initial={{ opacity: 0, y: 6 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -6 }}
                transition={{ duration: 0.18, ease: EASE_PREMIUM }}
                className="rounded-full bg-pan-terracota/10 px-2 py-0.5 text-[11px] font-bold text-pan-terracota tabular-nums"
              >
                {porcentaje}%
              </motion.span>
            </AnimatePresence>
          </span>
        </div>

        <div className="grid shrink-0 grid-cols-2 gap-2 sm:flex">
          <AtajoMonto activo={pagaMinimo} deshabilitado={deshabilitado} onClick={() => onCambiar(minimo)}>
            La mitad
          </AtajoMonto>
          <AtajoMonto activo={pagaTodo} deshabilitado={deshabilitado} onClick={() => onCambiar(total)}>
            Todo
          </AtajoMonto>
        </div>
      </div>

      <p id={idAyuda} className="mt-1.5 min-h-4 text-xs text-pan-carbon-suave" aria-live="polite">
        {textoBajoMinimo
          ? `El mínimo para separar tu pedido es S/ ${minimo.toFixed(2)}; lo ajustamos al soltar el campo.`
          : `Entre S/ ${minimo.toFixed(2)} y S/ ${total.toFixed(2)}.`}
      </p>

      {/* El deslizador va en SOLES con `step="any"`: así cualquier monto
          tecleado en el campo cae en su lugar exacto (con un `step` fijo el
          navegador lo redondearía al paso más cercano y pelearía con React).
          Las flechas del teclado mueven 1/100 del rango; el padre redondea al
          céntimo. `--progreso` pinta el tramo recorrido (ver .deslizador-pan). */}
      <div className="mt-2">
        <input
          type="range"
          min={minimo}
          max={total}
          step="any"
          value={montoElegido}
          onChange={(e) => onCambiar(Number(e.target.value))}
          disabled={deshabilitado}
          aria-label="Ajustar cuánto pagas ahora"
          aria-valuemin={minimo}
          aria-valuemax={total}
          aria-valuenow={montoElegido}
          aria-valuetext={`S/ ${montoElegido.toFixed(2)}, ${porcentaje}% del total`}
          className="deslizador-pan"
          style={
            {
              "--progreso": `${total > minimo ? ((montoElegido - minimo) / (total - minimo)) * 100 : 100}%`,
            } as React.CSSProperties
          }
        />
        <div className="flex justify-between text-[11px] font-medium text-pan-carbon-suave tabular-nums">
          <span>Mitad · S/ {minimo.toFixed(2)}</span>
          <span>Todo · S/ {total.toFixed(2)}</span>
        </div>
      </div>

      {/* ---- El desglose, en vivo ----
          Tres líneas, siempre las tres, en este orden: lo que va al pedido,
          lo que se lleva la pasarela y lo que de verdad sale de la tarjeta.
          Ese último número es el mismo del botón de pagar — si acá dijera
          una cosa y el botón otra, el cliente no sabría cuál creer. */}
      <dl className="mt-3 space-y-1.5 border-t border-pan-borde/40 pt-3 text-[13px]">
        <div className="flex items-baseline justify-between gap-3">
          <dt className="text-pan-carbon-suave">Va a tu pedido</dt>
          <dd className="font-medium text-pan-carbon tabular-nums">S/ {montoElegido.toFixed(2)}</dd>
        </div>
        <div className="flex items-baseline justify-between gap-3">
          <dt className="text-pan-carbon-suave">Comisión de la pasarela</dt>
          <dd className="font-medium text-pan-carbon tabular-nums">S/ {comision.toFixed(2)}</dd>
        </div>
        <div className="flex items-baseline justify-between gap-3 border-t border-pan-borde/40 pt-2">
          <dt className="font-semibold text-pan-carbon">Sale de tu {medio}</dt>
          <dd className="text-lg font-bold text-pan-terracota tabular-nums">
            <AnimatePresence mode="popLayout" initial={false}>
              <motion.span
                key={montoACobrar}
                initial={{ opacity: 0, y: 6 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -6 }}
                transition={{ duration: 0.18, ease: EASE_PREMIUM }}
                className="inline-block"
              >
                S/ {montoACobrar.toFixed(2)}
              </motion.span>
            </AnimatePresence>
          </dd>
        </div>
      </dl>

      {/* Por qué existe la comisión, dicho una vez y sin rodeos. */}
      <p className="mt-2.5 flex items-start gap-2 text-xs leading-relaxed text-pan-carbon-suave">
        <Info className="mt-0.5 h-3.5 w-3.5 shrink-0" strokeWidth={1.75} />
        <span>
          La comisión es lo que Culqi cobra por procesar tu pago: se la trasladamos tal cual, nosotros no nos
          quedamos con nada de eso. A tu pedido entra completo lo que elegiste.
        </span>
      </p>

      {/* El saldo, solo cuando hay: aparece y desaparece con altura animada
          para que el bloque no dé un salto. Va en ámbar (hay algo por hacer
          después), no en rojo (no es un error). */}
      <AnimatePresence initial={false}>
        {!pagaTodo && (
          <motion.div
            key="saldo"
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: "auto" }}
            exit={{ opacity: 0, height: 0 }}
            transition={{ duration: 0.22, ease: EASE_PREMIUM }}
            className="overflow-hidden"
          >
            <div
              role="status"
              className="mt-3 flex items-center justify-between gap-3 rounded-xl border border-amber-300 bg-amber-50 px-3.5 py-2.5"
            >
              <p className="text-xs leading-snug font-medium text-amber-800">Saldo pendiente al recoger</p>
              <span className="shrink-0 text-sm font-bold text-amber-800 tabular-nums">S/ {saldo.toFixed(2)}</span>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </section>
  );
}

/** Un atajo del monto ("La mitad" / "Todo"): píldora con borde, que se
 * rellena de terracota cuando el monto efectivo cae justo en ella. */
function AtajoMonto({
  activo,
  deshabilitado,
  onClick,
  children,
}: {
  activo: boolean;
  deshabilitado: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <motion.button
      type="button"
      onClick={onClick}
      disabled={deshabilitado}
      aria-pressed={activo}
      whileHover={deshabilitado ? undefined : { y: -1 }}
      whileTap={deshabilitado ? undefined : { scale: 0.96 }}
      transition={{ duration: 0.2, ease: EASE_PREMIUM }}
      className={`flex min-h-12 items-center justify-center rounded-xl border px-4 text-sm font-semibold transition-colors duration-300 disabled:cursor-not-allowed disabled:opacity-60 ${
        activo
          ? "border-pan-terracota bg-pan-terracota text-pan-crema shadow-md shadow-pan-terracota/20"
          : "border-pan-borde bg-pan-crema-suave text-pan-carbon hover:border-pan-terracota hover:text-pan-terracota"
      }`}
    >
      {children}
    </motion.button>
  );
}
