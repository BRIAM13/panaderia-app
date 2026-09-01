import { useEffect, useRef, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import {
  AlertCircle,
  Ban,
  CheckCircle2,
  ChevronDown,
  Clock,
  Loader2,
  PackageSearch,
  SearchX,
  Truck,
  X,
  XCircle,
} from "lucide-react";
import {
  ApiError,
  consultarPedidosPublicos,
  type PedidoPublicoConsultaItem,
  type PedidoPublicoConsultaResultado,
} from "../services/api";
import { formatearHora12 } from "../utils/horariosPan";
import { EASE_PREMIUM, VIEWPORT_REVEAL } from "../utils/animacion";

const ESTADO_INFO = {
  SOLICITADO: {
    etiqueta: "Pendiente de confirmar",
    icono: Clock,
    clases: "bg-amber-100 text-amber-800",
  },
  PENDIENTE: {
    etiqueta: "Confirmado, por entregar",
    icono: Truck,
    clases: "bg-blue-100 text-blue-800",
  },
  ENTREGADO: {
    etiqueta: "Entregado",
    icono: CheckCircle2,
    clases: "bg-emerald-100 text-emerald-800",
  },
  RECHAZADO: {
    etiqueta: "Rechazado",
    icono: XCircle,
    clases: "bg-rose-100 text-rose-800",
  },
  CANCELADO: {
    etiqueta: "Cancelado",
    icono: Ban,
    clases: "bg-slate-200 text-slate-700",
  },
} as const;

// Mientras algún pedido siga en un estado que todavía puede cambiar, el
// panel se refresca solo — una vez que todos quedaron en un estado final
// (entregado/rechazado/cancelado) ya no hay nada más que esperar.
const ESTADOS_ACTIVOS = new Set(["SOLICITADO", "PENDIENTE"]);
const INTERVALO_REFRESCO_MS = 20000;

// Orden fijo de los grupos, sin importar el orden en que llegaron del
// servidor — primero lo ya resuelto a favor del cliente (entregado),
// después lo confirmado en camino, luego lo que todavía espera respuesta,
// y al final lo que no llegó a concretarse.
const ORDEN_ESTADOS = ["ENTREGADO", "PENDIENTE", "SOLICITADO", "RECHAZADO", "CANCELADO"] as const;

function agruparPedidos(pedidos: PedidoPublicoConsultaItem[]) {
  return ORDEN_ESTADOS.map((estado) => ({
    estado,
    pedidos: pedidos.filter((p) => p.estado === estado),
  })).filter((grupo) => grupo.pedidos.length > 0);
}

const FORMATO_FECHA_CORTA = new Intl.DateTimeFormat("es-PE", { day: "numeric", month: "short" });

/** ISO completo (con hora) -> "19 ago" — solo el día en que se registró,
 * como referencia rápida dentro de cada tarjeta, no la hora exacta. */
function formatearFechaCorta(fechaIso: string): string {
  return FORMATO_FECHA_CORTA.format(new Date(fechaIso));
}

/** ISO completo -> "19 ago, 3:15pm" — día y hora juntos, para las filas de
 * "Registrado" y "Recojo" de cada tarjeta (mismo formato de hora que usa
 * PedidoForm, sin espacio ni puntos, para que se lea igual en todo el
 * sitio). */
function formatearFechaHora(fechaIso: string): string {
  const fecha = new Date(fechaIso);
  const horaTexto = `${String(fecha.getHours()).padStart(2, "0")}:${String(fecha.getMinutes()).padStart(2, "0")}`;
  return `${formatearFechaCorta(fechaIso)}, ${formatearHora12(horaTexto)}`;
}

type TipoDocumento = "DNI" | "RUC";

const LONGITUD_DOCUMENTO: Record<TipoDocumento, number> = { DNI: 8, RUC: 11 };

/** Búsqueda pública y sin login: DNI o RUC (el cliente elige cuál), y los
 * pedidos recientes del cliente en cualquier estado. Es una consulta pura
 * contra nuestra propia base — nunca gasta un consumo de la API paga de
 * RENIEC/SUNAT, a diferencia de la verificación de documento del
 * formulario de pedido. Mientras el panel queda abierto y todavía hay
 * algún pedido sin resolver, se vuelve a consultar solo cada 20s para que
 * el estado se vea al día sin que el cliente tenga que volver a buscar.
 * Para historial completo, deudas o cancelar un pedido, ese es trabajo de
 * la cuenta real dentro de /app/, no de esta vista rápida. */
export function SeguimientoPedido() {
  const [abierto, setAbierto] = useState(false);
  const [tipoDocumento, setTipoDocumento] = useState<TipoDocumento>("DNI");
  const [documento, setDocumento] = useState("");
  const [buscando, setBuscando] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [resultado, setResultado] = useState<PedidoPublicoConsultaResultado | null>(null);
  const documentoConsultadoRef = useRef("");
  // Qué grupos (por estado) están desplegados — arrancan todos plegados;
  // el cliente elige cuál abrir. Un refresco del sondeo no toca esto, así
  // que un grupo que ya abrió no se le vuelve a cerrar solo.
  const [gruposAbiertos, setGruposAbiertos] = useState<Set<string>>(new Set());

  function alternarGrupo(estado: string) {
    setGruposAbiertos((actual) => {
      const nuevo = new Set(actual);
      if (nuevo.has(estado)) nuevo.delete(estado);
      else nuevo.add(estado);
      return nuevo;
    });
  }

  function alternar() {
    setAbierto((v) => !v);
    setError(null);
    setResultado(null);
    setGruposAbiertos(new Set());
  }

  function elegirTipoDocumento(tipo: TipoDocumento) {
    setTipoDocumento(tipo);
    setDocumento("");
    setError(null);
  }

  async function buscar(e: React.FormEvent) {
    e.preventDefault();
    setError(null);

    const documentoLimpio = documento.trim();
    const longitud = LONGITUD_DOCUMENTO[tipoDocumento];
    if (documentoLimpio.length !== longitud || !/^\d+$/.test(documentoLimpio)) {
      setError(`Ingresa un ${tipoDocumento} válido de ${longitud} dígitos.`);
      return;
    }

    setBuscando(true);
    setResultado(null);
    try {
      const data = await consultarPedidosPublicos(documentoLimpio);
      documentoConsultadoRef.current = documentoLimpio;
      setResultado(data);
    } catch (err) {
      if (err instanceof ApiError) {
        setError(err.message);
      } else {
        setError("No pudimos conectar porque el servidor puede estar despertando. Intenta de nuevo en un momento.");
      }
    } finally {
      setBuscando(false);
    }
  }

  function buscarOtroVez() {
    setResultado(null);
    setError(null);
    setDocumento("");
    setGruposAbiertos(new Set());
  }

  // Sondeo en tiempo real: solo mientras el panel está abierto, hay un
  // resultado en pantalla, y todavía queda algún pedido en un estado que
  // puede seguir cambiando — así no gasta llamadas de más una vez que ya
  // no hay nada pendiente de resolver.
  useEffect(() => {
    if (!abierto || !resultado) return;
    const hayPedidosActivos = resultado.pedidos.some((p) => ESTADOS_ACTIVOS.has(p.estado));
    if (!hayPedidosActivos) return;

    const id = window.setInterval(async () => {
      try {
        const data = await consultarPedidosPublicos(documentoConsultadoRef.current);
        setResultado(data);
      } catch {
        // Silencioso: un refresco puntual que falla (red, servidor
        // despertando) simplemente se reintenta en el próximo ciclo.
      }
    }, INTERVALO_REFRESCO_MS);
    return () => window.clearInterval(id);
  }, [abierto, resultado]);

  return (
    <section className="px-6 py-16">
      <motion.div
        initial={{ opacity: 0, y: 24 }}
        whileInView={{ opacity: 1, y: 0 }}
        viewport={VIEWPORT_REVEAL}
        transition={{ duration: 0.6, ease: EASE_PREMIUM }}
        className="relative mx-auto max-w-4xl overflow-hidden rounded-3xl bg-gradient-to-br from-pan-terracota to-pan-terracota-profundo shadow-lg shadow-pan-terracota/20"
      >
        {/* Brillo diagonal fijo sobre el degradado: sin él, este bloque —
            el único de color sólido de toda la página — se veía como un
            rectángulo plano frente al resto de superficies con textura. */}
        <div
          aria-hidden="true"
          className="pointer-events-none absolute inset-0 bg-[radial-gradient(ellipse_70%_60%_at_12%_0%,rgba(253,246,236,0.16),transparent_60%)]"
        />
        <button
          onClick={alternar}
          aria-expanded={abierto}
          // La fila (ícono · texto · botón) espera a md: a 640px el título
          // y la bajada quedaban comprimidos contra el botón, partiéndose
          // en dos y tres renglones cada uno. Hasta ahí, la versión
          // centrada en columna se lee mucho mejor.
          className="group relative flex w-full flex-col items-center gap-6 px-5 py-9 text-center sm:px-8 sm:py-12 md:flex-row md:text-left"
        >
          <motion.div
            whileHover={{ rotate: -8, scale: 1.05 }}
            className="flex h-14 w-14 shrink-0 items-center justify-center rounded-2xl bg-pan-crema/15 text-pan-crema ring-1 ring-pan-crema/20"
          >
            <PackageSearch className="h-7 w-7" strokeWidth={1.6} />
          </motion.div>
          <div className="flex-1">
            <p className="mb-1.5 text-[11px] font-semibold tracking-[0.18em] text-pan-crema/70 uppercase">
              Seguimiento
            </p>
            <h3 className="equilibrar-texto font-[family-name:var(--font-display-panaderia)] text-xl font-semibold text-pan-crema sm:text-2xl">
              ¿Ya hiciste un pedido antes?
            </h3>
            <p className="mt-1 text-pan-crema/95">
              Escribe tu DNI o RUC y te decimos si tu pedido ya está confirmado o si todavía estamos
              por confirmarlo.
            </p>
          </div>
          <span className="inline-flex min-h-12 shrink-0 items-center gap-2 rounded-full bg-pan-crema px-6 font-semibold text-pan-terracota shadow-md transition-transform duration-300 group-hover:scale-105">
            {abierto ? "Cerrar" : "Ver mi pedido"}
            <ChevronDown
              className={`h-4 w-4 transition-transform duration-300 ${abierto ? "rotate-180" : ""}`}
              strokeWidth={2}
            />
          </span>
        </button>

        <AnimatePresence initial={false}>
          {abierto && (
            <motion.div
              initial={{ height: 0, opacity: 0 }}
              animate={{ height: "auto", opacity: 1 }}
              exit={{ height: 0, opacity: 0 }}
              transition={{ duration: 0.4, ease: EASE_PREMIUM }}
              className="relative"
            >
              <div className="border-t border-pan-crema/15 bg-pan-crema px-4 py-6 sm:px-8 sm:py-8">
                <AnimatePresence mode="wait">
                  {resultado ? (
                    <motion.div
                      key="resultado"
                      initial={{ opacity: 0, y: 8 }}
                      animate={{ opacity: 1, y: 0 }}
                      className="mx-auto max-w-md"
                    >
                      {resultado.pedidos.length === 0 ? (
                        // Estado vacío con cara propia: antes era una sola
                        // línea de texto suelta en medio del panel y se
                        // leía como si algo hubiera fallado.
                        <div className="flex flex-col items-center gap-4 py-4 text-center">
                          <motion.span
                            initial={{ scale: 0.6, opacity: 0 }}
                            animate={{ scale: 1, opacity: 1 }}
                            transition={{ type: "spring", stiffness: 240, damping: 18 }}
                            className="flex h-16 w-16 items-center justify-center rounded-2xl bg-pan-bronce-suave/60 text-pan-bronce-oscuro"
                          >
                            <SearchX className="h-7 w-7" strokeWidth={1.6} />
                          </motion.span>
                          <p className="max-w-xs leading-relaxed text-pan-carbon">
                            {resultado.nombre
                              ? `Hola, ${resultado.nombre}. Todavía no tienes ningún pedido registrado.`
                              : `No encontramos ningún cliente con ese ${tipoDocumento} todavía. Si acabas de hacer tu primer pedido, revisa que el ${tipoDocumento} esté bien escrito.`}
                          </p>
                        </div>
                      ) : (
                        <div>
                          {resultado.nombre && (
                            <p className="mb-4 text-center text-sm font-medium text-pan-carbon-suave">
                              Hola, {resultado.nombre}
                            </p>
                          )}

                          {/* A simple vista, sin tener que desplegar nada —
                              los pedidos más recientes ya vienen primero
                              (el backend los manda ordenados por fecha). */}
                          <p className="mb-2 text-xs font-semibold tracking-wide text-pan-carbon-suave uppercase">
                            Tus últimos pedidos
                          </p>
                          <div className="mb-6 space-y-2">
                            {resultado.pedidos.slice(0, 3).map((pedido) => {
                              const info = ESTADO_INFO[pedido.estado];
                              const Icono = info.icono;
                              return (
                                // En pantallas angostas el chip de estado y
                                // el nombre del pedido no entran en la misma
                                // línea: el título terminaba recortado a
                                // "Ped…". Ahí el estado pasa debajo, y solo
                                // vuelven a compartir fila cuando hay ancho.
                                <div
                                  key={pedido.idPedido}
                                  className="flex flex-col items-start gap-2 rounded-xl border border-pan-borde/40 bg-pan-crema-suave px-4 py-3 transition-colors duration-300 hover:border-pan-borde/70 sm:flex-row sm:items-center sm:justify-between sm:gap-3"
                                >
                                  <div className="min-w-0">
                                    <p className="truncate text-sm font-semibold text-pan-carbon">
                                      Pedido #{pedido.numeroPedidoDia}
                                    </p>
                                    <p className="truncate text-xs text-pan-carbon-suave">{pedido.producto}</p>
                                  </div>
                                  <span
                                    className={`inline-flex shrink-0 items-center gap-1.5 rounded-full px-3 py-1.5 text-xs font-semibold ${info.clases}`}
                                  >
                                    <Icono className="h-3.5 w-3.5" />
                                    {info.etiqueta}
                                  </span>
                                </div>
                              );
                            })}
                          </div>

                          <p className="mb-2 text-xs font-semibold tracking-wide text-pan-carbon-suave uppercase">
                            Todos tus pedidos
                          </p>
                          <div className="space-y-3">
                            {agruparPedidos(resultado.pedidos).map((grupo) => {
                              const info = ESTADO_INFO[grupo.estado];
                              const Icono = info.icono;
                              const abiertoGrupo = gruposAbiertos.has(grupo.estado);
                              return (
                                <div
                                  key={grupo.estado}
                                  className="overflow-hidden rounded-2xl border border-pan-borde/40 bg-pan-crema-suave shadow-sm shadow-pan-carbon/5"
                                >
                                  <button
                                    type="button"
                                    onClick={() => alternarGrupo(grupo.estado)}
                                    aria-expanded={abiertoGrupo}
                                    className="flex w-full items-center justify-between gap-3 px-4 py-3.5 text-left transition-colors hover:bg-pan-terracota-suave/20"
                                  >
                                    <span className="flex items-center gap-3">
                                      <span
                                        className={`flex h-9 w-9 shrink-0 items-center justify-center rounded-full ${info.clases}`}
                                      >
                                        <Icono className="h-4.5 w-4.5" />
                                      </span>
                                      <span>
                                        <span className="block text-sm font-semibold text-pan-carbon">
                                          {info.etiqueta}
                                        </span>
                                        <span className="block text-xs text-pan-carbon-suave">
                                          {grupo.pedidos.length}{" "}
                                          {grupo.pedidos.length === 1 ? "pedido" : "pedidos"}
                                        </span>
                                      </span>
                                    </span>
                                    <ChevronDown
                                      className={`h-4 w-4 shrink-0 text-pan-carbon-suave transition-transform duration-200 ${
                                        abiertoGrupo ? "rotate-180" : ""
                                      }`}
                                    />
                                  </button>
                                  <AnimatePresence initial={false}>
                                    {abiertoGrupo && (
                                      <motion.div
                                        initial={{ height: 0, opacity: 0 }}
                                        animate={{ height: "auto", opacity: 1 }}
                                        exit={{ height: 0, opacity: 0 }}
                                        transition={{ duration: 0.25, ease: EASE_PREMIUM }}
                                      >
                                        <ul className="space-y-2.5 border-t border-pan-borde/30 bg-pan-crema/60 px-4 py-3.5">
                                          {grupo.pedidos.map((pedido) => (
                                            <li
                                              key={pedido.idPedido}
                                              className="rounded-xl border border-pan-borde/40 bg-pan-crema-suave px-4 py-3"
                                            >
                                              <div className="flex items-baseline justify-between gap-2">
                                                <p className="font-semibold text-pan-carbon">
                                                  Pedido #{pedido.numeroPedidoDia}
                                                </p>
                                                <p className="shrink-0 text-xs text-pan-carbon-suave">
                                                  {formatearFechaCorta(pedido.fechaCreacion)}
                                                </p>
                                              </div>
                                              <p className="mt-0.5 text-sm text-pan-carbon-suave">{pedido.producto}</p>
                                              {/* `auto` + `1fr` en vez de dos
                                                  mitades iguales: partidas al
                                                  medio, la columna del valor
                                                  se quedaba en ~110px y
                                                  "31 ago., 7:19pm" caía en dos
                                                  renglones mientras la
                                                  etiqueta ("Total") dejaba
                                                  medio ancho vacío al lado. */}
                                              <div className="mt-2.5 grid grid-cols-[auto_1fr] gap-x-3 gap-y-1.5 border-t border-pan-borde/30 pt-2.5 text-sm">
                                                <span className="text-pan-carbon-suave">Registrado</span>
                                                <span className="text-right font-medium text-pan-carbon">
                                                  {formatearFechaHora(pedido.fechaCreacion)}
                                                </span>
                                                {pedido.fechaEntrega && (
                                                  <>
                                                    <span className="text-pan-carbon-suave">Recojo</span>
                                                    <span className="text-right font-medium text-pan-carbon">
                                                      {formatearFechaHora(pedido.fechaEntrega)}
                                                    </span>
                                                  </>
                                                )}
                                                <span className="text-pan-carbon-suave">Cantidad</span>
                                                <span className="text-right font-medium text-pan-carbon">
                                                  {pedido.cantidad}
                                                </span>
                                                <span className="text-pan-carbon-suave">Total</span>
                                                <span className="text-right font-semibold text-pan-terracota">
                                                  S/ {pedido.total.toFixed(2)}
                                                </span>
                                              </div>
                                            </li>
                                          ))}
                                        </ul>
                                      </motion.div>
                                    )}
                                  </AnimatePresence>
                                </div>
                              );
                            })}
                          </div>
                        </div>
                      )}
                      <button
                        onClick={buscarOtroVez}
                        className="mx-auto mt-4 flex min-h-11 items-center gap-1.5 rounded-full px-4 text-sm font-semibold text-pan-terracota hover:underline"
                      >
                        <X className="h-3.5 w-3.5" />
                        Buscar con otro documento
                      </button>
                    </motion.div>
                  ) : (
                    <motion.div
                      key="formulario"
                      initial={{ opacity: 0 }}
                      animate={{ opacity: 1 }}
                      className="mx-auto flex max-w-md flex-col items-center gap-3"
                    >
                      <div
                        role="radiogroup"
                        aria-label="Tipo de documento"
                        className="inline-flex rounded-full bg-pan-borde/30 p-1"
                      >
                        {(["DNI", "RUC"] as const).map((tipo) => (
                          <button
                            key={tipo}
                            type="button"
                            role="radio"
                            aria-checked={tipoDocumento === tipo}
                            onClick={() => elegirTipoDocumento(tipo)}
                            className={`relative min-h-10 rounded-full px-6 text-sm font-semibold transition-colors ${
                              tipoDocumento === tipo ? "text-pan-crema" : "text-pan-carbon-suave hover:text-pan-carbon"
                            }`}
                          >
                            {tipoDocumento === tipo && (
                              <motion.span
                                layoutId="seguimiento-tipo-documento-activo"
                                className="absolute inset-0 rounded-full bg-pan-terracota"
                                transition={{ duration: 0.25, ease: EASE_PREMIUM }}
                              />
                            )}
                            <span className="relative">{tipo}</span>
                          </button>
                        ))}
                      </div>

                      <form
                        onSubmit={buscar}
                        className="flex w-full flex-col items-center gap-3 sm:flex-row sm:items-start"
                      >
                        <div className="w-full">
                          <input
                            id="documento-seguimiento"
                            inputMode="numeric"
                            maxLength={LONGITUD_DOCUMENTO[tipoDocumento]}
                            value={documento}
                            onChange={(e) => setDocumento(e.target.value.replace(/\D/g, ""))}
                            placeholder={`Tu ${tipoDocumento}, ${LONGITUD_DOCUMENTO[tipoDocumento]} dígitos`}
                            required
                            aria-invalid={Boolean(error)}
                            className="campo-pan"
                          />
                          {error && (
                            <p role="alert" className="mt-1.5 flex items-start gap-1.5 text-sm font-medium text-red-700">
                              <AlertCircle className="mt-0.5 h-3.5 w-3.5 shrink-0" strokeWidth={2} />
                              {error}
                            </p>
                          )}
                        </div>
                        <button
                          type="submit"
                          disabled={buscando}
                          className="flex w-full shrink-0 items-center justify-center gap-2 rounded-xl bg-pan-terracota px-6 py-3 font-semibold text-pan-crema shadow-sm shadow-pan-terracota/25 transition-all duration-300 hover:scale-[1.02] hover:shadow-md hover:shadow-pan-terracota/35 disabled:opacity-60 disabled:hover:scale-100 sm:w-auto"
                        >
                          {buscando ? (
                            <>
                              <Loader2 className="h-4 w-4 animate-spin" />
                              Buscando…
                            </>
                          ) : (
                            "Buscar"
                          )}
                        </button>
                      </form>

                      {/* Mientras el servidor responde (que puede tardar si
                          está despertando) se dibuja la silueta de las
                          tarjetas que van a llegar, en vez de dejar el
                          panel vacío con solo el botón girando. */}
                      <AnimatePresence>
                        {buscando && (
                          <motion.div
                            initial={{ opacity: 0, height: 0 }}
                            animate={{ opacity: 1, height: "auto" }}
                            exit={{ opacity: 0, height: 0 }}
                            transition={{ duration: 0.3, ease: EASE_PREMIUM }}
                            aria-hidden="true"
                            className="w-full overflow-hidden"
                          >
                            <div className="mt-2 space-y-2 pt-2">
                              {[0, 1, 2].map((i) => (
                                <div
                                  key={i}
                                  className="esqueleto h-[62px] w-full rounded-xl border border-pan-borde/25"
                                  style={{ opacity: 1 - i * 0.25 }}
                                />
                              ))}
                            </div>
                          </motion.div>
                        )}
                      </AnimatePresence>
                    </motion.div>
                  )}
                </AnimatePresence>
              </div>
            </motion.div>
          )}
        </AnimatePresence>
      </motion.div>
    </section>
  );
}
