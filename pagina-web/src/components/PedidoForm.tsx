import { useEffect, useRef, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { AlertTriangle, CheckCircle2, Loader2, ShoppingBag } from "lucide-react";
import { PRODUCTOS } from "../data/config";
import {
  ApiError,
  crearPedidoPublico,
  obtenerCatalogoPublico,
  type HorariosPanaderia,
  type PedidoPublicoResultado,
  type ProductoPublico,
} from "../services/api";
import { esMuyProntoHoy, estaFueraDeVentana, formatearHora12, horaMinimaHoy, hoyISO } from "../utils/horariosPan";
import { SelectorFecha, type SelectorFechaHandle } from "./SelectorFecha";
import { SelectorHora, type SelectorHoraHandle } from "./SelectorHora";
import { SelectorProducto } from "./SelectorProducto";

const EASE_PREMIUM = [0.16, 1, 0.3, 1] as const;
const NOMBRES_DISPONIBLES = new Set(PRODUCTOS.map((p) => p.nombreEnCatalogo));

const FRASES_SALUDO = [
  "¡Hola! 👋",
  "¿Ya probaste nuestro pan?",
  "Recién horneado hoy 🍞",
  "¡Haz tu pedido!",
  "Pan de siempre, hecho en familia",
];

// Pan vendido por unidad (Pan de Agua/Francés) tiene un pedido mínimo — el
// pan de hamburguesa no aplica, se vende por paquete de 12 a precio fijo.
// Mismo mínimo que valida el backend (crearPedidoPublico), así el cliente
// ve el aviso antes de intentar enviar un pedido que el servidor va a
// rechazar igual.
const CANTIDAD_MINIMA_UNIDAD = 50;

export function PedidoForm() {
  const [productos, setProductos] = useState<ProductoPublico[]>([]);
  const [horarios, setHorarios] = useState<HorariosPanaderia | null>(null);
  const [cargandoProductos, setCargandoProductos] = useState(true);
  const [errorCatalogo, setErrorCatalogo] = useState<string | null>(null);

  const [tipoDocumento, setTipoDocumento] = useState<"DNI" | "RUC">("DNI");
  const [numeroDocumento, setNumeroDocumento] = useState("");
  const [telefono, setTelefono] = useState("");
  const [idProducto, setIdProducto] = useState<number | "">("");
  const [cantidad, setCantidad] = useState("");
  const [notas, setNotas] = useState("");
  const [fechaRecojo, setFechaRecojo] = useState("");
  const [horaRecojo, setHoraRecojo] = useState("");
  const [avisoFechaPrimero, setAvisoFechaPrimero] = useState(false);
  const selectorFechaRef = useRef<SelectorFechaHandle>(null);
  const selectorHoraRef = useRef<SelectorHoraHandle>(null);
  const abrirHoraLuegoDeFechaRef = useRef(false);

  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [resultado, setResultado] = useState<PedidoPublicoResultado | null>(null);
  const [fueraDeVentanaAlEnviar, setFueraDeVentanaAlEnviar] = useState(false);
  const [mascotaAgitada, setMascotaAgitada] = useState(false);
  const [mensajeMascota, setMensajeMascota] = useState<string | null>(null);
  const mensajeTimeoutRef = useRef<number | undefined>(undefined);
  const agitadoTimeoutRef = useRef<number | undefined>(undefined);

  // Un clic nuevo (u otro disparador, como llegar a esta sección) siempre
  // interrumpe el mensaje anterior en vez de sumarse — cancela el timeout
  // pendiente para que no cierre el mensaje nuevo antes de tiempo.
  function mostrarMensajeMascota(texto: string, duracionMs = 2200) {
    window.clearTimeout(mensajeTimeoutRef.current);
    setMensajeMascota(texto);
    mensajeTimeoutRef.current = window.setTimeout(() => setMensajeMascota(null), duracionMs);
  }

  function saludarMascota() {
    window.clearTimeout(agitadoTimeoutRef.current);
    setMascotaAgitada(true);
    agitadoTimeoutRef.current = window.setTimeout(() => setMascotaAgitada(false), 650);
    mostrarMensajeMascota(FRASES_SALUDO[Math.floor(Math.random() * FRASES_SALUDO.length)]);
  }

  // Reloj vivo: el piso de "minutos de tolerancia" depende del minuto
  // actual, así que si el cliente se queda mucho rato en la pantalla (por
  // ejemplo con el selector de hora abierto) el piso tiene que ir
  // avanzando solo, sin que haga falta ninguna acción suya — 15s alcanza
  // de sobra para no notarse el salto de minuto.
  const [ahora, setAhora] = useState(() => new Date());
  useEffect(() => {
    const id = window.setInterval(() => setAhora(new Date()), 15000);
    return () => window.clearInterval(id);
  }, []);

  useEffect(() => {
    obtenerCatalogoPublico()
      .then(({ productos: lista, horarios: horariosCatalogo }) => {
        // Solo se ofrecen los panes que ya tienen foto y están en el menú
        // de arriba (ver PRODUCTOS en data/config.ts) — el resto sigue
        // existiendo en el sistema, pero todavía no se vende desde acá.
        const disponibles = lista.filter((p) => NOMBRES_DISPONIBLES.has(p.nombre));
        setProductos(disponibles);
        setHorarios(horariosCatalogo);
        // El producto arranca sin elegir a propósito — el cliente tiene que
        // elegir uno de forma activa, no se preselecciona el primero.
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

  // Pan de Agua/Francés (no paquete) muestra el recojo — el pan de
  // hamburguesa (paquete) no lo usa. Solo aparece una vez que el cliente
  // eligió activamente un pan (idProducto !== ""), nunca antes.
  const mostrarCamposRecojo = idProducto !== "" && !esPaquete;

  // El cliente puede elegir cualquier fecha (desde hoy) y cualquier hora —
  // esto no bloquea nada, solo decide si se muestra el aviso de que ese
  // horario ya cerró (el pedido igual se registra; el negocio confirma
  // disponibilidad de stock por WhatsApp, ver el aviso más abajo).
  const fueraDeVentanaActual =
    horarios && fechaRecojo && horaRecojo ? estaFueraDeVentana(fechaRecojo, horaRecojo, horarios, ahora) : false;

  // Piso duro (a diferencia del aviso de arriba, que solo informa): si la
  // fecha elegida es hoy, ninguna hora a menos de "minutos de tolerancia"
  // desde ahora es válida — el selector de hora ya la deshabilita, esto
  // solo calcula desde qué hora arranca lo permitido para pasárselo. Se
  // recalcula con el reloj vivo (`ahora`), así el piso sigue avanzando
  // aunque el cliente se quede un buen rato con el selector abierto.
  const esRecojoHoy = fechaRecojo === hoyISO(ahora);
  const minimoHoraHoy = horarios && esRecojoHoy ? horaMinimaHoy(horarios, ahora) : undefined;

  // Al cambiar de producto, la cantidad y el recojo se limpian — quedan
  // vacíos con un placeholder que ya indica qué elegir (ver más abajo), en
  // vez de arrastrar un valor que valía para el pan anterior.
  useEffect(() => {
    setCantidad("");
    setFechaRecojo("");
    setHoraRecojo("");
  }, [idProducto]);

  // Si el cliente ya había elegido una hora y después cambia la fecha a
  // hoy (o el reloj avanza), esa hora puede quedar por debajo del nuevo
  // piso de tolerancia — se limpia en vez de dejar un valor que el envío
  // igual va a rechazar.
  useEffect(() => {
    if (horarios && fechaRecojo && horaRecojo && esMuyProntoHoy(fechaRecojo, horaRecojo, horarios, ahora)) {
      setHoraRecojo("");
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [fechaRecojo, horarios, ahora]);

  // Si el cliente toca "Elige una hora" sin haber elegido fecha todavía,
  // se abre el calendario en su lugar (con un aviso) y, apenas acepte una
  // fecha, el selector de hora se abre solo a continuación — así nunca
  // intenta elegir una hora sin saber para qué día es.
  function alIntentarAbrirHoraSinFecha() {
    abrirHoraLuegoDeFechaRef.current = true;
    setAvisoFechaPrimero(true);
    selectorFechaRef.current?.abrir();
  }

  useEffect(() => {
    if (!fechaRecojo || !abrirHoraLuegoDeFechaRef.current) return;
    abrirHoraLuegoDeFechaRef.current = false;
    setAvisoFechaPrimero(false);
    // Pequeña espera para que la animación de cierre del calendario no se
    // encime con la de apertura del selector de hora.
    const id = window.setTimeout(() => selectorHoraRef.current?.abrir(), 260);
    return () => window.clearTimeout(id);
  }, [fechaRecojo]);

  // El personaje festeja un instante cuando el pedido se confirma — un
  // gesto puntual, no una animación que se repite sola sin parar.
  useEffect(() => {
    if (!resultado) return;
    setMascotaAgitada(true);
    const id = window.setTimeout(() => setMascotaAgitada(false), 1400);
    return () => window.clearTimeout(id);
  }, [resultado]);

  async function enviar(e: React.FormEvent) {
    e.preventDefault();
    setError(null);

    const numeroDocumentoLimpio = numeroDocumento.trim();
    const largoEsperado = tipoDocumento === "DNI" ? 8 : 11;
    if (!new RegExp(`^\\d{${largoEsperado}}$`).test(numeroDocumentoLimpio)) {
      setError(
        tipoDocumento === "DNI"
          ? "Ingresa un DNI válido de 8 dígitos."
          : "Ingresa un RUC válido de 11 dígitos.",
      );
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

    let fechaEntrega: string | undefined;
    if (!esPaquete) {
      if (!fechaRecojo || !horaRecojo) {
        setError("Elige una fecha y hora de recojo.");
        return;
      }
      if (horarios && esMuyProntoHoy(fechaRecojo, horaRecojo, horarios)) {
        setError(`Para pedidos de hoy necesitamos al menos ${horarios.minutosTolerancia} minutos de anticipación.`);
        return;
      }
      fechaEntrega = `${fechaRecojo}T${horaRecojo}`;
    }

    setEnviando(true);
    try {
      const resultado = await crearPedidoPublico({
        documento: numeroDocumentoLimpio,
        telefono: telefono.trim(),
        idProducto: Number(idProducto),
        cantidad: cantidadNum,
        notas: notas.trim() || undefined,
        fechaEntrega,
      });
      setFueraDeVentanaAlEnviar(!esPaquete && fueraDeVentanaActual);
      setResultado(resultado);
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
    setFueraDeVentanaAlEnviar(false);
    setNumeroDocumento("");
    setTelefono("");
    setCantidad("");
    setNotas("");
    setFechaRecojo("");
    setHoraRecojo("");
  }

  return (
    <section id="pedido" className="px-6 py-24 sm:py-32">
      <div className="mx-auto max-w-xl">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, margin: "-100px" }}
          onViewportEnter={() =>
            window.setTimeout(() => mostrarMensajeMascota("Realiza tu pedido aquí 👇", 4000), 700)
          }
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

        <div className="relative mt-32 sm:mt-36">
          <AnimatePresence>
            {mensajeMascota && (
              <motion.div
                initial={{ opacity: 0, y: 8, scale: 0.85 }}
                animate={{ opacity: 1, y: 0, scale: 1 }}
                exit={{ opacity: 0, y: 8, scale: 0.85 }}
                transition={{ duration: 0.25, ease: EASE_PREMIUM }}
                className="absolute -top-14 right-6 z-10 -translate-y-full whitespace-nowrap rounded-2xl rounded-br-md bg-pan-crema-suave px-3.5 py-2 text-xs font-semibold text-pan-carbon shadow-lg shadow-pan-carbon/15 sm:-top-20 sm:right-10"
              >
                {mensajeMascota}
              </motion.div>
            )}
          </AnimatePresence>

          <motion.button
            type="button"
            onClick={saludarMascota}
            aria-label="Saludar al panadero"
            initial={{ opacity: 0, y: 20, rotate: -8 }}
            whileInView={{ opacity: 1, y: 0, rotate: -6 }}
            viewport={{ once: true, margin: "-80px" }}
            whileHover={{ scale: 1.05 }}
            whileTap={{ scale: 0.95 }}
            animate={
              mascotaAgitada ? { rotate: [-4, 6, -4, 6, -6] } : { rotate: -6 }
            }
            transition={
              mascotaAgitada
                ? { duration: 0.55, ease: "easeInOut" }
                : { duration: 0.5, ease: EASE_PREMIUM }
            }
            className="absolute -top-14 right-6 z-0 cursor-pointer sm:-top-20 sm:right-10"
          >
            <img
              src="/images/mascota/panadero.png"
              alt=""
              className="h-28 w-auto drop-shadow-lg sm:h-40"
            />
          </motion.button>

          <motion.div
            initial={{ opacity: 0, y: 24 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true, margin: "-80px" }}
            transition={{ duration: 0.6, ease: EASE_PREMIUM, delay: 0.1 }}
            className="relative z-10 rounded-3xl border border-pan-borde/50 bg-pan-crema-suave p-6 shadow-md shadow-pan-carbon/5 sm:p-8"
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
                {fueraDeVentanaAlEnviar && (
                  <p className="mx-auto mt-4 max-w-sm rounded-xl bg-amber-50 px-4 py-3 text-left text-xs font-medium text-amber-800">
                    Como el horario elegido ya cerró, te confirmaremos por WhatsApp al número que dejaste
                    si tenemos stock disponible para separar tu pedido.
                  </p>
                )}
                <button
                  onClick={pedirOtroVez}
                  className="boton-relleno mt-6 rounded-full border border-pan-borde px-5 py-2.5 text-sm font-semibold text-pan-carbon"
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
                  <label className="mb-1.5 block text-sm font-medium text-pan-carbon">Documento</label>
                  <div className="mb-2 inline-flex rounded-full border border-pan-borde bg-pan-crema p-1">
                    {(["DNI", "RUC"] as const).map((tipo) => (
                      <button
                        key={tipo}
                        type="button"
                        onClick={() => {
                          setTipoDocumento(tipo);
                          setNumeroDocumento("");
                        }}
                        className={`rounded-full px-5 py-1.5 text-sm font-semibold transition-colors ${
                          tipoDocumento === tipo
                            ? "bg-pan-terracota text-pan-crema"
                            : "text-pan-carbon-suave hover:text-pan-carbon"
                        }`}
                      >
                        {tipo}
                      </button>
                    ))}
                  </div>
                  <input
                    id="documento"
                    inputMode="numeric"
                    maxLength={tipoDocumento === "DNI" ? 8 : 11}
                    value={numeroDocumento}
                    onChange={(e) => setNumeroDocumento(e.target.value.replace(/\D/g, ""))}
                    placeholder={tipoDocumento === "DNI" ? "Ingresa tu DNI" : "Ingresa tu RUC"}
                    required
                    className="w-full rounded-xl border border-pan-borde bg-pan-crema px-4 py-3 text-pan-carbon outline-none focus:border-pan-terracota"
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
                    className="w-full rounded-xl border border-pan-borde bg-pan-crema px-4 py-3 text-pan-carbon outline-none focus:border-pan-terracota"
                  />
                </div>

                <div>
                  <label htmlFor="producto" className="mb-1.5 block text-sm font-medium text-pan-carbon">
                    Producto
                  </label>
                  <SelectorProducto
                    id="producto"
                    productos={productos}
                    valor={idProducto}
                    onChange={setIdProducto}
                    cargando={cargandoProductos}
                  />
                  {errorCatalogo && <p className="mt-1.5 text-xs text-red-700">{errorCatalogo}</p>}
                  {productoSeleccionado && (
                    <p className="mt-1.5 text-xs text-pan-carbon-suave">
                      {esPaquete
                        ? "Cada paquete trae 12 panes de hamburguesa."
                        : `Pedido mínimo: ${CANTIDAD_MINIMA_UNIDAD} panes.`}
                    </p>
                  )}
                </div>

                {mostrarCamposRecojo && horarios && (
                  <div>
                    <label className="mb-1.5 block text-sm font-medium text-pan-carbon">Recojo</label>
                    <div className="grid grid-cols-2 gap-3">
                      <SelectorFecha
                        ref={selectorFechaRef}
                        id="fecha-recojo"
                        valor={fechaRecojo}
                        onChange={setFechaRecojo}
                        minimo={new Date()}
                        aviso={avisoFechaPrimero ? "Primero elige la fecha, después podrás elegir la hora." : undefined}
                      />
                      <SelectorHora
                        ref={selectorHoraRef}
                        id="hora-recojo"
                        valor={horaRecojo}
                        onChange={setHoraRecojo}
                        minimoHoy={minimoHoraHoy}
                        puedeAbrir={!!fechaRecojo}
                        onIntentoBloqueado={alIntentarAbrirHoraSinFecha}
                      />
                    </div>
                    <p className="mt-1.5 text-xs text-pan-carbon-suave">
                      Pedidos hasta las {formatearHora12(horarios.horaLimitePedido)} se recogen hoy mismo
                      desde las {formatearHora12(horarios.horaRecojoMismoDia)}. Después de esa hora, el
                      recojo pasa para el día siguiente desde las{" "}
                      {formatearHora12(horarios.horaRecojoDiaSiguiente)}.
                    </p>
                    <AnimatePresence>
                      {fueraDeVentanaActual && (
                        <motion.div
                          initial={{ opacity: 0, y: -4, height: 0 }}
                          animate={{ opacity: 1, y: 0, height: "auto" }}
                          exit={{ opacity: 0, y: -4, height: 0 }}
                          transition={{ duration: 0.2, ease: EASE_PREMIUM }}
                          className="mt-2 flex items-start gap-2.5 overflow-hidden rounded-xl border border-amber-300 bg-amber-50 px-4 py-3"
                        >
                          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-amber-600" />
                          <p className="text-xs font-medium text-amber-800">
                            Ese horario ya cerró para recojo. Igual registramos tu pedido y te
                            confirmamos por WhatsApp, al número que dejes, si tenemos stock disponible
                            para separarlo.
                          </p>
                        </motion.div>
                      )}
                    </AnimatePresence>
                  </div>
                )}

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
                    className="w-full rounded-xl border border-pan-borde bg-pan-crema px-4 py-3 text-pan-carbon outline-none focus:border-pan-terracota"
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
                    placeholder="Ej: sin sésamo, o cualquier indicación"
                    className="w-full resize-none rounded-xl border border-pan-borde bg-pan-crema px-4 py-3 text-pan-carbon outline-none focus:border-pan-terracota"
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
      </div>
    </section>
  );
}
