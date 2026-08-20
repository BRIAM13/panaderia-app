import { useEffect, useRef, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import {
  Ban,
  CheckCircle2,
  ChevronDown,
  Clock,
  Loader2,
  PackageSearch,
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

const EASE_PREMIUM = [0.16, 1, 0.3, 1] as const;

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

/** Búsqueda pública y sin login: solo el DNI, y los pedidos recientes del
 * cliente en cualquier estado. Mientras el panel queda abierto y todavía
 * hay algún pedido sin resolver, se vuelve a consultar solo cada 20s para
 * que el estado se vea al día sin que el cliente tenga que volver a
 * buscar. Para historial completo, deudas o cancelar un pedido, ese es
 * trabajo de la cuenta real dentro de /app/, no de esta vista rápida. */
export function SeguimientoPedido() {
  const [abierto, setAbierto] = useState(false);
  const [dni, setDni] = useState("");
  const [buscando, setBuscando] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [resultado, setResultado] = useState<PedidoPublicoConsultaResultado | null>(null);
  const dniConsultadoRef = useRef("");
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

  async function buscar(e: React.FormEvent) {
    e.preventDefault();
    setError(null);

    const dniLimpio = dni.trim();
    if (!/^\d{8}$/.test(dniLimpio)) {
      setError("Ingresa un DNI válido de 8 dígitos.");
      return;
    }

    setBuscando(true);
    setResultado(null);
    try {
      const data = await consultarPedidosPublicos(dniLimpio);
      dniConsultadoRef.current = dniLimpio;
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
    setDni("");
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
        const data = await consultarPedidosPublicos(dniConsultadoRef.current);
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
        viewport={{ once: true, margin: "-80px" }}
        transition={{ duration: 0.6, ease: EASE_PREMIUM }}
        className="mx-auto max-w-4xl overflow-hidden rounded-3xl bg-gradient-to-br from-pan-terracota to-pan-terracota-profundo shadow-lg shadow-pan-terracota/20"
      >
        <button
          onClick={alternar}
          className="group flex w-full flex-col items-center gap-6 px-8 py-12 text-center sm:flex-row sm:text-left"
        >
          <motion.div
            whileHover={{ rotate: -8, scale: 1.05 }}
            className="flex h-14 w-14 shrink-0 items-center justify-center rounded-2xl bg-pan-crema/15 text-pan-crema"
          >
            <PackageSearch className="h-7 w-7" />
          </motion.div>
          <div className="flex-1">
            <h3 className="font-[family-name:var(--font-display-panaderia)] text-2xl font-semibold text-pan-crema">
              ¿Ya hiciste un pedido antes?
            </h3>
            <p className="mt-1 text-pan-crema/95">
              Escribe tu DNI y te decimos si tu pedido ya está confirmado o si todavía estamos por
              confirmarlo.
            </p>
          </div>
          <span className="inline-flex shrink-0 items-center gap-2 rounded-full bg-pan-crema px-6 py-3.5 font-semibold text-pan-terracota shadow-md transition-transform duration-300 group-hover:scale-105">
            {abierto ? "Cerrar" : "Ver mi pedido"}
          </span>
        </button>

        <AnimatePresence initial={false}>
          {abierto && (
            <motion.div
              initial={{ height: 0, opacity: 0 }}
              animate={{ height: "auto", opacity: 1 }}
              exit={{ height: 0, opacity: 0 }}
              transition={{ duration: 0.4, ease: EASE_PREMIUM }}
            >
              <div className="border-t border-pan-crema/15 bg-pan-crema px-8 py-8">
                <AnimatePresence mode="wait">
                  {resultado ? (
                    <motion.div
                      key="resultado"
                      initial={{ opacity: 0, y: 8 }}
                      animate={{ opacity: 1, y: 0 }}
                      className="mx-auto max-w-md"
                    >
                      {resultado.pedidos.length === 0 ? (
                        <div className="text-center">
                          <p className="text-pan-carbon">
                            {resultado.nombre
                              ? `Hola, ${resultado.nombre}. Todavía no tienes ningún pedido registrado.`
                              : "No encontramos ningún cliente con ese DNI todavía. Si acabas de hacer tu primer pedido, revisa que el DNI esté bien escrito."}
                          </p>
                        </div>
                      ) : (
                        <div>
                          {resultado.nombre && (
                            <p className="mb-4 text-center text-sm font-medium text-pan-carbon-suave">
                              Hola, {resultado.nombre}
                            </p>
                          )}
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
                                              <div className="mt-2.5 grid grid-cols-2 gap-x-3 gap-y-1.5 border-t border-pan-borde/30 pt-2.5 text-sm">
                                                <span className="text-pan-carbon-suave">Cantidad</span>
                                                <span className="text-right font-medium text-pan-carbon">
                                                  {pedido.cantidad}
                                                </span>
                                                <span className="text-pan-carbon-suave">Tienda</span>
                                                <span className="text-right font-medium text-pan-carbon">
                                                  {pedido.tienda ?? "—"}
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
                        className="mx-auto mt-6 flex items-center gap-1.5 text-sm font-semibold text-pan-terracota hover:underline"
                      >
                        <X className="h-3.5 w-3.5" />
                        Buscar con otro DNI
                      </button>
                    </motion.div>
                  ) : (
                    <motion.form
                      key="formulario"
                      initial={{ opacity: 0 }}
                      animate={{ opacity: 1 }}
                      onSubmit={buscar}
                      className="mx-auto flex max-w-md flex-col items-center gap-3 sm:flex-row sm:items-start"
                    >
                      <div className="w-full">
                        <input
                          id="dni-seguimiento"
                          inputMode="numeric"
                          maxLength={8}
                          value={dni}
                          onChange={(e) => setDni(e.target.value.replace(/\D/g, ""))}
                          placeholder="Tu DNI, 8 dígitos"
                          required
                          className="w-full rounded-xl border border-pan-borde bg-pan-crema px-4 py-3 text-pan-carbon outline-none focus:border-pan-terracota"
                        />
                        {error && <p className="mt-1.5 text-sm font-medium text-red-700">{error}</p>}
                      </div>
                      <button
                        type="submit"
                        disabled={buscando}
                        className="flex w-full shrink-0 items-center justify-center gap-2 rounded-xl bg-pan-terracota px-6 py-3 font-semibold text-pan-crema transition-transform hover:scale-[1.02] disabled:opacity-60 disabled:hover:scale-100 sm:w-auto"
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
                    </motion.form>
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
