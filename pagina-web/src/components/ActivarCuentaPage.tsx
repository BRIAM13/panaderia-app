import { useEffect, useRef, useState, type FormEvent, type RefObject } from "react";
import { AnimatePresence, MotionConfig, motion } from "framer-motion";
import {
  AlertTriangle,
  ArrowRight,
  CheckCircle2,
  Eye,
  EyeOff,
  KeyRound,
  Loader2,
  LinkIcon,
} from "lucide-react";
import { ApiError, activarCuenta, URL_PORTAL_APP } from "../services/api";
import { enlaceWhatsApp } from "../data/config";
import { EASE_PREMIUM } from "../utils/animacion";

/** Mismo mínimo que exige el backend (validators.js) y que ya rige en toda
 * la app. Se valida acá solo para no hacer un viaje al servidor por algo
 * que se ve al instante — la barrera real está del otro lado. */
const LARGO_MINIMO_PASSWORD = 8;

type Fase = "formulario" | "enviando" | "exito" | "enlaceRoto";

/**
 * Pantalla a la que lleva el botón "Activar mi cuenta" del correo que
 * recibe quien hizo un pedido desde la web dejando su correo.
 *
 * Su único trabajo es que la persona elija su contraseña. El enlace trae
 * `p` (IdPersona) y `t` (el token de un solo uso); acá no se interpretan,
 * se reenvían tal cual al backend, que es quien decide si valen.
 *
 * Al terminar NO inicia sesión: el portal donde de verdad se entra
 * (app.panaderiaronceros.com) es otro sitio, con su propia sesión, y no hay
 * SSO entre los dos dominios. Lo honesto —y lo que de verdad ayuda— es
 * confirmar y dejar el enlace a un clic.
 */
export function ActivarCuentaPage() {
  const parametros = new URLSearchParams(window.location.search);
  const idPersonaCrudo = parametros.get("p") ?? "";
  const token = parametros.get("t") ?? "";
  const idPersona = Number(idPersonaCrudo);
  const enlaceCompleto = Number.isInteger(idPersona) && idPersona > 0 && token.length > 0;

  const [fase, setFase] = useState<Fase>(enlaceCompleto ? "formulario" : "enlaceRoto");
  const [password, setPassword] = useState("");
  const [confirmacion, setConfirmacion] = useState("");
  const [verPassword, setVerPassword] = useState(false);
  const [error, setError] = useState<string | null>(
    enlaceCompleto
      ? null
      : "El enlace está incompleto: probablemente se cortó al copiarlo del correo. Ábrelo tocando el botón «Activar mi cuenta» desde el mismo correo.",
  );

  const tituloExitoRef = useRef<HTMLHeadingElement>(null);

  // Título de pestaña propio (esta "ruta" no pasa por index.html) y
  // `noindex`: es una página de un solo uso, atada a un token personal —
  // no tiene ningún sentido que Google la indexe.
  useEffect(() => {
    document.title = "Activa tu cuenta · Panadería Ronceros";
    const meta = document.createElement("meta");
    meta.name = "robots";
    meta.content = "noindex, nofollow";
    document.head.appendChild(meta);
    return () => {
      meta.remove();
    };
  }, []);

  // El foco salta al título del éxito: quien navega con teclado o lector de
  // pantalla necesita que se le anuncie que el formulario ya no está.
  useEffect(() => {
    if (fase !== "exito") return;
    const id = window.setTimeout(() => tituloExitoRef.current?.focus(), 250);
    return () => window.clearTimeout(id);
  }, [fase]);

  async function enviar(evento: FormEvent) {
    evento.preventDefault();
    if (fase === "enviando") return;

    if (password.length < LARGO_MINIMO_PASSWORD) {
      setError(`La contraseña debe tener al menos ${LARGO_MINIMO_PASSWORD} caracteres.`);
      return;
    }
    if (password !== confirmacion) {
      setError("Las dos contraseñas no coinciden. Revísalas y vuelve a intentar.");
      return;
    }

    setError(null);
    setFase("enviando");

    try {
      await activarCuenta({ idPersona, token, passwordNueva: password });
      setPassword("");
      setConfirmacion("");
      setFase("exito");
    } catch (err) {
      // El backend ya manda el texto redactado para mostrarse tal cual (y
      // deliberadamente igual para todos los motivos por los que un token
      // puede no valer). Solo se reemplaza cuando ni siquiera hubo
      // respuesta: ahí `err` es un fallo de red, sin mensaje útil.
      const mensaje =
        err instanceof ApiError
          ? err.message
          : "No pudimos conectarnos con el servidor. Revisa tu internet e inténtalo de nuevo.";
      setError(mensaje);
      // Un token inválido, vencido o ya usado no mejora reintentando: el
      // formulario desaparece y se muestra la salida real (escribirnos)
      // en vez de dejarlo golpeando un botón que nunca va a funcionar.
      const enlaceInservible =
        err instanceof ApiError && ["INVALIDO", "EXPIRADO", "MAX_INTENTOS"].includes(err.tipo ?? "");
      setFase(enlaceInservible ? "enlaceRoto" : "formulario");
    }
  }

  return (
    <MotionConfig reducedMotion="user">
      <div className="bg-mesh-panaderia flex min-h-screen flex-col items-center justify-center px-6 py-16">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.55, ease: EASE_PREMIUM }}
          className="w-full max-w-md"
        >
          <a
            href="/"
            className="mb-6 block text-center font-[family-name:var(--font-display-panaderia)] text-xl font-semibold text-pan-terracota-profundo transition-opacity hover:opacity-80"
          >
            Panadería Ronceros
          </a>

          <div className="rounded-3xl border border-pan-borde/50 bg-pan-crema-suave p-6 shadow-md shadow-pan-carbon/5 sm:p-8">
            <AnimatePresence mode="wait">
              {fase === "exito" ? (
                <PanelExito key="exito" tituloRef={tituloExitoRef} />
              ) : fase === "enlaceRoto" ? (
                <PanelEnlaceRoto key="roto" mensaje={error} />
              ) : (
                <motion.form
                  key="formulario"
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  exit={{ opacity: 0 }}
                  onSubmit={enviar}
                  className="space-y-6"
                >
                  <header className="text-center">
                    <span className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-pan-terracota-suave/60">
                      <KeyRound className="h-5 w-5 text-pan-terracota" strokeWidth={1.75} />
                    </span>
                    <h1 className="mt-4 font-[family-name:var(--font-display-panaderia)] text-2xl font-semibold text-pan-carbon">
                      Activa tu cuenta
                    </h1>
                    <p className="mt-2 text-sm leading-relaxed text-pan-carbon-suave">
                      Elige la contraseña con la que vas a entrar. Tu usuario es el mismo documento
                      con el que hiciste el pedido.
                    </p>
                  </header>

                  <div className="space-y-4">
                    <div>
                      <label
                        htmlFor="password"
                        className="mb-1.5 block text-sm font-medium text-pan-carbon"
                      >
                        Nueva contraseña
                      </label>
                      <div className="relative">
                        <input
                          id="password"
                          name="password"
                          // `new-password` es lo que le dice al gestor de
                          // contraseñas del navegador que ofrezca GUARDAR una
                          // nueva en vez de autocompletar una vieja.
                          autoComplete="new-password"
                          type={verPassword ? "text" : "password"}
                          value={password}
                          onChange={(e) => setPassword(e.target.value)}
                          minLength={LARGO_MINIMO_PASSWORD}
                          required
                          disabled={fase === "enviando"}
                          aria-describedby="ayuda-password"
                          className="campo-pan pr-12"
                          placeholder="Mínimo 8 caracteres"
                        />
                        <button
                          type="button"
                          onClick={() => setVerPassword((v) => !v)}
                          // El botón de ver/ocultar afecta a los DOS campos:
                          // decirlo evita que un lector de pantalla lo
                          // anuncie como si solo tocara el de arriba.
                          aria-label={
                            verPassword ? "Ocultar las contraseñas" : "Mostrar las contraseñas"
                          }
                          className="absolute inset-y-0 right-0 flex w-11 items-center justify-center text-pan-carbon-suave transition-colors hover:text-pan-terracota"
                        >
                          {verPassword ? (
                            <EyeOff className="h-4 w-4" strokeWidth={1.75} />
                          ) : (
                            <Eye className="h-4 w-4" strokeWidth={1.75} />
                          )}
                        </button>
                      </div>
                      <p id="ayuda-password" className="mt-1.5 text-xs text-pan-carbon-suave">
                        Al menos {LARGO_MINIMO_PASSWORD} caracteres. Usa algo que recuerdes.
                      </p>
                    </div>

                    <div>
                      <label
                        htmlFor="confirmacion"
                        className="mb-1.5 block text-sm font-medium text-pan-carbon"
                      >
                        Repite la contraseña
                      </label>
                      <input
                        id="confirmacion"
                        name="confirmacion"
                        autoComplete="new-password"
                        type={verPassword ? "text" : "password"}
                        value={confirmacion}
                        onChange={(e) => setConfirmacion(e.target.value)}
                        minLength={LARGO_MINIMO_PASSWORD}
                        required
                        disabled={fase === "enviando"}
                        className="campo-pan"
                        placeholder="La misma de arriba"
                      />
                    </div>
                  </div>

                  <div aria-live="polite">
                    <AnimatePresence>
                      {error && (
                        <motion.div
                          initial={{ opacity: 0, height: 0 }}
                          animate={{ opacity: 1, height: "auto" }}
                          exit={{ opacity: 0, height: 0 }}
                          className="overflow-hidden"
                        >
                          <div className="flex items-start gap-2.5 rounded-xl border border-red-200 bg-red-50 px-4 py-3">
                            <AlertTriangle
                              className="mt-0.5 h-4 w-4 shrink-0 text-red-600"
                              strokeWidth={1.75}
                            />
                            <p className="text-sm font-medium text-red-700">{error}</p>
                          </div>
                        </motion.div>
                      )}
                    </AnimatePresence>
                  </div>

                  <motion.button
                    type="submit"
                    disabled={fase === "enviando"}
                    whileHover={{ scale: fase === "enviando" ? 1 : 1.015 }}
                    whileTap={{ scale: fase === "enviando" ? 1 : 0.985 }}
                    className="flex w-full items-center justify-center gap-2 rounded-full bg-pan-terracota px-6 py-3.5 font-semibold text-pan-crema shadow-lg shadow-pan-terracota/20 transition-shadow hover:shadow-xl hover:shadow-pan-terracota/30 disabled:opacity-60"
                  >
                    {fase === "enviando" ? (
                      <>
                        <Loader2 className="h-4 w-4 animate-spin" />
                        Activando…
                      </>
                    ) : (
                      "Activar mi cuenta"
                    )}
                  </motion.button>
                </motion.form>
              )}
            </AnimatePresence>
          </div>

          <p className="mt-6 text-center text-xs text-pan-carbon-suave">
            ¿Algo no cuadra?{" "}
            <a
              href={enlaceWhatsApp("Hola, tuve un problema al activar mi cuenta de la página web.")}
              target="_blank"
              rel="noopener noreferrer"
              className="font-semibold text-pan-terracota underline underline-offset-2"
            >
              Escríbenos por WhatsApp
            </a>
          </p>
        </motion.div>
      </div>
    </MotionConfig>
  );
}

/** Confirmación final. El botón grande NO es "seguir navegando": es el
 * enlace al portal donde ya puede entrar, que es lo único que la persona
 * quiere hacer en este momento. */
function PanelExito({ tituloRef }: { tituloRef: RefObject<HTMLHeadingElement | null> }) {
  return (
    <motion.div
      initial={{ opacity: 0, scale: 0.96 }}
      animate={{ opacity: 1, scale: 1 }}
      transition={{ duration: 0.4, ease: EASE_PREMIUM }}
      className="py-2 text-center"
    >
      <motion.div
        initial={{ scale: 0 }}
        animate={{ scale: 1 }}
        transition={{ type: "spring", stiffness: 260, damping: 15, delay: 0.1 }}
        className="relative mx-auto h-14 w-14"
      >
        {/* La misma onda que confirma un pedido enviado (ResumenPedidoExito):
            el "clic" visual de que algo se completó, igual en todo el sitio. */}
        <motion.span
          initial={{ scale: 0.6, opacity: 0.5 }}
          animate={{ scale: 2.1, opacity: 0 }}
          transition={{ duration: 1, ease: "easeOut", delay: 0.15 }}
          className="absolute inset-0 rounded-full bg-emerald-500/30"
        />
        <CheckCircle2 className="relative h-14 w-14 text-emerald-600" strokeWidth={1.6} />
      </motion.div>

      <h1
        ref={tituloRef}
        tabIndex={-1}
        className="mt-4 font-[family-name:var(--font-display-panaderia)] text-2xl font-semibold text-pan-carbon outline-none"
      >
        ¡Cuenta activada!
      </h1>
      <p className="mt-2 text-sm leading-relaxed text-pan-carbon-suave">
        Ya puedes entrar con tu documento y la contraseña que acabas de crear.
      </p>

      <motion.a
        href={URL_PORTAL_APP}
        whileHover={{ scale: 1.015 }}
        whileTap={{ scale: 0.985 }}
        className="mt-6 flex w-full items-center justify-center gap-2 rounded-full bg-pan-terracota px-6 py-3.5 font-semibold text-pan-crema shadow-lg shadow-pan-terracota/20 transition-shadow hover:shadow-xl hover:shadow-pan-terracota/30"
      >
        Ir a mi cuenta
        <ArrowRight className="h-4 w-4" strokeWidth={2} />
      </motion.a>

      <a
        href="/"
        className="mt-3 inline-block px-4 py-2 text-sm font-semibold text-pan-carbon-suave transition-colors hover:text-pan-terracota"
      >
        Volver a la página
      </a>
    </motion.div>
  );
}

/** Callejón sin salida honesto: el enlace no sirve y no hay ningún botón
 * acá que lo arregle (hoy no existe un "reenviar correo de activación"), así
 * que en vez de un error genérico se explica qué pasó y cuáles son las dos
 * salidas reales que sí tiene la persona. */
function PanelEnlaceRoto({ mensaje }: { mensaje: string | null }) {
  return (
    <motion.div
      initial={{ opacity: 0, scale: 0.96 }}
      animate={{ opacity: 1, scale: 1 }}
      exit={{ opacity: 0 }}
      transition={{ duration: 0.4, ease: EASE_PREMIUM }}
      className="py-2 text-center"
    >
      <span className="mx-auto flex h-14 w-14 items-center justify-center rounded-full bg-amber-100">
        <LinkIcon className="h-6 w-6 text-amber-600" strokeWidth={1.75} />
      </span>

      <h1 className="mt-4 font-[family-name:var(--font-display-panaderia)] text-2xl font-semibold text-pan-carbon">
        Este enlace ya no sirve
      </h1>
      <p className="mt-2 text-sm leading-relaxed text-pan-carbon-suave">
        {mensaje ?? "El enlace de activación venció o ya se usó."}
      </p>

      <a
        href={URL_PORTAL_APP}
        className="mt-6 flex w-full items-center justify-center gap-2 rounded-full border border-pan-borde bg-transparent px-6 py-3.5 font-semibold text-pan-carbon transition-colors hover:bg-pan-crema"
      >
        Ya tengo mi contraseña, entrar
        <ArrowRight className="h-4 w-4" strokeWidth={2} />
      </a>

      <a
        href={enlaceWhatsApp("Hola, mi enlace para activar la cuenta ya no funciona. ¿Me ayudan?")}
        target="_blank"
        rel="noopener noreferrer"
        className="mt-3 inline-block px-4 py-2 text-sm font-semibold text-pan-terracota transition-opacity hover:opacity-80"
      >
        Pedir ayuda por WhatsApp
      </a>
    </motion.div>
  );
}
