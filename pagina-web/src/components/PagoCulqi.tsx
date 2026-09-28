import { useEffect, useRef, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { AlertTriangle, ArrowLeft, CreditCard, Loader2, Lock, Mail, ShieldCheck, Smartphone } from "lucide-react";
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
import { celularPeruanoValido, codigoYapeValido, formatearCelular, motivoYapeNoDisponible } from "../utils/yape";
import { ErrorMontoFueraDeRango, acotarMontoElegido, calcularMontoConComision } from "../utils/pagoAdelanto";
import { EASE_PREMIUM } from "../utils/animacion";
import { SelectorMontoPago } from "./PagoCulqiMonto";
import { CamposYape, VistaPreviaYape } from "./PagoCulqiYape";
import { SelectorMetodoPago, type MetodoPagoCulqi } from "./PagoCulqiSelectorMetodo";

/**
 * Lo mínimo de la API global de CulqiJS v4 que este componente usa. La
 * biblioteca no publica tipos propios y trabaja pegada al DOM (lee/escribe
 * sobre `window.Culqi`), así que esto es un contrato local, no el SDK real.
 *
 * Fuente: `https://checkout.culqi.com/js/v4` + el flujo confirmado en los
 * demos oficiales de Culqi (`culqi/culqi-reactjs-demo-jsv4` y
 * `culqi/culqi-php-demo-jsv4-culqi3ds`, GitHub) — ver el reporte de este
 * componente para el detalle exacto de cada método.
 *
 * Tarjeta y Yape van por el MISMO camino: `validationPaymentMethods()` deja
 * en `paymentOptionsAvailable` una opción por método (`token` para tarjeta,
 * `yape` para Yape), cada una con `available`/`message`/`generate()`. Las
 * dos leen sus campos del DOM y las dos terminan en el mismo callback global
 * `window.culqi()` con el mismo `Culqi.token` (`object: "token"`, `id:
 * "tkn_test_…"` en tarjeta, `"ype_test_…"` en Yape). La única diferencia es
 * qué inputs hay que tener puestos.
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
  paymentOptionsAvailable?: { token?: CulqiOpcionDePago; yape?: CulqiOpcionDePago };
  token?: CulqiTokenResultado;
  error?: CulqiErrorResultado;
}

/** Los dos medios de pago que ofrece esta pantalla ("TARJETA" | "YAPE"). El
 * tipo vive en `PagoCulqiSelectorMetodo.tsx`; se re-exporta acá para que
 * quien integre el checkout siga importándolo de este archivo. */
export type { MetodoPagoCulqi };

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
  /** Se llama DESPUÉS de que Culqi.js tokenizó la tarjeta (o el código de
   * Yape) con éxito. Este componente no sabe nada de pedidos ni de backend:
   * lo que pase con el token (cobrar, guardar, reintentar) es
   * responsabilidad de quien lo usa. Mientras la promesa no resuelve se
   * muestra el estado de carga, y si se rechaza, se muestra el mensaje de
   * error que traiga. El token de Yape (`ype_…`) se cobra por el mismo
   * endpoint que el de tarjeta (`tkn_…`), así que quien integra no necesita
   * distinguirlos.
   *
   * `montoElegido` es cuánto decidió abonar el cliente A SU PEDIDO ahora, en
   * soles y SIN comisión — lo que hay que mandar tal cual como `montoElegido`
   * a `pagarConCulqi`. Ya viene acotado al rango [mitad, total]; el backend
   * lo vuelve a validar y calcula la comisión por su cuenta. Si el servidor
   * igual lo rechaza por rango (400 con `total` y `montoMinimo`), quien
   * integra debe rechazar la promesa con un `ErrorMontoFueraDeRango` para que
   * esta pantalla corrija el control además de mostrar el mensaje. */
  onTokenGenerado: (culqiTokenId: string, datos: { email: string; montoElegido: number }) => Promise<void>;
  onCancelar?: () => void;
  etiquetaCancelar?: string;
  compacto?: boolean;
}

/**
 * Checkout de pago por Culqi para Panadería, con dos medios: tarjeta y Yape,
 * en DOS pasos. Primero la pantalla de elección (`SelectorMetodoPago`, en
 * `PagoCulqiSelectorMetodo.tsx`): "¿Cómo quieres pagar?", Tarjeta o Yape,
 * ninguna marcada de antemano. Recién cuando el cliente toca una, entra el
 * formulario de ESE medio: vista previa en vivo + resumen a la izquierda,
 * campos a la derecha, con una fila arriba para volver a elegir. Pedido del
 * dueño (2026-09-27): no quería el selector de pestañas que ya mostraba un
 * formulario por defecto, sino una decisión explícita antes de pagar.
 *
 * El flujo vive ACÁ y no en un componente hermano por método porque todo lo
 * que de verdad cuesta —cargar CulqiJS una sola vez, avisarle el monto,
 * envolver su callback global en una promesa, el resumen, los errores, los
 * botones— es idéntico para los dos: un `PagoYapeCulqi` aparte habría tenido
 * que repetirlo entero. Lo que sí es distinto (los campos y el panel de la
 * izquierda en modo Yape) está en `PagoCulqiYape.tsx`, por tamaño.
 *
 * Dentro del formulario de cualquiera de los dos medios, LO PRIMERO es el
 * control de "¿cuánto pagas ahora?" (`SelectorMontoPago`, en
 * `PagoCulqiMonto.tsx`): desde el 2026-09-28 el cliente puede separar su
 * pedido abonando entre la mitad y el total, y paga él la comisión de la
 * pasarela. Ese control define el monto que se va a cobrar, así que va
 * antes que la tarjeta, el resumen y los campos. Acá viven las TRES cifras
 * que hay que tener separadas todo el tiempo:
 *   montoElegido  lo que va al pedido (lo que el cliente ajusta; viaja al backend)
 *   comision      lo que se lleva Culqi (calculado con la MISMA cuenta que el backend)
 *   montoACobrar  lo que sale de la tarjeta/Yape (= los dos de arriba; es lo que
 *                 ve el botón de pagar, la vista previa y lo que se le avisa a CulqiJS)
 *
 * Todo lo de la tarjeta (Luhn, marca, formato, expiración) vive en
 * `utils/tarjeta.ts`, lo de Yape (celular, código, límites) en
 * `utils/yape.ts` y la cuenta del monto/comisión en `utils/pagoAdelanto.ts`,
 * puros y probados — acá solo queda la parte que sí necesita DOM: pintar,
 * sincronizar los campos que CulqiJS v4 necesita leer del formulario, y
 * envolver su callback global en una promesa para poder usar async/await
 * limpio.
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

  // ---- Método ----
  // `null` = todavía en la pantalla de elección: NINGÚN medio viene marcado,
  // el cliente tiene que tocar uno. Lo que ya escribió en un formulario
  // (tarjeta, celular, correo) se conserva si vuelve a elegir y regresa al
  // mismo medio; el correo además es compartido entre los dos a propósito.
  const [metodo, setMetodo] = useState<MetodoPagoCulqi | null>(null);
  const [celularYape, setCelularYape] = useState("");
  const [codigoYape, setCodigoYape] = useState("");

  // ---- Monto ----
  // Cuánto abona el cliente A SU PEDIDO ahora. Arranca en el total (pago
  // completo, lo que va a hacer la mayoría) y SIEMPRE pasa por
  // `acotarMontoElegido`: da igual si viene del deslizador, del campo de
  // texto o de un atajo, lo que queda acá está dentro de [mitad, total] y
  // redondeado al céntimo. Se conserva al cambiar de medio: la decisión de
  // cuánto pagar no depende de con qué.
  const [montoElegido, setMontoElegidoCrudo] = useState(() => acotarMontoElegido(total, total));
  function setMontoElegido(monto: number) {
    setMontoElegidoCrudo(acotarMontoElegido(total, monto));
  }
  // Si el total cambiara con la pantalla abierta (no debería, pero la prop
  // lo permite), el monto se vuelve a encajar en el rango nuevo.
  useEffect(() => {
    setMontoElegidoCrudo((actual) => acotarMontoElegido(total, actual));
  }, [total]);

  // La comisión y el monto a cobrar, con la MISMA cuenta que el backend (ver
  // utils/pagoAdelanto). `montoACobrar` es lo que de verdad sale de la
  // tarjeta/Yape y por eso es lo que ve el botón, la vista previa y CulqiJS.
  const desglose = calcularMontoConComision(montoElegido);
  const montoACobrar = desglose?.montoACobrar ?? montoElegido;

  // null = se puede yapear este monto; texto = por qué no (fuera del rango
  // que CulqiJS acepta para Yape). Se calcula acá, en palabras nuestras,
  // antes de que Culqi lo rechace con su mensaje genérico. En la pantalla
  // de elección apaga la opción Yape; dentro del formulario queda como red
  // por si el monto cambiara con el método ya elegido. Se mira el monto A
  // COBRAR (con comisión), que es el que CulqiJS compara contra sus topes.
  const yapeNoDisponible = motivoYapeNoDisponible(montoACobrar);

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

  // El monto se le avisa a Culqi en céntimos enteros (S/ 47.24 -> 4724),
  // igual que hace el backend (ver utils/pagoAdelanto). Y es el monto A
  // COBRAR, con comisión, no el total ni el elegido: el token de Yape queda
  // atado al monto que se le dio acá, y el backend va a pedir el cargo por
  // exactamente `montoACobrar` — si no coincidieran, Culqi rechazaría el
  // cobro. Se reenvía cada vez que el cliente mueve el monto.
  useEffect(() => {
    const Culqi = window.Culqi;
    if (!culqiListo || !Culqi) return;
    Culqi.settings({ currency: "PEN", amount: Math.round(montoACobrar * 100) });
  }, [culqiListo, montoACobrar]);

  /**
   * Todo lo que hay que revisar ANTES de gastar un viaje a Culqi. Es la
   * misma idea que la validación de PedidoForm: atrapar el error de tecleo
   * obvio acá, no después de un viaje de ida y vuelta.
   */
  function validar(metodoElegido: MetodoPagoCulqi): string | null {
    if (metodoElegido === "YAPE") {
      if (yapeNoDisponible) return yapeNoDisponible;
      if (!celularPeruanoValido(celularYape)) {
        return "Escribe el celular que tienes registrado en Yape: 9 dígitos, empieza con 9.";
      }
      if (!emailValido(email)) {
        return "Ingresa un correo electrónico válido.";
      }
      if (!codigoYapeValido(codigoYape)) {
        return "El código de aprobación tiene 6 dígitos. Genéralo en tu app de Yape y escríbelo completo.";
      }
      return null;
    }
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
   *
   * Sirve para los dos métodos: lo único que cambia es cuál de las opciones
   * de `paymentOptionsAvailable` se dispara (`token` = tarjeta, `yape` =
   * Yape) y qué campos del DOM va a leer Culqi al hacerlo. El token de Yape
   * no trae `email` (Culqi solo recibe celular + código), así que ahí se usa
   * el del formulario.
   */
  function generarTokenCulqi(metodoElegido: MetodoPagoCulqi): Promise<{ tokenId: string; email: string }> {
    return new Promise((resolve, reject) => {
      const Culqi = window.Culqi;
      if (!Culqi) {
        reject(new Error("El sistema de pagos todavía no está listo. Espera un momento e intenta de nuevo."));
        return;
      }
      Culqi.token = undefined;
      Culqi.error = undefined;

      const esYape = metodoElegido === "YAPE";
      window.culqi = () => {
        if (Culqi.token && Culqi.token.object === "token") {
          resolve({ tokenId: Culqi.token.id, email: Culqi.token.email ?? email.trim() });
        } else {
          reject(
            new Error(
              Culqi.error?.user_message ??
                Culqi.error?.merchant_message ??
                (esYape
                  ? "No pudimos validar tu código de Yape. Genera uno nuevo en tu app e intenta de nuevo."
                  : "No pudimos procesar tu tarjeta. Revisa los datos e intenta de nuevo."),
            ),
          );
        }
      };

      Culqi.validationPaymentMethods();
      const opcion = esYape ? Culqi.paymentOptionsAvailable?.yape : Culqi.paymentOptionsAvailable?.token;
      if (!opcion?.available) {
        reject(
          new Error(
            opcion?.message ??
              (esYape
                ? "El pago con Yape no está disponible en este momento."
                : "El pago con tarjeta no está disponible en este momento."),
          ),
        );
        return;
      }
      opcion.generate();
    });
  }

  async function enviar(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    // El formulario solo existe con un método elegido; esto es para que
    // TypeScript lo sepa, no un caso que pueda pasar de verdad.
    if (metodo === null) return;

    const problema = validar(metodo);
    if (problema) {
      setError(problema);
      return;
    }
    if (!culqiListo) {
      setError("El sistema de pagos todavía se está cargando. Espera un instante e intenta de nuevo.");
      return;
    }

    setEnviando(true);
    try {
      const { tokenId, email: emailToken } = await generarTokenCulqi(metodo);
      // Viaja `montoElegido` (SIN comisión): el backend calcula la comisión
      // por su cuenta con la misma cuenta que se le mostró al cliente acá.
      await onTokenGenerado(tokenId, { email: emailToken, montoElegido });
    } catch (err) {
      if (err instanceof ErrorMontoFueraDeRango) {
        // Red de seguridad: el servidor no aceptó el monto (en teoría
        // imposible, el control ya lo acotó con la misma cuenta). Se corrige
        // el control con el rango que ÉL mandó, así el botón queda con un
        // número que sí va a aceptar, y se muestra su mensaje tal cual.
        setMontoElegidoCrudo(Math.min(Math.max(montoElegido, err.montoMinimo), err.total));
      }
      setError(err instanceof Error ? err.message : "No pudimos procesar el pago. Intenta de nuevo.");
    } finally {
      setEnviando(false);
    }
  }

  const { mes: mesExpiracion, anio: anioExpiracion } = partesExpiracion(expiracion);
  const ultimosCuatro = soloDigitos(numero).slice(-4);

  /** Volver a la pantalla de elección sin perder lo escrito. Se apaga
   * mientras se está cobrando: cambiar de medio a mitad de un token en
   * vuelo sería justo el lío que el flujo por pasos evita. */
  function volverAElegir() {
    if (enviando) return;
    setMetodo(null);
    setError(null);
  }

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
        Paga tu pedido
      </h3>
      {/* La bajada cambia con el paso (con `key`, para que el cambio se
          note como un cambio y no como un texto que parpadea). */}
      <AnimatePresence mode="wait" initial={false}>
        <motion.p
          key={metodo ?? "eleccion"}
          initial={{ opacity: 0, y: 4 }}
          animate={{ opacity: 1, y: 0 }}
          exit={{ opacity: 0, y: -4 }}
          transition={{ duration: 0.18, ease: EASE_PREMIUM }}
          className="mt-1 text-sm leading-relaxed text-pan-carbon-suave"
        >
          {metodo === null
            ? "Tu pedido ya está registrado. Elige con qué pagarlo y en un minuto queda confirmado."
            : metodo === "YAPE"
              ? "Genera un código de aprobación en tu app de Yape y escríbelo acá. El cobro sale al instante, sin tarjeta."
              : "Crédito o débito, en un solo paso. Tus datos van directo a Culqi, nunca pasan por nuestros servidores."}
        </motion.p>
      </AnimatePresence>

      {!culqiConfigurado ? (
        <div className="mt-5 flex items-start gap-2.5 rounded-xl border border-amber-300 bg-amber-50 px-4 py-3">
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-amber-600" strokeWidth={1.75} />
          <p className="text-xs leading-relaxed font-medium text-amber-800">
            Los pagos en línea no están configurados todavía. Escríbenos y coordinamos el pago por otro
            medio mientras los activamos.
          </p>
        </div>
      ) : (
        // Los dos pasos se turnan (`mode="wait"`: primero se va uno, después
        // llega el otro), así nunca conviven en el DOM la pantalla de
        // elección y un formulario, ni dos juegos de inputs que CulqiJS
        // podría confundir. Cada formulario lleva el método en su `key`: se
        // monta limpio al elegir y se desmonta entero al volver.
        <AnimatePresence mode="wait" initial={false}>
          {metodo === null ? (
            <motion.div
              key="eleccion"
              initial={{ opacity: 0, x: -16 }}
              animate={{ opacity: 1, x: 0 }}
              exit={{ opacity: 0, x: -16 }}
              transition={{ duration: 0.28, ease: EASE_PREMIUM }}
              className="mt-4"
            >
              <SelectorMetodoPago
                numeroPedidoDia={numeroPedidoDia}
                total={total}
                yapeNoDisponible={yapeNoDisponible}
                onElegir={(elegido) => {
                  setMetodo(elegido);
                  setError(null);
                }}
                onCancelar={onCancelar}
                etiquetaCancelar={etiquetaCancelar}
                compacto={compacto}
              />
            </motion.div>
          ) : (
            <motion.div
              key={`formulario-${metodo}`}
              initial={{ opacity: 0, x: 16 }}
              animate={{ opacity: 1, x: 0 }}
              exit={{ opacity: 0, x: 16 }}
              transition={{ duration: 0.28, ease: EASE_PREMIUM }}
              className="mt-4"
            >
              {/* Qué medio eligió y la puerta para volver a elegir. Es distinto
                  de "Cancelar" (que abandona el pago entero): esto solo regresa
                  un paso, con lo escrito intacto. */}
              <div className="mb-4 flex items-center justify-between gap-3 rounded-xl border border-pan-borde/40 bg-pan-crema px-3.5 py-2">
                <p className="flex min-w-0 items-center gap-2 text-sm text-pan-carbon">
                  {metodo === "YAPE" ? (
                    <Smartphone className="h-4 w-4 shrink-0 text-pan-terracota" strokeWidth={1.75} />
                  ) : (
                    <CreditCard className="h-4 w-4 shrink-0 text-pan-terracota" strokeWidth={1.75} />
                  )}
                  <span className="truncate">
                    Pagas con <strong className="font-semibold">{metodo === "YAPE" ? "Yape" : "tarjeta"}</strong>
                  </span>
                </p>
                <motion.button
                  type="button"
                  onClick={volverAElegir}
                  disabled={enviando}
                  whileTap={enviando ? undefined : { scale: 0.96 }}
                  className="group flex min-h-9 shrink-0 items-center gap-1 rounded-full px-2.5 text-[13px] font-semibold text-pan-terracota transition-colors hover:bg-pan-terracota/10 disabled:cursor-not-allowed disabled:opacity-50"
                >
                  <ArrowLeft
                    className="h-3.5 w-3.5 transition-transform duration-300 group-hover:-translate-x-0.5"
                    strokeWidth={2}
                  />
                  Cambiar método
                </motion.button>
              </div>

              {/* LO PRIMERO del formulario, a todo el ancho y antes de las dos
                  columnas: cuánto paga ahora. Define el monto que se va a
                  cobrar, así que el cliente tiene que verlo (y poder moverlo)
                  antes que la tarjeta, el resumen y los campos. */}
              <motion.div
                initial={{ opacity: 0, y: 8 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.3, ease: EASE_PREMIUM }}
                className="mb-4"
              >
                <SelectorMontoPago
                  total={total}
                  montoElegido={montoElegido}
                  onCambiar={(monto) => {
                    setMontoElegido(monto);
                    setError(null);
                  }}
                  metodo={metodo}
                  deshabilitado={enviando}
                />
              </motion.div>

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
                {/* ---- Columna izquierda: vista previa + resumen ----
                    La tarjeta y el panel de Yape tienen la MISMA proporción, así
                    que el resumen de abajo y el formulario quedan en el mismo
                    lugar sea cual sea el medio. La vista previa "aterriza" con un
                    leve giro al entrar, ya que todo el paso se monta de cero. */}
                <motion.div
                  className="relative"
                  initial={{ opacity: 0, scale: 0.96, rotateY: 12 }}
                  animate={{ opacity: 1, scale: 1, rotateY: 0 }}
                  transition={{ duration: 0.4, ease: EASE_PREMIUM, delay: 0.05 }}
                >
                  {metodo === "YAPE" ? (
                    <VistaPreviaYape celular={celularYape} codigo={codigoYape} monto={montoACobrar} />
                  ) : (
                    <TarjetaPreview
                      marca={marca}
                      nombreTitular={nombreTitular}
                      numeroFormateado={numero}
                      expiracion={expiracion}
                      cvc={cvc}
                      mostrarReverso={cvcEnfocado}
                    />
                  )}
                </motion.div>

                <div className="flex flex-col rounded-2xl border border-pan-borde/40 bg-pan-crema px-4 py-3.5 sm:px-5 sm:py-4">
                  {/* El ÚNICO lugar donde aparece el número de pedido: junto al
                      monto, que es lo que el cliente necesita confirmar antes de
                      pagar. El número grande es lo que SALE de la tarjeta/Yape
                      (con comisión), el mismo del botón: es la cifra que va a
                      ver en su estado de cuenta. El total del pedido queda
                      como referencia chica cuando no coincide. */}
                  <div className="flex items-center justify-between gap-3">
                    <div className="min-w-0">
                      <p className="text-[11px] font-semibold tracking-[0.14em] text-pan-carbon-suave uppercase">
                        Pedido #{numeroPedidoDia}
                      </p>
                      <p className="mt-0.5 text-sm font-medium text-pan-carbon">
                        {metodo === "YAPE" ? "Sale de tu Yape" : "Sale de tu tarjeta"}
                      </p>
                      {montoElegido !== total && (
                        <p className="mt-0.5 text-xs text-pan-carbon-suave tabular-nums">
                          Total del pedido: S/ {total.toFixed(2)}
                        </p>
                      )}
                    </div>
                    <span className="shrink-0 text-2xl font-bold tabular-nums text-pan-terracota sm:text-[1.75rem]">
                      S/ {montoACobrar.toFixed(2)}
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
                        <dt className="shrink-0 text-pan-carbon-suave">{metodo === "YAPE" ? "Yape" : "Tarjeta"}</dt>
                        <dd className="min-w-0 truncate text-right font-medium text-pan-carbon">
                          {metodo === "YAPE" ? (
                            celularYape.length > 0 ? (
                              <span className="tabular-nums">{formatearCelular(celularYape)}</span>
                            ) : (
                              "Desde tu celular"
                            )
                          ) : marca === "DESCONOCIDA" ? (
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
                    {metodo === "YAPE"
                      ? "Pago seguro procesado por Culqi. Tu código de aprobación sirve una sola vez y nunca lo guardamos."
                      : "Pago seguro procesado por Culqi (certificado PCI-DSS). Nunca guardamos el número de tu tarjeta."}
                  </p>
                </div>

                {/* ---- Columna derecha: formulario ---- */}
                <form
                  onSubmit={enviar}
                  className={`space-y-2.5 ${compacto ? "" : "sm:col-start-2 sm:row-start-1 sm:row-span-2"}`}
                >
                  {/* Solo existen los campos del método elegido: el otro juego
                      de inputs ni siquiera está en el DOM, así CulqiJS no tiene
                      cómo confundirse. Los de tarjeta se quedan tal cual
                      estaban; lo de Yape vive en PagoCulqiYape.tsx. Entran un
                      pelo después que la vista previa, como una segunda ola. */}
                  {metodo === "YAPE" ? (
                      <motion.div
                        key="campos-yape"
                        initial={{ opacity: 0, y: 8 }}
                        animate={{ opacity: 1, y: 0 }}
                        transition={{ duration: 0.3, ease: EASE_PREMIUM, delay: 0.1 }}
                        className="space-y-2.5"
                      >
                        {yapeNoDisponible ? (
                          // Fuera del rango que Culqi acepta para Yape: se dice
                          // acá, con salida (la tarjeta está a un toque), en vez
                          // de dejar que el cliente llene todo y le rebote.
                          <div className="flex items-start gap-2.5 rounded-xl border border-amber-300 bg-amber-50 px-4 py-3">
                            <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-amber-600" strokeWidth={1.75} />
                            <p className="text-xs leading-relaxed font-medium text-amber-800">{yapeNoDisponible}</p>
                          </div>
                        ) : (
                          <CamposYape
                            celular={celularYape}
                            codigo={codigoYape}
                            email={email}
                            onCelular={(valor) => {
                              setCelularYape(valor);
                              setError(null);
                            }}
                            onCodigo={(valor) => {
                              setCodigoYape(valor);
                              setError(null);
                            }}
                            onEmail={(valor) => {
                              setEmail(valor);
                              setError(null);
                            }}
                          />
                        )}
                      </motion.div>
                    ) : (
                      <motion.div
                        key="campos-tarjeta"
                        initial={{ opacity: 0, y: 8 }}
                        animate={{ opacity: 1, y: 0 }}
                        transition={{ duration: 0.3, ease: EASE_PREMIUM, delay: 0.1 }}
                        className="space-y-2.5"
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
                      </motion.div>
                    )}

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
                      disabled={enviando || !culqiListo || (metodo === "YAPE" && yapeNoDisponible !== null)}
                      whileHover={enviando ? undefined : { scale: 1.02, y: -1 }}
                      whileTap={enviando ? undefined : { scale: 0.98 }}
                      className="flex min-h-12 flex-1 items-center justify-center gap-2 rounded-full bg-pan-terracota px-6 py-3 font-semibold text-pan-crema shadow-lg shadow-pan-terracota/20 transition-shadow hover:shadow-xl hover:shadow-pan-terracota/30 disabled:opacity-60"
                    >
                      {enviando ? (
                        <>
                          <Loader2 className="h-4 w-4 animate-spin" />
                          {metodo === "YAPE" ? "Confirmando con Yape…" : "Procesando…"}
                        </>
                      ) : metodo === "YAPE" ? (
                        // Con comisión: es lo que de verdad se le va a cobrar.
                        `Yapear S/ ${montoACobrar.toFixed(2)}`
                      ) : (
                        `Pagar S/ ${montoACobrar.toFixed(2)}`
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
            </motion.div>
          )}
        </AnimatePresence>
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
