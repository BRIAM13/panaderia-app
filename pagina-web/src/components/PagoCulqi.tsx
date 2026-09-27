import { useEffect, useRef, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { AlertTriangle, CreditCard, Loader2, Lock, Mail, ShieldCheck } from "lucide-react";
import {
  cvcEnmascarado,
  cvcValido,
  detectarMarca,
  emailValido,
  expiracionValida,
  formatearExpiracion,
  formatearNombreTitular,
  formatearNumeroTarjeta,
  limpiarCvc,
  limpiarEmail,
  nombreTitularValido,
  numeroTarjetaEnmascarado,
  numeroTarjetaValidoLuhn,
  partesExpiracion,
  soloDigitos,
  type MarcaTarjeta,
} from "../utils/tarjeta";
import { EASE_PREMIUM } from "../utils/animacion";

/**
 * Lo mínimo de la API global de CulqiJS v4 que este componente usa. La
 * biblioteca no publica tipos propios y trabaja pegada al DOM (lee/escribe
 * sobre `window.Culqi`), así que esto es un contrato local, no el SDK real.
 *
 * Fuente: `https://checkout.culqi.com/js/v4` + el flujo confirmado en los
 * demos oficiales de Culqi (`culqi/culqi-reactjs-demo-jsv4` y
 * `culqi/culqi-php-demo-jsv4-culqi3ds`, GitHub) — ver el reporte de este
 * componente para el detalle exacto de cada método.
 */
interface CulqiTokenResultado {
  object?: string;
  id: string;
  email?: string;
}
interface CulqiErrorResultado {
  user_message?: string;
  merchant_message?: string;
}
interface CulqiOpcionDePago {
  available: boolean;
  message?: string;
  generate: () => void;
}
interface CulqiGlobal {
  publicKey: string;
  init: () => void;
  settings: (opciones: { currency: string; amount: number }) => void;
  validationPaymentMethods: () => void;
  paymentOptionsAvailable?: { token?: CulqiOpcionDePago };
  token?: CulqiTokenResultado;
  error?: CulqiErrorResultado;
}

declare global {
  interface Window {
    Culqi?: CulqiGlobal;
    /** CulqiJS v4 no usa promesas: cuando termina de tokenizar (bien o mal)
     * invoca esta función global fija, así que hay que tenerla puesta ANTES
     * de pedirle que genere el token. */
    culqi?: () => void;
  }
}

const URL_SCRIPT_CULQI = "https://checkout.culqi.com/js/v4";

interface PagoCulqiProps {
  /** No se usa dentro de este componente — es una vista aislada que no
   * habla con el backend. Se acepta igual, por simetría con `PagoYape` y
   * para quien lo integre más adelante (ej. correlacionar un log). */
  idPedido: number;
  numeroPedidoDia: number;
  total: number;
  /** Se llama DESPUÉS de que Culqi.js tokenizó la tarjeta con éxito. Este
   * componente no sabe nada de pedidos ni de backend: lo que pase con el
   * token (cobrar, guardar, reintentar) es responsabilidad de quien lo usa.
   * Mientras la promesa no resuelve se muestra el estado de carga, y si se
   * rechaza, se muestra el mensaje de error que traiga. */
  onTokenGenerado: (culqiTokenId: string, datosTarjeta: { email: string }) => Promise<void>;
  onCancelar?: () => void;
  etiquetaCancelar?: string;
  compacto?: boolean;
}

/**
 * Checkout de pago con tarjeta (Culqi) para Panadería: vista previa de
 * tarjeta en vivo + resumen a la izquierda, formulario a la derecha.
 *
 * Todo lo de la tarjeta (Luhn, marca, formato, expiración) vive en
 * `utils/tarjeta.ts`, puro y ya probado — acá solo queda la parte que sí
 * necesita DOM: pintar la tarjeta, sincronizar los campos que CulqiJS v4
 * necesita leer del formulario, y envolver su callback global en una
 * promesa para poder usar async/await limpio.
 */
export function PagoCulqi({
  numeroPedidoDia,
  total,
  onTokenGenerado,
  onCancelar,
  etiquetaCancelar = "Cancelar",
  compacto = false,
}: PagoCulqiProps) {
  const [nombreTitular, setNombreTitular] = useState("");
  const [numero, setNumero] = useState("");
  const [expiracion, setExpiracion] = useState("");
  const [cvc, setCvc] = useState("");
  const [email, setEmail] = useState("");
  // Vive solo en esta pantalla: guardar la tarjeta de verdad (vaulting) es
  // trabajo del backend, todavía sin construir. No bloquea ni cambia nada
  // del pago — es la intención del cliente, a la espera de que exista dónde
  // guardarla.
  const [guardarTarjeta, setGuardarTarjeta] = useState(false);

  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [culqiListo, setCulqiListo] = useState(false);
  const [errorCarga, setErrorCarga] = useState<string | null>(null);
  // Mientras el campo CVC tiene el foco (mouse, toque O teclado — va por
  // onFocus/onBlur, no por hover), la tarjeta de vista previa se da vuelta
  // y muestra el reverso, que es donde de verdad está impreso el CVC.
  const [cvcEnfocado, setCvcEnfocado] = useState(false);

  const marca: MarcaTarjeta = detectarMarca(numero);

  const tituloRef = useRef<HTMLHeadingElement>(null);
  useEffect(() => {
    // Mismo motivo que en PagoYape/ResumenPedidoExito: quien navega con
    // teclado o lector de pantalla necesita que se le anuncie esta pantalla.
    const id = window.setTimeout(() => tituloRef.current?.focus(), 250);
    return () => window.clearTimeout(id);
  }, []);

  // La clave pública se configura recién cuando el dueño tenga su cuenta
  // Culqi lista. Sin ella, no tiene sentido ni cargar el script: se avisa
  // claro en vez de dejar que la pantalla se rompa a medias.
  const publicKey = import.meta.env.VITE_CULQI_PUBLIC_KEY as string | undefined;
  const culqiConfigurado = Boolean(publicKey && publicKey.trim().length > 0);

  // Carga del script de Culqi — inyectado a mano y con su propio cleanup,
  // porque este componente no siempre está en pantalla: no tiene sentido
  // que TODA la web cargue el checkout de Culqi solo por si alguien llega a
  // pagar con tarjeta.
  useEffect(() => {
    if (!culqiConfigurado) return;
    let vigente = true;
    const script = document.createElement("script");
    script.src = URL_SCRIPT_CULQI;
    script.async = true;

    function alCargar() {
      const Culqi = window.Culqi;
      if (!vigente || !Culqi) return;
      Culqi.publicKey = publicKey as string;
      Culqi.init();
      setCulqiListo(true);
    }
    function alFallar() {
      if (vigente) {
        setErrorCarga("No pudimos cargar el sistema de pagos. Revisa tu conexión e intenta de nuevo.");
      }
    }

    script.addEventListener("load", alCargar);
    script.addEventListener("error", alFallar);
    document.body.appendChild(script);

    return () => {
      vigente = false;
      script.removeEventListener("load", alCargar);
      script.removeEventListener("error", alFallar);
      document.body.removeChild(script);
      delete window.culqi;
    };
    // publicKey no cambia durante la vida de este componente (viene de una
    // variable de entorno fija) — solo importa una vez, al montar.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [culqiConfigurado]);

  // El monto se le avisa a Culqi en céntimos enteros (S/ 17.50 -> 1750),
  // igual que hace el backend con el pago por Yape (ver utils/pagoAdelanto).
  useEffect(() => {
    const Culqi = window.Culqi;
    if (!culqiListo || !Culqi) return;
    Culqi.settings({ currency: "PEN", amount: Math.round(total * 100) });
  }, [culqiListo, total]);

  /**
   * Todo lo que hay que revisar ANTES de gastar un viaje a Culqi. Es la
   * misma idea que la validación de PedidoForm: atrapar el error de tecleo
   * obvio acá, no después de un viaje de ida y vuelta.
   */
  function validar(): string | null {
    if (nombreTitular.trim().length === 0) {
      return "Escribe el nombre del titular de la tarjeta.";
    }
    // El campo ya no deja escribir números, símbolos ni espacios de más (ver
    // `formatearNombreTitular`), así que lo único que queda por revisar acá
    // es lo que sí se puede teclear pero no alcanza: una sola palabra.
    if (!nombreTitularValido(nombreTitular)) {
      return "Escribe tu nombre y apellido, tal como figuran en tu tarjeta.";
    }
    const numeroLimpio = soloDigitos(numero);
    if (numeroLimpio.length < 12) {
      return "Ingresa un número de tarjeta válido.";
    }
    if (!numeroTarjetaValidoLuhn(numeroLimpio)) {
      return "El número de tarjeta no es válido. Revísalo, por favor.";
    }
    if (!expiracionValida(expiracion)) {
      return "La fecha de expiración no es válida, o la tarjeta ya venció.";
    }
    if (!cvcValido(cvc)) {
      return "Ingresa un CVC válido (3 o 4 dígitos).";
    }
    if (!emailValido(email)) {
      return "Ingresa un correo electrónico válido.";
    }
    return null;
  }

  /**
   * CulqiJS v4 no trabaja con promesas: lee los datos directamente de los
   * campos del formulario (por su `id`/`name`, ver los inputs de abajo) y,
   * al terminar, llama a una función global fija — `window.culqi()` — en
   * vez de resolver algo que este componente pueda esperar. Esto envuelve
   * ese callback en una promesa para poder seguir usando async/await.
   */
  function generarTokenCulqi(): Promise<{ tokenId: string; email: string }> {
    return new Promise((resolve, reject) => {
      const Culqi = window.Culqi;
      if (!Culqi) {
        reject(new Error("El sistema de pagos todavía no está listo. Espera un momento e intenta de nuevo."));
        return;
      }
      Culqi.token = undefined;
      Culqi.error = undefined;

      window.culqi = () => {
        if (Culqi.token && Culqi.token.object === "token") {
          resolve({ tokenId: Culqi.token.id, email: Culqi.token.email ?? email.trim() });
        } else {
          reject(
            new Error(
              Culqi.error?.user_message ??
                Culqi.error?.merchant_message ??
                "No pudimos procesar tu tarjeta. Revisa los datos e intenta de nuevo.",
            ),
          );
        }
      };

      Culqi.validationPaymentMethods();
      const opcionToken = Culqi.paymentOptionsAvailable?.token;
      if (!opcionToken?.available) {
        reject(new Error(opcionToken?.message ?? "El pago con tarjeta no está disponible en este momento."));
        return;
      }
      opcionToken.generate();
    });
  }

  async function enviar(e: React.FormEvent) {
    e.preventDefault();
    setError(null);

    const problema = validar();
    if (problema) {
      setError(problema);
      return;
    }
    if (!culqiListo) {
      setError("Los pagos con tarjeta todavía se están cargando. Espera un instante e intenta de nuevo.");
      return;
    }

    setEnviando(true);
    try {
      const { tokenId, email: emailToken } = await generarTokenCulqi();
      await onTokenGenerado(tokenId, { email: emailToken });
    } catch (err) {
      setError(err instanceof Error ? err.message : "No pudimos procesar el pago. Intenta de nuevo.");
    } finally {
      setEnviando(false);
    }
  }

  const { mes: mesExpiracion, anio: anioExpiracion } = partesExpiracion(expiracion);
  const ultimosCuatro = soloDigitos(numero).slice(-4);

  return (
    // `select-none` en toda la pantalla: que arrastrar el mouse (o el dedo)
    // no pinte de celeste títulos, montos ni el texto del botón, como en
    // cualquier checkout nativo. Los campos de formulario lo revierten uno
    // por uno con `select-text` — ahí seleccionar para corregir sí es parte
    // de escribir.
    <motion.div
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.35, ease: EASE_PREMIUM }}
      className="select-none"
    >
      {/* El número de pedido NO va acá a propósito: el dueño pidió que
          aparezca una sola vez, abajo, pegado al monto que hay que pagar. */}
      <h3
        ref={tituloRef}
        tabIndex={-1}
        className="font-[family-name:var(--font-display-panaderia)] text-xl font-semibold text-pan-carbon outline-none sm:text-2xl"
      >
        Paga con tu tarjeta
      </h3>
      <p className="mt-1 text-sm leading-relaxed text-pan-carbon-suave">
        Crédito o débito, en un solo paso. Tus datos van directo a Culqi, nunca pasan por nuestros
        servidores.
      </p>

      {!culqiConfigurado ? (
        <div className="mt-5 flex items-start gap-2.5 rounded-xl border border-amber-300 bg-amber-50 px-4 py-3">
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-amber-600" strokeWidth={1.75} />
          <p className="text-xs leading-relaxed font-medium text-amber-800">
            Pagos con tarjeta no están configurados todavía. Escríbenos y coordinamos el pago por otro
            medio mientras lo activamos.
          </p>
        </div>
      ) : (
        <div className="mt-4">
          {/* Dos columnas desde `sm:` (en modo compacto, el panel angosto de
              "mis pedidos", siempre una sola). La izquierda son dos filas:
              la tarjeta (alto fijo por su proporción) y el panel de resumen,
              que ocupa TODO el alto que sobra hasta el pie del formulario de
              la derecha — así la columna termina exactamente donde termina
              el formulario, en vez de dejar un hueco suelto debajo. El sello
              de confianza vive dentro de ese panel, pegado a su base. */}
          <div
            className={`grid grid-cols-1 gap-4 ${
              compacto ? "" : "sm:grid-cols-2 sm:grid-rows-[auto_1fr] sm:gap-x-7 sm:gap-y-4"
            }`}
          >
            {/* ---- Columna izquierda: vista previa + resumen ---- */}
            <TarjetaPreview
              marca={marca}
              nombreTitular={nombreTitular}
              numeroFormateado={numero}
              expiracion={expiracion}
              cvc={cvc}
              mostrarReverso={cvcEnfocado}
            />

            <div className="flex flex-col rounded-2xl border border-pan-borde/40 bg-pan-crema px-4 py-3.5 sm:px-5 sm:py-4">
              {/* El ÚNICO lugar donde aparece el número de pedido: junto al
                  monto, que es lo que el cliente necesita confirmar antes de
                  pagar. */}
              <div className="flex items-center justify-between gap-3">
                <div className="min-w-0">
                  <p className="text-[11px] font-semibold tracking-[0.14em] text-pan-carbon-suave uppercase">
                    Pedido #{numeroPedidoDia}
                  </p>
                  <p className="mt-0.5 text-sm font-medium text-pan-carbon">Total a pagar</p>
                </div>
                <span className="shrink-0 text-2xl font-bold tabular-nums text-pan-terracota sm:text-[1.75rem]">
                  S/ {total.toFixed(2)}
                </span>
              </div>

              {/* Detalle en vivo del cobro — se va completando con lo que el
                  cliente escribe a la derecha, como el recibo que va a
                  recibir. Solo en escritorio y a dos columnas: ahí es donde
                  el panel tiene alto de sobra; en celular o en el panel
                  compacto sería una repetición que estira la pantalla. */}
              {!compacto && (
                <dl className="mt-3 hidden space-y-1.5 border-t border-pan-borde/40 pt-3 text-[13px] sm:block">
                  <div className="flex items-baseline justify-between gap-3">
                    <dt className="shrink-0 text-pan-carbon-suave">Tarjeta</dt>
                    <dd className="min-w-0 truncate text-right font-medium text-pan-carbon">
                      {marca === "DESCONOCIDA" ? (
                        "Crédito o débito"
                      ) : (
                        <>
                          {marca.charAt(0) + marca.slice(1).toLowerCase()}
                          {ultimosCuatro.length === 4 && (
                            <span className="ml-1.5 tabular-nums text-pan-carbon-suave">•••• {ultimosCuatro}</span>
                          )}
                        </>
                      )}
                    </dd>
                  </div>
                  <div className="flex items-baseline justify-between gap-3">
                    <dt className="shrink-0 text-pan-carbon-suave">Comprobante</dt>
                    <dd className="min-w-0 truncate text-right font-medium text-pan-carbon">
                      {email.trim() || "Al correo que ingreses"}
                    </dd>
                  </div>
                </dl>
              )}

              <p
                className={`flex items-start gap-2 text-xs leading-relaxed text-pan-carbon-suave ${
                  compacto ? "mt-3 border-t border-pan-borde/40 pt-3" : "mt-3 border-t border-pan-borde/40 pt-3 sm:mt-auto"
                }`}
              >
                <ShieldCheck className="mt-0.5 h-3.5 w-3.5 shrink-0 text-emerald-600" strokeWidth={1.75} />
                Pago seguro procesado por Culqi (certificado PCI-DSS). Nunca guardamos el número de tu
                tarjeta.
              </p>
            </div>

            {/* ---- Columna derecha: formulario ---- */}
            <form
              onSubmit={enviar}
              className={`space-y-2.5 ${compacto ? "" : "sm:col-start-2 sm:row-start-1 sm:row-span-2"}`}
            >
              <div>
                <label htmlFor="titular-tarjeta" className="mb-1 block text-[13px] font-medium text-pan-carbon">
                  Nombre del titular
                </label>
                <input
                  id="titular-tarjeta"
                  autoComplete="cc-name"
                  value={nombreTitular}
                  onChange={(e) => {
                    setNombreTitular(formatearNombreTitular(e.target.value));
                    setError(null);
                  }}
                  placeholder="Como figura en la tarjeta"
                  required
                  className="campo-pan select-text"
                />
              </div>

              <div>
                <label htmlFor="numero-tarjeta" className="mb-1 block text-[13px] font-medium text-pan-carbon">
                  Número de tarjeta
                </label>
                <div className="relative">
                  <input
                    id="numero-tarjeta"
                    inputMode="numeric"
                    autoComplete="cc-number"
                    value={numero}
                    onChange={(e) => {
                      setNumero(formatearNumeroTarjeta(e.target.value));
                      setError(null);
                    }}
                    placeholder="4242 4242 4242 4242"
                    required
                    className="campo-pan select-text pr-16 tabular-nums"
                  />
                  <span className="pointer-events-none absolute inset-y-0 right-3.5 flex items-center">
                    {marca === "DESCONOCIDA" ? (
                      <CreditCard className="h-4 w-4 text-pan-carbon-suave" strokeWidth={1.75} />
                    ) : (
                      <span className="text-[11px] font-bold tracking-wide text-pan-bronce-oscuro">
                        {marca}
                      </span>
                    )}
                  </span>
                </div>
                {/* Los campos que Culqi de verdad lee del DOM (ver
                    `generarTokenCulqi`): número sin espacios, mes y año
                    sueltos. Son `hidden` (no `display:none` a mano ni
                    `sr-only`) justamente porque para eso existen los
                    inputs ocultos — el valor sigue siendo legible por
                    CulqiJS, solo no se pinta en pantalla. El visible de
                    arriba es el que el cliente teclea y ve formateado. */}
                <input type="hidden" id="card[number]" name="card[number]" value={soloDigitos(numero)} readOnly />
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label htmlFor="expiracion-tarjeta" className="mb-1 block text-[13px] font-medium text-pan-carbon">
                    Expiración (MM/AA)
                  </label>
                  <input
                    id="expiracion-tarjeta"
                    inputMode="numeric"
                    autoComplete="cc-exp"
                    value={expiracion}
                    onChange={(e) => {
                      setExpiracion(formatearExpiracion(e.target.value));
                      setError(null);
                    }}
                    placeholder="MM/AA"
                    maxLength={5}
                    required
                    className="campo-pan select-text tabular-nums"
                  />
                  <input type="hidden" id="card[exp_month]" name="card[exp_month]" value={mesExpiracion} readOnly />
                  {/* CulqiJS exige el año COMPLETO (4 dígitos): "30" lo rechaza con
                      "El año de expiración de tu tarjeta es inválido" aunque la
                      tarjeta sea válida. `anioExpiracion` sigue en 2 dígitos porque
                      así se ve en la tarjeta y así lo valida `expiracionValida` —
                      acá se expande solo para este campo puntual. */}
                  <input
                    type="hidden"
                    id="card[exp_year]"
                    name="card[exp_year]"
                    value={`20${anioExpiracion}`}
                    readOnly
                  />
                </div>
                <div>
                  <label htmlFor="card[cvv]" className="mb-1 block text-[13px] font-medium text-pan-carbon">
                    CVC
                  </label>
                  <div className="relative">
                    <input
                      id="card[cvv]"
                      name="card[cvv]"
                      type="password"
                      inputMode="numeric"
                      autoComplete="cc-csc"
                      value={cvc}
                      onChange={(e) => {
                        setCvc(limpiarCvc(e.target.value));
                        setError(null);
                      }}
                      onFocus={() => setCvcEnfocado(true)}
                      onBlur={() => setCvcEnfocado(false)}
                      placeholder="123"
                      maxLength={4}
                      required
                      className="campo-pan select-text pr-9 tabular-nums"
                    />
                    <Lock
                      className="pointer-events-none absolute inset-y-0 right-3.5 my-auto h-3.5 w-3.5 text-pan-carbon-suave"
                      strokeWidth={1.75}
                    />
                  </div>
                </div>
              </div>

              <div>
                <label htmlFor="card[email]" className="mb-1 block text-[13px] font-medium text-pan-carbon">
                  Correo electrónico
                </label>
                <div className="relative">
                  <input
                    id="card[email]"
                    name="card[email]"
                    type="email"
                    inputMode="email"
                    autoComplete="email"
                    value={email}
                    onChange={(e) => {
                      setEmail(limpiarEmail(e.target.value));
                      setError(null);
                    }}
                    placeholder="tucorreo@ejemplo.com"
                    required
                    className="campo-pan select-text pr-9"
                  />
                  <Mail
                    className="pointer-events-none absolute inset-y-0 right-3.5 my-auto h-4 w-4 text-pan-carbon-suave"
                    strokeWidth={1.75}
                  />
                </div>
                <p className="mt-1 text-xs text-pan-carbon-suave">Ahí te llega el comprobante de Culqi.</p>
              </div>

              <label className="flex min-h-10 cursor-pointer items-center gap-2.5 text-sm text-pan-carbon-suave">
                <input
                  type="checkbox"
                  checked={guardarTarjeta}
                  onChange={(e) => setGuardarTarjeta(e.target.checked)}
                  className="h-4 w-4 rounded border-pan-borde accent-pan-terracota focus:ring-2 focus:ring-pan-terracota/30"
                />
                Guardar esta tarjeta para la próxima vez
              </label>

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

              <AnimatePresence>
                {errorCarga && (
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
                      <p className="text-sm font-medium text-red-700">{errorCarga}</p>
                    </div>
                  </motion.div>
                )}
              </AnimatePresence>

              {/* Pagar y Cancelar en una misma fila en escritorio (Cancelar a
                  la izquierda, como en cualquier diálogo; en el DOM va
                  primero Pagar para que siga siendo el botón por defecto
                  con Enter). En celular y en el panel compacto se apilan,
                  Pagar arriba — ahí "Volver a mis pedidos" no cabe al lado. */}
              <div className={`flex flex-col gap-2.5 pt-0.5 ${compacto ? "" : "sm:flex-row-reverse"}`}>
                <motion.button
                  type="submit"
                  disabled={enviando || !culqiListo}
                  whileHover={enviando ? undefined : { scale: 1.02, y: -1 }}
                  whileTap={enviando ? undefined : { scale: 0.98 }}
                  className="flex min-h-12 flex-1 items-center justify-center gap-2 rounded-full bg-pan-terracota px-6 py-3 font-semibold text-pan-crema shadow-lg shadow-pan-terracota/20 transition-shadow hover:shadow-xl hover:shadow-pan-terracota/30 disabled:opacity-60"
                >
                  {enviando ? (
                    <>
                      <Loader2 className="h-4 w-4 animate-spin" />
                      Procesando…
                    </>
                  ) : (
                    `Pagar S/ ${total.toFixed(2)}`
                  )}
                </motion.button>

                {/* Botón secundario de verdad (borde, fondo, mismo alto que
                    Pagar) — el mismo tratamiento del "Cancelar" de
                    SelectorModal, con el relleno animado de `.boton-relleno`
                    al pasar el mouse. Antes era un texto suelto que no se
                    notaba que se podía tocar. */}
                {onCancelar && (
                  <motion.button
                    type="button"
                    onClick={onCancelar}
                    whileTap={{ scale: 0.98 }}
                    className={`boton-relleno flex min-h-12 items-center justify-center rounded-full border border-pan-borde bg-pan-crema-suave px-6 py-3 text-sm font-semibold text-pan-carbon-suave ${
                      compacto ? "" : "sm:min-w-32"
                    }`}
                    style={
                      {
                        "--color-relleno": "var(--color-pan-crema-muted)",
                        "--color-relleno-texto": "var(--color-pan-carbon)",
                      } as React.CSSProperties
                    }
                  >
                    {etiquetaCancelar}
                  </motion.button>
                )}
              </div>
            </form>
          </div>
        </div>
      )}
    </motion.div>
  );
}

const FONDO_TARJETA =
  "linear-gradient(135deg, var(--color-pan-carbon) 0%, var(--color-pan-terracota-profundo) 55%, var(--color-pan-terracota) 100%)";

/**
 * La tarjeta con gradiente que se actualiza en vivo mientras el cliente
 * escribe — nada de imagen, es un div con degradado y los datos puestos
 * encima. El detalle "wow" del video de referencia, con la identidad de
 * ESTE proyecto (carbón + terracota + un brillo dorado) en vez del
 * azul genérico del original.
 *
 * Tiene dos caras: mientras el campo CVC está enfocado se da vuelta (giro
 * 3D sobre el eje Y) y muestra el reverso, con la banda magnética, la de
 * firma y el recuadro del CVC — que es donde ese código está impreso en la
 * tarjeta física, así el cliente sabe dónde mirar. Mecánica: el contenedor
 * da la perspectiva, un `motion.div` con `transform-style: preserve-3d`
 * rota entre 0° y 180°, y cada cara lleva `backface-visibility: hidden`
 * (la de atrás ya nace girada 180°). Con "reducir movimiento" activado
 * `MotionConfig` de la app apaga la animación y el cambio de cara es
 * instantáneo, que es justo lo que corresponde.
 */
function TarjetaPreview({
  marca,
  nombreTitular,
  numeroFormateado,
  expiracion,
  cvc,
  mostrarReverso,
}: {
  marca: MarcaTarjeta;
  nombreTitular: string;
  numeroFormateado: string;
  expiracion: string;
  cvc: string;
  mostrarReverso: boolean;
}) {
  const cvcPuntos = cvcEnmascarado(cvc);

  return (
    <div aria-hidden="true" className="relative aspect-[1.6/1] w-full perspective-[1200px]">
      <motion.div
        className="relative h-full w-full transform-3d"
        initial={false}
        animate={{ rotateY: mostrarReverso ? 180 : 0 }}
        transition={{ duration: 0.6, ease: EASE_PREMIUM }}
      >
        {/* ---- Frente ---- */}
        <div
          className="absolute inset-0 overflow-hidden rounded-2xl p-5 shadow-lg shadow-pan-carbon/20 backface-hidden"
          style={{ background: FONDO_TARJETA }}
        >
          {/* Brillos decorativos, tipo glassmorphism, sin salirse de la
              paleta cálida del proyecto. */}
          <div
            className="absolute -top-10 -right-10 h-40 w-40 rounded-full opacity-30 blur-2xl"
            style={{ background: "var(--color-pan-oro)" }}
          />
          <div
            className="absolute -bottom-16 -left-10 h-40 w-40 rounded-full opacity-20 blur-2xl"
            style={{ background: "var(--color-pan-bronce)" }}
          />

          <div className="relative flex h-full flex-col justify-between text-pan-crema">
            <div className="flex items-start justify-between">
              <div className="h-8 w-11 rounded-md bg-gradient-to-br from-pan-oro/80 to-pan-bronce/60" />
              {marca === "DESCONOCIDA" ? (
                <CreditCard className="h-6 w-6 text-pan-crema/80" strokeWidth={1.5} />
              ) : (
                <span className="text-sm font-bold tracking-wide text-pan-crema/90 italic">{marca}</span>
              )}
            </div>

            <p className="font-mono text-lg tracking-widest tabular-nums sm:text-xl">
              {numeroTarjetaEnmascarado(numeroFormateado)}
            </p>

            <div className="flex items-end justify-between gap-4">
              <div className="min-w-0">
                <p className="text-[10px] tracking-[0.16em] text-pan-crema/60 uppercase">Titular</p>
                <p className="truncate text-sm font-medium tracking-wide uppercase">
                  {nombreTitular.trim() || "NOMBRE APELLIDO"}
                </p>
              </div>
              <div className="shrink-0 text-right">
                <p className="text-[10px] tracking-[0.16em] text-pan-crema/60 uppercase">Vence</p>
                <p className="text-sm font-medium tabular-nums">{expiracion || "MM/AA"}</p>
              </div>
            </div>
          </div>
        </div>

        {/* ---- Reverso ---- */}
        <div
          className="absolute inset-0 overflow-hidden rounded-2xl shadow-lg shadow-pan-carbon/20 backface-hidden rotate-y-180"
          style={{ background: FONDO_TARJETA }}
        >
          <div
            className="absolute -bottom-12 -right-8 h-36 w-36 rounded-full opacity-25 blur-2xl"
            style={{ background: "var(--color-pan-oro)" }}
          />

          <div className="relative flex h-full flex-col text-pan-crema">
            {/* Banda magnética */}
            <div className="mt-[9%] h-[17%] w-full bg-pan-carbon/90" />

            {/* Banda de firma + recuadro del CVC. El CVC se pinta SIEMPRE
                como puntos (uno por dígito tecleado), nunca el número —
                pedido explícito del dueño, y buena práctica de pagos. */}
            <div className="mx-5 mt-[7%] flex items-center gap-2.5">
              <div
                className="h-9 min-w-0 flex-1 rounded-sm bg-pan-crema/95"
                style={{
                  backgroundImage:
                    "repeating-linear-gradient(0deg, transparent 0 5px, color-mix(in srgb, var(--color-pan-bronce) 35%, transparent) 5px 6px)",
                }}
              />
              <div className="flex h-9 w-16 shrink-0 items-center justify-center rounded-sm bg-pan-crema-suave font-mono text-base tracking-[0.3em] text-pan-carbon tabular-nums">
                <AnimatePresence initial={false}>
                  {cvcPuntos.split("").map((punto, i) => (
                    <motion.span
                      // Los puntos son idénticos entre sí: la posición es
                      // la única identidad que tienen.
                      key={i}
                      initial={{ opacity: 0, scale: 0.4 }}
                      animate={{ opacity: 1, scale: 1 }}
                      exit={{ opacity: 0, scale: 0.4 }}
                      transition={{ duration: 0.18, ease: EASE_PREMIUM }}
                    >
                      {punto}
                    </motion.span>
                  ))}
                </AnimatePresence>
              </div>
              <span className="shrink-0 text-[10px] font-semibold tracking-[0.16em] text-pan-crema/70 uppercase">
                CVC
              </span>
            </div>

            <div className="mx-5 mt-auto mb-4 flex items-end justify-between gap-4">
              <p className="max-w-[60%] text-[9px] leading-snug text-pan-crema/55">
                El código junto a la banda de firma. Nunca lo mostramos en pantalla.
              </p>
              {marca === "DESCONOCIDA" ? (
                <CreditCard className="h-5 w-5 text-pan-crema/70" strokeWidth={1.5} />
              ) : (
                <span className="text-xs font-bold tracking-wide text-pan-crema/85 italic">{marca}</span>
              )}
            </div>
          </div>
        </div>
      </motion.div>
    </div>
  );
}
