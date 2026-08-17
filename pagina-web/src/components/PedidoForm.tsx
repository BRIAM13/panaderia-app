import { useEffect, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { CheckCircle2, Loader2, ShoppingBag } from "lucide-react";
import { PRODUCTOS } from "../data/config";
import { EVENTO_PEDIDO_ENVIADO } from "../lib/eventos";
import {
  ApiError,
  crearPedidoPublico,
  obtenerCatalogoPublico,
  type PedidoPublicoResultado,
  type ProductoPublico,
} from "../services/api";

const EASE_PREMIUM = [0.16, 1, 0.3, 1] as const;
const NOMBRES_DISPONIBLES = new Set(PRODUCTOS.map((p) => p.nombreEnCatalogo));

// Pan vendido por unidad (Pan de Agua/Francés) tiene un pedido mínimo — el
// pan de hamburguesa no aplica, se vende por paquete de 12 a precio fijo.
// Mismo mínimo que valida el backend (crearPedidoPublico), así el cliente
// ve el aviso antes de intentar enviar un pedido que el servidor va a
// rechazar igual.
const CANTIDAD_MINIMA_UNIDAD = 50;

export function PedidoForm() {
  const [productos, setProductos] = useState<ProductoPublico[]>([]);
  const [cargandoProductos, setCargandoProductos] = useState(true);
  const [errorCatalogo, setErrorCatalogo] = useState<string | null>(null);

  const [dni, setDni] = useState("");
  const [telefono, setTelefono] = useState("");
  const [idProducto, setIdProducto] = useState<number | "">("");
  const [cantidad, setCantidad] = useState("");
  const [notas, setNotas] = useState("");

  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [resultado, setResultado] = useState<PedidoPublicoResultado | null>(null);

  useEffect(() => {
    obtenerCatalogoPublico()
      .then((lista) => {
        // Solo se ofrecen los panes que ya tienen foto y están en el menú
        // de arriba (ver PRODUCTOS en data/config.ts) — el resto sigue
        // existiendo en el sistema, pero todavía no se vende desde acá.
        const disponibles = lista.filter((p) => NOMBRES_DISPONIBLES.has(p.nombre));
        setProductos(disponibles);
        if (disponibles.length > 0) setIdProducto(disponibles[0].idProducto);
      })
      .catch(() =>
        setErrorCatalogo(
          "No pudimos cargar el catálogo porque el servidor puede estar despertando. Intenta de nuevo en un momento.",
        ),
      )
      .finally(() => setCargandoProductos(false));
  }, []);

  const productoSeleccionado = productos.find((p) => p.idProducto === idProducto);
  const esPaquete = productoSeleccionado?.esPaquete ?? false;
  const cantidadNum = Number(cantidad) || 0;
  const total = productoSeleccionado ? productoSeleccionado.precioUnitario * cantidadNum : 0;

  // Al cambiar de producto, la cantidad se limpia — el campo queda vacío
  // con un placeholder que ya indica qué escribir (ver más abajo), en vez
  // de arrastrar una cantidad que valía para el pan anterior.
  useEffect(() => {
    setCantidad("");
  }, [idProducto]);

  async function enviar(e: React.FormEvent) {
    e.preventDefault();
    setError(null);

    if (!/^\d{8}$/.test(dni.trim())) {
      setError("Ingresa un DNI válido de 8 dígitos.");
      return;
    }
    if (!/^\d{9}$/.test(telefono.trim())) {
      setError("Ingresa un número de celular válido de 9 dígitos.");
      return;
    }
    if (!idProducto) {
      setError("Selecciona un producto.");
      return;
    }
    if (!Number.isInteger(cantidadNum) || cantidadNum <= 0) {
      setError("Ingresa una cantidad válida.");
      return;
    }
    if (!esPaquete && cantidadNum < CANTIDAD_MINIMA_UNIDAD) {
      setError(`El pedido mínimo es de ${CANTIDAD_MINIMA_UNIDAD} panes.`);
      return;
    }

    setEnviando(true);
    try {
      const resultado = await crearPedidoPublico({
        dni: dni.trim(),
        telefono: telefono.trim(),
        idProducto: Number(idProducto),
        cantidad: cantidadNum,
        notas: notas.trim() || undefined,
      });
      setResultado(resultado);
      window.dispatchEvent(new Event(EVENTO_PEDIDO_ENVIADO));
    } catch (err) {
      if (err instanceof ApiError) {
        setError(err.errores?.join(" ") || err.message);
      } else {
        setError("No pudimos conectar porque el servidor puede estar despertando. Intenta de nuevo en un momento.");
      }
    } finally {
      setEnviando(false);
    }
  }

  function pedirOtroVez() {
    setResultado(null);
    setDni("");
    setTelefono("");
    setCantidad("");
    setNotas("");
  }

  return (
    <section id="pedido" className="px-6 py-24 sm:py-32">
      <div className="mx-auto max-w-xl">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, margin: "-100px" }}
          transition={{ duration: 0.6, ease: EASE_PREMIUM }}
          className="text-center"
        >
          <motion.div
            initial={{ opacity: 0, scale: 0.6, rotate: -20 }}
            whileInView={{ opacity: 1, scale: 1, rotate: 0 }}
            viewport={{ once: true, margin: "-100px" }}
            transition={{ duration: 0.6, ease: EASE_PREMIUM }}
            className="mx-auto mb-5 flex h-14 w-14 items-center justify-center rounded-2xl bg-pan-terracota-suave/60 text-pan-terracota"
          >
            <ShoppingBag className="h-7 w-7" />
          </motion.div>
          <h2 className="font-[family-name:var(--font-display-panaderia)] text-4xl font-semibold text-pan-carbon sm:text-5xl">
            Haz tu pedido
          </h2>
          <p className="mt-4 text-lg text-pan-carbon-suave">
            Déjanos tus datos y te llamamos para confirmarlo. No necesitas crear ninguna cuenta ni
            contraseña.
          </p>
        </motion.div>

        <motion.div
          initial={{ opacity: 0, y: 24 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, margin: "-80px" }}
          transition={{ duration: 0.6, ease: EASE_PREMIUM, delay: 0.1 }}
          className="mt-10 rounded-3xl border border-pan-bronce-suave/50 bg-pan-crema-suave p-6 shadow-md shadow-pan-carbon/5 sm:p-8"
        >
          <AnimatePresence mode="wait">
            {resultado ? (
              <motion.div
                key="exito"
                initial={{ opacity: 0, scale: 0.96 }}
                animate={{ opacity: 1, scale: 1 }}
                className="py-6 text-center"
              >
                <motion.div
                  initial={{ scale: 0 }}
                  animate={{ scale: 1 }}
                  transition={{ type: "spring", stiffness: 260, damping: 15, delay: 0.1 }}
                >
                  <CheckCircle2 className="mx-auto h-14 w-14 text-emerald-600" />
                </motion.div>
                <h3 className="mt-4 font-[family-name:var(--font-display-panaderia)] text-2xl font-semibold text-pan-carbon">
                  Pedido #{resultado.numeroPedidoDia} recibido
                </h3>
                <p className="mt-2 text-pan-carbon-suave">{resultado.mensaje}</p>
                <p className="mt-3 text-lg font-semibold text-pan-terracota">
                  Total: S/ {resultado.total.toFixed(2)}
                </p>
                <button
                  onClick={pedirOtroVez}
                  className="mt-6 rounded-full border border-pan-bronce-suave px-5 py-2.5 text-sm font-semibold text-pan-carbon transition-colors hover:bg-pan-crema-muted"
                >
                  Hacer otro pedido
                </button>
              </motion.div>
            ) : (
              <motion.form
                key="formulario"
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                onSubmit={enviar}
                className="space-y-5"
              >
                <div>
                  <label htmlFor="dni" className="mb-1.5 block text-sm font-medium text-pan-carbon">
                    DNI
                  </label>
                  <input
                    id="dni"
                    inputMode="numeric"
                    maxLength={8}
                    value={dni}
                    onChange={(e) => setDni(e.target.value.replace(/\D/g, ""))}
                    placeholder="Ingresa tu DNI"
                    required
                    className="w-full rounded-xl border border-pan-bronce-suave bg-pan-crema px-4 py-3 text-pan-carbon outline-none focus:border-pan-terracota"
                  />
                </div>

                <div>
                  <label htmlFor="telefono" className="mb-1.5 block text-sm font-medium text-pan-carbon">
                    Celular
                  </label>
                  <input
                    id="telefono"
                    inputMode="numeric"
                    maxLength={9}
                    value={telefono}
                    onChange={(e) => setTelefono(e.target.value.replace(/\D/g, ""))}
                    placeholder="Ingresa tu número de celular"
                    required
                    className="w-full rounded-xl border border-pan-bronce-suave bg-pan-crema px-4 py-3 text-pan-carbon outline-none focus:border-pan-terracota"
                  />
                </div>

                <div>
                  <label htmlFor="producto" className="mb-1.5 block text-sm font-medium text-pan-carbon">
                    Producto
                  </label>
                  <select
                    id="producto"
                    value={idProducto}
                    onChange={(e) => setIdProducto(Number(e.target.value))}
                    disabled={cargandoProductos || productos.length === 0}
                    required
                    className="w-full rounded-xl border border-pan-bronce-suave bg-pan-crema px-4 py-3 text-pan-carbon outline-none focus:border-pan-terracota disabled:opacity-60"
                  >
                    {cargandoProductos && <option>Cargando productos…</option>}
                    {!cargandoProductos &&
                      productos.map((p) => (
                        <option key={p.idProducto} value={p.idProducto}>
                          {p.nombre}
                        </option>
                      ))}
                  </select>
                  {errorCatalogo && <p className="mt-1.5 text-xs text-red-700">{errorCatalogo}</p>}
                  {productoSeleccionado && (
                    <p className="mt-1.5 text-xs text-pan-carbon-suave">
                      {esPaquete
                        ? "Cada paquete trae 12 panes de hamburguesa."
                        : `Pedido mínimo: ${CANTIDAD_MINIMA_UNIDAD} panes.`}
                    </p>
                  )}
                </div>

                <div>
                  <label htmlFor="cantidad" className="mb-1.5 block text-sm font-medium text-pan-carbon">
                    {esPaquete ? "Cantidad de paquetes" : "Cantidad"}
                  </label>
                  <input
                    id="cantidad"
                    inputMode="numeric"
                    maxLength={4}
                    value={cantidad}
                    onChange={(e) => setCantidad(e.target.value.replace(/\D/g, ""))}
                    placeholder={esPaquete ? "Ingresa cantidad de paquetes" : "Ingresa cantidad de panes"}
                    required
                    className="w-full rounded-xl border border-pan-bronce-suave bg-pan-crema px-4 py-3 text-pan-carbon outline-none focus:border-pan-terracota"
                  />
                </div>

                <div>
                  <label htmlFor="notas" className="mb-1.5 block text-sm font-medium text-pan-carbon">
                    Notas (opcional)
                  </label>
                  <textarea
                    id="notas"
                    value={notas}
                    onChange={(e) => setNotas(e.target.value)}
                    rows={2}
                    placeholder="Ej: para recoger mañana temprano"
                    className="w-full resize-none rounded-xl border border-pan-bronce-suave bg-pan-crema px-4 py-3 text-pan-carbon outline-none focus:border-pan-terracota"
                  />
                </div>

                {productoSeleccionado && cantidadNum > 0 && (
                  <motion.div
                    initial={{ opacity: 0, scale: 0.95 }}
                    animate={{ opacity: 1, scale: 1 }}
                    transition={{ duration: 0.25, ease: EASE_PREMIUM }}
                    className="flex items-center justify-between rounded-xl bg-pan-terracota-suave/40 px-4 py-3"
                  >
                    <span className="text-sm font-medium text-pan-carbon">Total estimado</span>
                    <span className="text-lg font-semibold text-pan-terracota">S/ {total.toFixed(2)}</span>
                  </motion.div>
                )}

                {error && <p className="text-sm font-medium text-red-700">{error}</p>}

                <motion.button
                  type="submit"
                  disabled={enviando || cargandoProductos}
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
                    "Enviar pedido"
                  )}
                </motion.button>
              </motion.form>
            )}
          </AnimatePresence>
        </motion.div>
      </div>
    </section>
  );
}
