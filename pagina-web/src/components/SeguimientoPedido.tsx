import { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { Clock, Loader2, PackageSearch, Truck, X } from "lucide-react";
import {
  ApiError,
  consultarPedidosPublicos,
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
    clases: "bg-emerald-100 text-emerald-800",
  },
} as const;

/** Búsqueda pública y sin login: solo el DNI, y solo pedidos SOLICITADO
 * (pendiente de confirmar) o PENDIENTE (confirmado, pendiente de entrega).
 * Para historial completo, deudas o cancelar un pedido, ese es trabajo de
 * la cuenta real dentro de /app/, no de esta vista rápida. */
export function SeguimientoPedido() {
  const [abierto, setAbierto] = useState(false);
  const [dni, setDni] = useState("");
  const [buscando, setBuscando] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [resultado, setResultado] = useState<PedidoPublicoConsultaResultado | null>(null);

  function alternar() {
    setAbierto((v) => !v);
    setError(null);
    setResultado(null);
  }

  async function buscar(e: React.FormEvent) {
    e.preventDefault();
    setError(null);

    if (!/^\d{8}$/.test(dni.trim())) {
      setError("Ingresa un DNI válido de 8 dígitos.");
      return;
    }

    setBuscando(true);
    setResultado(null);
    try {
      const data = await consultarPedidosPublicos(dni.trim());
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
  }

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
            className="flex h-14 w-14 shrink-0 items-center justify-center rounded-2xl bg-white/15 text-pan-crema"
          >
            <PackageSearch className="h-7 w-7" />
          </motion.div>
          <div className="flex-1">
            <h3 className="font-[family-name:var(--font-display-panaderia)] text-2xl font-semibold text-pan-crema">
              ¿Ya hiciste un pedido antes?
            </h3>
            <p className="mt-1 text-pan-crema/85">
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
              <div className="border-t border-white/15 bg-pan-crema px-8 py-8">
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
                              ? `Hola, ${resultado.nombre}. No tienes pedidos pendientes de confirmar ni de entregar en este momento.`
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
                          <ul className="space-y-3">
                            {resultado.pedidos.map((pedido) => {
                              const info = ESTADO_INFO[pedido.estado];
                              const Icono = info.icono;
                              return (
                                <li
                                  key={pedido.idPedido}
                                  className="rounded-2xl bg-pan-crema-suave px-5 py-4 shadow-sm shadow-pan-carbon/5"
                                >
                                  <div className="flex items-start justify-between gap-3">
                                    <div>
                                      <p className="font-semibold text-pan-carbon">
                                        Pedido #{pedido.numeroPedidoDia} · {pedido.producto}
                                      </p>
                                      <p className="text-sm text-pan-carbon-suave">
                                        {pedido.cantidad} · {pedido.tienda} · S/ {pedido.total.toFixed(2)}
                                      </p>
                                    </div>
                                    <span
                                      className={`inline-flex shrink-0 items-center gap-1.5 rounded-full px-3 py-1.5 text-xs font-semibold ${info.clases}`}
                                    >
                                      <Icono className="h-3.5 w-3.5" />
                                      {info.etiqueta}
                                    </span>
                                  </div>
                                </li>
                              );
                            })}
                          </ul>
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
                          className="w-full rounded-xl border border-pan-bronce-suave bg-white px-4 py-3 text-pan-carbon outline-none focus:border-pan-terracota"
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
