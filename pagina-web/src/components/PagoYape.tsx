import { useEffect, useRef, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import {
  AlertTriangle,
  Check,
  CheckCircle2,
  Copy,
  Loader2,
  QrCode,
  ShieldCheck,
  Smartphone,
} from "lucide-react";
import {
  ApiError,
  obtenerMedioPagoPublico,
  registrarCodigoPago,
  type MedioPagoPublico,
} from "../services/api";
import {
  LARGO_MAXIMO_CODIGO,
  limpiarCodigoOperacion,
  limpiarMonto,
  montoSugerido,
  revisarMontoDeclarado,
} from "../utils/pagoAdelanto";
import { EASE_PREMIUM } from "../utils/animacion";

interface PagoYapeProps {
  /** El pedido YA existe: se creó al terminar el formulario, antes de pagar. */
  idPedido: number;
  numeroPedidoDia: number;
  total: number;
  /** El que devolvió la creación del pedido. Se omite cuando se llega desde
   * el seguimiento por DNI en otro dispositivo — ahí viaja `documento`. */
  token?: string;
  documento?: string;
  /** Se avisa hacia arriba cuando el código ya quedó registrado. */
  onCodigoRegistrado: () => void;
  /** Salida del paso sin mandar código (ej. "lo hago después"). Opcional:
   * la vista de seguimiento la usa para volver a la lista. */
  onCancelar?: () => void;
  /** Qué texto lleva el botón de salida, según desde dónde se abrió. */
  etiquetaCancelar?: string;
  /** Compacto se usa dentro del panel de seguimiento, que ya tiene su
   * propio encabezado y menos ancho. */
  compacto?: boolean;
}

/**
 * La pantalla de pago del pedido de Panadería: a dónde yapear (QR + número
 * con botón de copiar) y dónde escribir el código de operación que Yape
 * devuelve después de pagar.
 *
 * Es un paso propio y no dos campos al final del formulario por lo mismo
 * que el pedido se crea antes de llegar acá: pagar obliga a salir del
 * navegador, y volver con media pantalla de campos a medio llenar es la
 * peor forma posible de retomar. Acá el pedido ya está hecho y lo único que
 * queda es pegar un número.
 */
export function PagoYape({
  idPedido,
  numeroPedidoDia,
  total,
  token,
  documento,
  onCodigoRegistrado,
  onCancelar,
  etiquetaCancelar = "Lo pago después",
  compacto = false,
}: PagoYapeProps) {
  const [medioPago, setMedioPago] = useState<MedioPagoPublico | null>(null);
  const [cargandoMedio, setCargandoMedio] = useState(true);
  const [codigo, setCodigo] = useState("");
  // Arranca con el total exacto escrito: es lo que va a pagar casi todo el
  // mundo, así que la mayoría no tiene que teclear nada acá. Quien redondeó
  // hacia arriba solo corrige la cifra.
  const [monto, setMonto] = useState(() => montoSugerido(total));
  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [copiado, setCopiado] = useState(false);

  const tituloRef = useRef<HTMLHeadingElement>(null);
  useEffect(() => {
    // Igual que en la pantalla de éxito: quien navega con teclado o lector
    // de pantalla necesita que se le anuncie que el formulario ya no está.
    const id = window.setTimeout(() => tituloRef.current?.focus(), 250);
    return () => window.clearTimeout(id);
  }, []);

  useEffect(() => {
    let vigente = true;
    obtenerMedioPagoPublico("panaderia")
      .then((medio) => {
        if (vigente) setMedioPago(medio);
      })
      .catch(() => {
        // Sin medio de pago cargado se muestra el mismo estado que cuando el
        // dueño todavía no configuró ninguno: el pedido YA está registrado,
        // así que el cliente nunca queda con las manos vacías.
        if (vigente) setMedioPago(null);
      })
      .finally(() => {
        if (vigente) setCargandoMedio(false);
      });
    return () => {
      vigente = false;
    };
  }, []);

  // El "copiado" vuelve solo a su estado normal: es una confirmación, no un
  // modo en el que quedarse.
  useEffect(() => {
    if (!copiado) return;
    const id = window.setTimeout(() => setCopiado(false), 2000);
    return () => window.clearTimeout(id);
  }, [copiado]);

  async function copiarNumero() {
    if (!medioPago) return;
    try {
      await navigator.clipboard.writeText(medioPago.numeroDestino);
      setCopiado(true);
    } catch {
      // Sin permiso de portapapeles (o navegador viejo) no se rompe nada: el
      // número sigue a la vista para escribirlo a mano.
      setError("No pudimos copiar el número. Anótalo de la pantalla, por favor.");
    }
  }

  async function enviar(e: React.FormEvent) {
    e.preventDefault();
    setError(null);

    const codigoLimpio = limpiarCodigoOperacion(codigo);
    if (codigoLimpio.length === 0) {
      setError("Escribe el código de operación que te dio Yape.");
      return;
    }
    const problemaMonto = revisarMontoDeclarado(total, monto);
    if (problemaMonto) {
      setError(problemaMonto);
      return;
    }

    setEnviando(true);
    try {
      await registrarCodigoPago({
        idPedido,
        token,
        documento,
        codigoOperacionYape: codigoLimpio,
        montoDeclaradoCliente: Number(monto),
      });
      onCodigoRegistrado();
    } catch (err) {
      if (err instanceof ApiError) {
        setError(err.errores?.join(" ") || err.message);
      } else {
        setError(
          "No pudimos conectar porque el servidor puede estar despertando. Tu pedido sigue guardado: intenta de nuevo en un momento.",
        );
      }
    } finally {
      setEnviando(false);
    }
  }

  return (
    <motion.div
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.35, ease: EASE_PREMIUM }}
      className={compacto ? "" : "py-2"}
    >
      {/* El pedido ya entró: eso se dice PRIMERO, antes de pedir nada más.
          Quien llegó acá ya hizo su parte del formulario y necesita saber
          que no está en el aire mientras va a Yape. */}
      <div className="text-center">
        <motion.span
          initial={{ scale: 0 }}
          animate={{ scale: 1 }}
          transition={{ type: "spring", stiffness: 260, damping: 16, delay: 0.05 }}
          className="mx-auto flex h-12 w-12 items-center justify-center rounded-2xl bg-emerald-100 text-emerald-700"
        >
          <CheckCircle2 className="h-6 w-6" strokeWidth={1.8} />
        </motion.span>
        <h3
          ref={tituloRef}
          tabIndex={-1}
          className="mt-3 font-[family-name:var(--font-display-panaderia)] text-xl font-semibold text-pan-carbon outline-none sm:text-2xl"
        >
          Pedido #{numeroPedidoDia} registrado
        </h3>
        <p className="mt-1.5 text-sm leading-relaxed text-pan-carbon-suave">
          Solo falta el pago. Yapéanos{" "}
          <span className="font-semibold text-pan-terracota">S/ {total.toFixed(2)}</span> y vuelve
          acá con tu código de operación.
        </p>
      </div>

      <div className="mt-5 rounded-2xl border border-pan-borde/40 bg-pan-crema px-4 py-4 sm:px-5">
        {cargandoMedio ? (
          <div className="flex flex-col items-center gap-3" aria-hidden="true">
            <div className="esqueleto h-44 w-44 rounded-2xl" />
            <div className="esqueleto h-11 w-full rounded-xl" />
          </div>
        ) : medioPago ? (
          <>
            {medioPago.imagenQrBase64 ? (
              <div className="flex flex-col items-center">
                <div className="rounded-2xl border border-pan-borde/50 bg-white p-3 shadow-sm">
                  {/* Grande a propósito: el cliente le va a sacar captura
                      para escanearlo desde la galería de Yape. */}
                  <img
                    src={`data:image/png;base64,${medioPago.imagenQrBase64}`}
                    alt={`Código QR de ${medioPago.tipo} de ${medioPago.titular}`}
                    className="h-52 w-52 object-contain sm:h-60 sm:w-60"
                  />
                </div>
                <p className="mt-2 text-xs text-pan-carbon-suave">
                  Escanéalo desde Yape o guárdalo en tu galería.
                </p>
              </div>
            ) : (
              // Sin QR real cargado, el número sigue alcanzando para pagar.
              // Antes que un recuadro vacío, se dice qué hacer.
              <div className="flex items-start gap-2.5 rounded-xl border border-pan-borde/50 bg-pan-crema-suave px-4 py-3">
                <QrCode className="mt-0.5 h-4 w-4 shrink-0 text-pan-bronce-oscuro" strokeWidth={1.75} />
                <p className="text-xs leading-relaxed text-pan-carbon-suave">
                  Busca este número en Yape para pagar — todavía no tenemos el QR cargado.
                </p>
              </div>
            )}

            <div className="mt-4 rounded-xl border border-pan-borde/50 bg-pan-crema-suave px-4 py-3">
              <p className="text-[11px] font-semibold tracking-[0.14em] text-pan-carbon-suave uppercase">
                {medioPago.tipo === "YAPE" ? "Yape" : medioPago.tipo} a
              </p>
              <div className="mt-1 flex flex-wrap items-center justify-between gap-x-3 gap-y-2">
                <span className="flex min-w-0 items-center gap-2">
                  <Smartphone className="h-4 w-4 shrink-0 text-pan-terracota" strokeWidth={1.75} />
                  <span className="truncate text-lg font-semibold tracking-wide tabular-nums text-pan-carbon">
                    {medioPago.numeroDestino}
                  </span>
                </span>
                <button
                  type="button"
                  onClick={copiarNumero}
                  className="inline-flex min-h-11 shrink-0 items-center gap-1.5 rounded-full border border-pan-terracota/30 bg-pan-terracota-suave/40 px-4 text-sm font-semibold text-pan-terracota-profundo transition-colors hover:bg-pan-terracota-suave/70"
                >
                  <AnimatePresence mode="wait" initial={false}>
                    {copiado ? (
                      <motion.span
                        key="copiado"
                        initial={{ scale: 0.6, opacity: 0 }}
                        animate={{ scale: 1, opacity: 1 }}
                        exit={{ scale: 0.6, opacity: 0 }}
                        transition={{ duration: 0.15 }}
                        className="flex items-center gap-1.5"
                      >
                        <Check className="h-3.5 w-3.5" strokeWidth={2.4} />
                        Copiado
                      </motion.span>
                    ) : (
                      <motion.span
                        key="copiar"
                        initial={{ scale: 0.6, opacity: 0 }}
                        animate={{ scale: 1, opacity: 1 }}
                        exit={{ scale: 0.6, opacity: 0 }}
                        transition={{ duration: 0.15 }}
                        className="flex items-center gap-1.5"
                      >
                        <Copy className="h-3.5 w-3.5" strokeWidth={2} />
                        Copiar
                      </motion.span>
                    )}
                  </AnimatePresence>
                </button>
              </div>
              <p className="mt-1 truncate text-xs text-pan-carbon-suave">
                A nombre de {medioPago.titular}
              </p>
              {medioPago.notas && (
                <p className="mt-1 text-xs leading-relaxed text-pan-carbon-suave">{medioPago.notas}</p>
              )}
            </div>
          </>
        ) : (
          // `MediosPagoTienda` sin ninguna fila activa para Panadería. El
          // pedido ya está registrado, así que esto NO es un callejón sin
          // salida: se le dice al cliente que lo coordinamos por WhatsApp.
          <div className="flex items-start gap-2.5 rounded-xl border border-amber-300 bg-amber-50 px-4 py-3">
            <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-amber-600" strokeWidth={1.75} />
            <p className="text-xs leading-relaxed font-medium text-amber-800">
              Todavía no habilitamos el pago por Yape en la web. Tu pedido #{numeroPedidoDia} ya quedó
              registrado: te escribimos por WhatsApp al número que dejaste para coordinar el pago y el
              recojo.
            </p>
          </div>
        )}
      </div>

      {/* El formulario de código solo tiene sentido si hay a dónde pagar. */}
      {!cargandoMedio && medioPago && (
        <form onSubmit={enviar} className="mt-5 space-y-4">
          <div>
            <label htmlFor="codigo-operacion" className="mb-1.5 block text-sm font-medium text-pan-carbon">
              Código de operación
            </label>
            <p className="mb-2 text-xs leading-relaxed text-pan-carbon-suave">
              Una vez hecho el pago, Yape te muestra una constancia con un número de operación.
              Escríbelo acá para que podamos confirmar tu pedido.
            </p>
            <input
              id="codigo-operacion"
              inputMode="numeric"
              autoComplete="off"
              maxLength={LARGO_MAXIMO_CODIGO}
              value={codigo}
              // Solo dígitos, igual que el DNI y el celular del formulario:
              // una letra pegada por error no llega ni a intentarse.
              onChange={(e) => {
                setCodigo(limpiarCodigoOperacion(e.target.value));
                setError(null);
              }}
              placeholder="Ej: 1234567"
              required
              className="campo-pan tracking-widest tabular-nums"
            />
          </div>

          <div>
            <label htmlFor="monto-pagado" className="mb-1.5 block text-sm font-medium text-pan-carbon">
              ¿Cuánto pagaste? <span className="font-normal text-pan-carbon-suave">(S/)</span>
            </label>
            {/* La moneda va en la etiqueta y no como prefijo dentro del
                campo: `.campo-pan` fija su propio `padding` en una regla sin
                capa, que le gana a cualquier `pl-*` de Tailwind, así que un
                prefijo absoluto se montaba encima de la cifra. */}
            <input
              id="monto-pagado"
              inputMode="decimal"
              value={monto}
              onChange={(e) => {
                setMonto(limpiarMonto(e.target.value));
                setError(null);
              }}
              required
              className="campo-pan tabular-nums"
            />
            <p className="mt-1.5 text-xs text-pan-carbon-suave">
              Ya está puesto el total de tu pedido. Cámbialo solo si yapeaste otra cantidad.
            </p>
          </div>

          <AnimatePresence>
            {error && (
              <motion.div
                initial={{ opacity: 0, height: 0 }}
                animate={{ opacity: 1, height: "auto" }}
                exit={{ opacity: 0, height: 0 }}
                transition={{ duration: 0.22, ease: EASE_PREMIUM }}
                role="alert"
                className="overflow-hidden"
              >
                <div className="flex items-start gap-2.5 rounded-xl border border-red-200 bg-red-50 px-4 py-3">
                  <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-red-600" strokeWidth={1.75} />
                  <p className="text-sm font-medium text-red-700">{error}</p>
                </div>
              </motion.div>
            )}
          </AnimatePresence>

          <motion.button
            type="submit"
            disabled={enviando}
            whileHover={enviando ? undefined : { scale: 1.02, y: -1 }}
            whileTap={enviando ? undefined : { scale: 0.98 }}
            className="flex w-full items-center justify-center gap-2 rounded-full bg-pan-terracota px-6 py-3.5 font-semibold text-pan-crema shadow-lg shadow-pan-terracota/20 transition-shadow hover:shadow-xl hover:shadow-pan-terracota/30 disabled:opacity-60"
          >
            {enviando ? (
              <>
                <Loader2 className="h-4 w-4 animate-spin" />
                Enviando…
              </>
            ) : (
              "Ya pagué, confirmar"
            )}
          </motion.button>

          <p className="flex items-start gap-2 text-xs leading-relaxed text-pan-carbon-suave">
            <ShieldCheck className="mt-0.5 h-3.5 w-3.5 shrink-0 text-emerald-600" strokeWidth={1.75} />
            Revisamos el pago a mano contra nuestro Yape. Si pagaste de más te devolvemos el vuelto al
            recoger, y si faltó algo lo completas ahí mismo.
          </p>
        </form>
      )}

      {onCancelar && (
        <button
          type="button"
          onClick={onCancelar}
          className="mx-auto mt-4 flex min-h-11 items-center rounded-full px-4 text-sm font-semibold text-pan-carbon-suave transition-colors hover:text-pan-carbon"
        >
          {etiquetaCancelar}
        </button>
      )}
    </motion.div>
  );
}

