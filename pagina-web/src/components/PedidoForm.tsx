import { useCallback, useEffect, useRef, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import {
  AlertTriangle,
  CalendarClock,
  CheckCircle2,
  Loader2,
  RotateCw,
  ShoppingBag,
  UserRound,
  WifiOff,
  Wheat,
} from "lucide-react";
import { PRODUCTOS } from "../data/config";
import {
  ApiError,
  crearPedidoPublico,
  obtenerCatalogoPublico,
  verificarDocumentoPublico,
  type HorariosPanaderia,
  type PedidoPublicoResultado,
  type ProductoPublico,
} from "../services/api";
import {
  esMuyProntoHoy,
  esMuyTardeHoy,
  estaFueraDeVentana,
  formatearHora12,
  franjaAjustada,
  fueraDeHorarioAtencion,
  hayVentanaHoy,
  horaMinimaHoy,
  hoyISO,
} from "../utils/horariosPan";
import { EASE_PREMIUM, VIEWPORT_REVEAL } from "../utils/animacion";
import { EncabezadoSeccion } from "./EncabezadoSeccion";
import { SelectorFecha, type SelectorFechaHandle, formatearFechaBonita } from "./SelectorFecha";
import { SelectorHora, type SelectorHoraHandle } from "./SelectorHora";
import { SelectorProducto } from "./SelectorProducto";

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
  // null = todavía no se completó/verificó; true/false = resultado de la
  // última verificación contra RENIEC/SUNAT (ver el efecto más abajo).
  const [documentoValido, setDocumentoValido] = useState<boolean | null>(null);
  const [verificandoDocumento, setVerificandoDocumento] = useState(false);
  const [avisoDocumento, setAvisoDocumento] = useState<string | null>(null);
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
  const tituloExitoRef = useRef<HTMLHeadingElement>(null);

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

  // Una sola función para traer el catálogo, reusada por la carga inicial,
  // por el sondeo periódico y por el botón "Reintentar" del estado de
  // error — antes la carga inicial no tenía forma de repetirse sin recargar
  // la página entera.
  const cargarCatalogo = useCallback(async (esReintento: boolean) => {
    if (esReintento) {
      setCargandoProductos(true);
      setErrorCatalogo(null);
    }
    try {
      const { productos: lista, horarios: horariosCatalogo } = await obtenerCatalogoPublico();
      // Solo se ofrecen los panes que ya tienen foto y están en el menú
      // de arriba (ver PRODUCTOS en data/config.ts) — el resto sigue
      // existiendo en el sistema, pero todavía no se vende desde acá.
      const disponibles = lista.filter((p) => NOMBRES_DISPONIBLES.has(p.nombre));
      setProductos(disponibles);
      setHorarios(horariosCatalogo);
      setErrorCatalogo(null);
      // El producto arranca sin elegir a propósito — el cliente tiene que
      // elegir uno de forma activa, no se preselecciona el primero.
    } catch {
      setErrorCatalogo(
        "No pudimos cargar el catálogo porque el servidor puede estar despertando. Intenta de nuevo en un momento.",
      );
    } finally {
      setCargandoProductos(false);
    }
  }, []);

  useEffect(() => {
    void cargarCatalogo(false);
  }, [cargarCatalogo]);

  // Los horarios (y sobre todo los 2 interruptores de franja) pueden
  // cambiar en cualquier momento desde la app — sin este sondeo, alguien
  // que ya tenía la página abierta seguía viendo el horario viejo hasta
  // que recargaba. Se detiene una vez que el pedido ya se envió (no hace
  // falta seguir refrescando sobre la pantalla de éxito). Silencioso: un
  // refresco que falla (red, servidor despertando) simplemente se
  // reintenta en el próximo ciclo, sin tocar el horario ya cargado.
  useEffect(() => {
    if (resultado) return;
    const id = window.setInterval(() => {
      obtenerCatalogoPublico()
        .then(({ productos: lista, horarios: horariosCatalogo }) => {
          const disponibles = lista.filter((p) => NOMBRES_DISPONIBLES.has(p.nombre));
          setProductos(disponibles);
          setHorarios(horariosCatalogo);
          setErrorCatalogo(null);
        })
        .catch(() => {});
    }, 30000);
    return () => window.clearInterval(id);
  }, [resultado]);

  // Verificación real contra RENIEC/SUNAT apenas el documento llega al
  // largo esperado (8 dígitos DNI, 11 RUC) — así el cliente se entera de
  // entrada si escribió mal el número, en vez de descubrirlo recién al
  // enviar todo el formulario. Si borra un dígito o cambia de pestaña
  // DNI/RUC, el resultado anterior ya no aplica y vuelve a quedar sin
  // verificar hasta completar el nuevo número.
  useEffect(() => {
    const largoEsperado = tipoDocumento === "DNI" ? 8 : 11;
    if (numeroDocumento.length !== largoEsperado) {
      setDocumentoValido(null);
      setAvisoDocumento(null);
      return;
    }
    let cancelado = false;
    setVerificandoDocumento(true);
    setAvisoDocumento(null);
    verificarDocumentoPublico(numeroDocumento)
      .then((resultado) => {
        if (cancelado) return;
        setDocumentoValido(resultado.existe);
        if (!resultado.existe) {
          setAvisoDocumento(
            resultado.mensaje ?? (tipoDocumento === "DNI" ? "DNI no encontrado." : "RUC no encontrado."),
          );
        }
      })
      .catch(() => {
        if (cancelado) return;
        setDocumentoValido(null);
        setAvisoDocumento("No pudimos verificar el documento. Intenta de nuevo en un momento.");
      })
      .finally(() => {
        if (!cancelado) setVerificandoDocumento(false);
      });
    return () => {
      cancelado = true;
    };
  }, [numeroDocumento, tipoDocumento]);

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
  // Segundo piso duro: el negocio ya cerró para recoger hoy después de
  // esta hora (fija, no depende del reloj como el mínimo de arriba).
  const maximoHoraHoy = horarios && esRecojoHoy ? horarios.horaTopeRecojo : undefined;

  // Piso/techo que rige CUALQUIER fecha (no solo hoy): el rango efectivo
  // según qué franjas de recojo (mañana 4am / tarde 3pm) están activas
  // ahora mismo — si el dueño apagó una por falta de stock, el rango se
  // achica a la otra. Si apagó las dos, "23:59"-"00:00" es un rango
  // invertido a propósito: el mismo mecanismo que ya cierra el selector
  // cuando el piso supera el techo (ver SelectorHora) deja todo
  // deshabilitado sin necesitar un caso especial aparte.
  const franja = horarios ? franjaAjustada(horarios) : null;
  const minimoHoraSiempre = franja?.piso ?? "23:59";
  const maximoHoraSiempre = franja?.tope ?? "00:00";

  // Una vez que ni con la tolerancia mínima alcanza a caber antes del
  // tope de recojo (ej. tope 10pm, tolerancia 30 min: desde las 9:30pm en
  // adelante), hoy deja de ofrecerse como fecha — el calendario arranca
  // directo en mañana, igual que si ya hubiera pasado la medianoche.
  const hoyDisponible = !horarios || hayVentanaHoy(horarios, ahora);
  const minimoFechaRecojo = hoyDisponible
    ? ahora
    : (() => {
        const manana = new Date(ahora);
        manana.setDate(manana.getDate() + 1);
        return manana;
      })();

  // Al cambiar de producto, la cantidad y el recojo se limpian — quedan
  // vacíos con un placeholder que ya indica qué elegir (ver más abajo), en
  // vez de arrastrar un valor que valía para el pan anterior.
  useEffect(() => {
    setCantidad("");
    setFechaRecojo("");
    setHoraRecojo("");
  }, [idProducto]);

  // Un mensaje de error queda pegado en pantalla si el cliente corrige el
  // campo que lo causó pero nunca vuelve a presionar "Enviar pedido" —
  // apenas toca cualquier campo, el error de la vez anterior se descarta
  // para no confundirlo con uno nuevo.
  useEffect(() => {
    setError(null);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tipoDocumento, numeroDocumento, telefono, idProducto, cantidad, notas, fechaRecojo, horaRecojo]);

  // Si el cliente ya había elegido una hora y el reloj avanza lo
  // suficiente como para que ese horario ya no respete los minutos de
  // tolerancia, en vez de borrarla (y dejarlo con el campo vacío otra
  // vez) se adelanta justo lo necesario para seguir siendo válida — así
  // nunca desaparece la hora que ya había elegido, solo se corrige. Pero
  // si ya no queda ninguna hora válida hoy (la tolerancia empujó más allá
  // del tope de recojo), ahí sí se limpian fecha y hora: no hay a qué
  // horario "avanzar", el cliente tiene que elegir un día distinto.
  useEffect(() => {
    if (!horarios || !fechaRecojo || fechaRecojo !== hoyISO(ahora)) return;
    // Aunque todavía no haya una hora confirmada (el cliente sigue
    // eligiendo dentro del selector), si la ventana de hoy ya se cerró
    // por completo no tiene sentido dejar "hoy" marcado como fecha — se
    // limpia para que el selector de fecha vuelva a arrancar en mañana.
    if (!hayVentanaHoy(horarios, ahora)) {
      setFechaRecojo("");
      setHoraRecojo("");
      return;
    }
    if (!horaRecojo) return;
    if (esMuyTardeHoy(fechaRecojo, horaRecojo, horarios, ahora)) {
      setFechaRecojo("");
      setHoraRecojo("");
      return;
    }
    if (esMuyProntoHoy(fechaRecojo, horaRecojo, horarios, ahora)) {
      setHoraRecojo(horaMinimaHoy(horarios, ahora));
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [fechaRecojo, horaRecojo, horarios, ahora]);

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
  // gesto puntual, no una animación que se repite sola sin parar. Además,
  // el foco salta al título de la confirmación: quien navega con teclado o
  // lector de pantalla necesita que se le anuncie que el formulario ya no
  // está y qué lo reemplazó.
  useEffect(() => {
    if (!resultado) return;
    setMascotaAgitada(true);
    const idFoco = window.setTimeout(() => tituloExitoRef.current?.focus(), 250);
    const id = window.setTimeout(() => setMascotaAgitada(false), 1400);
    return () => {
      window.clearTimeout(id);
      window.clearTimeout(idFoco);
    };
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
    if (verificandoDocumento) {
      setError("Espera un momento, estamos verificando tu documento.");
      return;
    }
    if (documentoValido !== true) {
      setError(
        avisoDocumento ?? (tipoDocumento === "DNI" ? "DNI no encontrado." : "RUC no encontrado."),
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
      if (horarios && fueraDeHorarioAtencion(horaRecojo, horarios)) {
        const franjaActual = franjaAjustada(horarios);
        setError(
          franjaActual
            ? `Atendemos de ${formatearHora12(franjaActual.piso)} a ${formatearHora12(franjaActual.tope)}. Elige una hora dentro de ese horario.`
            : "Por ahora no estamos recibiendo pedidos nuevos. Intenta de nuevo más tarde.",
        );
        return;
      }
      if (horarios && esMuyProntoHoy(fechaRecojo, horaRecojo, horarios)) {
        setError(`Para pedidos de hoy necesitamos al menos ${horarios.minutosTolerancia} minutos de anticipación.`);
        return;
      }
      if (horarios && esMuyTardeHoy(fechaRecojo, horaRecojo, horarios)) {
        setError(
          `Ya no se puede recoger hoy después de las ${formatearHora12(horarios.horaTopeRecojo)}. Elige otro horario.`,
        );
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

  // Cada paso se marca como resuelto en cuanto sus campos están completos.
  // No bloquea nada (el formulario sigue siendo una sola pantalla): sirve
  // para que el cliente vea de un vistazo qué le falta antes de enviar.
  const paso1Listo = documentoValido === true && telefono.trim().length === 9;
  const paso2Listo =
    idProducto !== "" && cantidadNum > 0 && (esPaquete || cantidadNum >= CANTIDAD_MINIMA_UNIDAD);
  const paso3Listo = !mostrarCamposRecojo || Boolean(fechaRecojo && horaRecojo);

  return (
    <section id="pedido" className="px-6 py-24 sm:py-32">
      <div className="mx-auto max-w-xl">
        <motion.div
          initial={{ opacity: 0 }}
          whileInView={{ opacity: 1 }}
          viewport={VIEWPORT_REVEAL}
          onViewportEnter={() =>
            window.setTimeout(() => mostrarMensajeMascota("Realiza tu pedido aquí 👇", 4000), 700)
          }
          transition={{ duration: 0.4 }}
        >
          <EncabezadoSeccion
            etiqueta="Pedidos"
            icono={ShoppingBag}
            titulo="Haz tu"
            tituloDestacado="pedido"
            descripcion="Déjanos tus datos y te llamamos para confirmarlo. No necesitas crear ninguna cuenta ni contraseña."
          />
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
            className="absolute -top-14 right-6 z-0 cursor-pointer rounded-2xl sm:-top-20 sm:right-10"
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
                transition={{ duration: 0.4, ease: EASE_PREMIUM }}
                className="py-6 text-center"
              >
                <motion.div
                  initial={{ scale: 0 }}
                  animate={{ scale: 1 }}
                  transition={{ type: "spring", stiffness: 260, damping: 15, delay: 0.1 }}
                  className="relative mx-auto h-14 w-14"
                >
                  {/* Onda que se expande una sola vez detrás del check —
                      el "clic" visual que confirma que algo se completó. */}
                  <motion.span
                    initial={{ scale: 0.6, opacity: 0.5 }}
                    animate={{ scale: 2.1, opacity: 0 }}
                    transition={{ duration: 1, ease: "easeOut", delay: 0.15 }}
                    className="absolute inset-0 rounded-full bg-emerald-500/30"
                  />
                  <CheckCircle2 className="relative h-14 w-14 text-emerald-600" strokeWidth={1.6} />
                </motion.div>
                <h3
                  ref={tituloExitoRef}
                  tabIndex={-1}
                  className="mt-4 font-[family-name:var(--font-display-panaderia)] text-2xl font-semibold text-pan-carbon outline-none"
                >
                  Pedido #{resultado.numeroPedidoDia} recibido
                </h3>
                <p className="mt-2 text-pan-carbon-suave">{resultado.mensaje}</p>
                <p className="mt-3 text-lg font-semibold text-pan-terracota">
                  Total: S/ {resultado.total.toFixed(2)}
                </p>

                <div className="mx-auto mt-5 max-w-sm space-y-2.5 rounded-2xl border border-pan-borde/25 bg-pan-crema px-5 py-4 text-left text-sm">
                  <FilaDetallePedido etiqueta="Producto" valor={productoSeleccionado?.nombre ?? "—"} />
                  <FilaDetallePedido
                    etiqueta={esPaquete ? "Paquetes" : "Cantidad"}
                    valor={cantidad || "—"}
                  />
                  <FilaDetallePedido etiqueta="Documento" valor={`${tipoDocumento} ${numeroDocumento}`} />
                  <FilaDetallePedido etiqueta="Celular" valor={telefono} />
                  {!esPaquete && fechaRecojo && horaRecojo && (
                    <FilaDetallePedido
                      etiqueta="Recojo"
                      valor={`${formatearFechaBonita(fechaRecojo)}, ${formatearHora12(horaRecojo)}`}
                    />
                  )}
                  {notas.trim() && <FilaDetallePedido etiqueta="Notas" valor={notas.trim()} />}
                </div>

                {fueraDeVentanaAlEnviar && (
                  <div className="mx-auto mt-4 flex max-w-sm items-start gap-2.5 rounded-xl border border-amber-300 bg-amber-50 px-4 py-3 text-left">
                    <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-amber-600" strokeWidth={1.75} />
                    <p className="text-xs font-medium text-amber-800">
                      Como el horario elegido ya cerró, te confirmaremos por WhatsApp al número que dejaste
                      si tenemos stock disponible para separar tu pedido.
                    </p>
                  </div>
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
                className="space-y-8"
              >
                <fieldset className="space-y-5 border-0 p-0">
                  <PasoFormulario numero={1} titulo="Tus datos" icono={UserRound} listo={paso1Listo} />

                  <div>
                    <label htmlFor="documento" className="mb-1.5 block text-sm font-medium text-pan-carbon">
                      Documento
                    </label>
                    {/* El indicador activo se DESLIZA entre DNI y RUC
                        (layoutId) en vez de saltar de un botón al otro —
                        el mismo gesto que ya usa el buscador de pedidos,
                        para que los dos selectores se sientan iguales. */}
                    <div
                      role="radiogroup"
                      aria-label="Tipo de documento"
                      className="mb-2 inline-flex rounded-full border border-pan-borde bg-pan-crema p-1"
                    >
                      {(["DNI", "RUC"] as const).map((tipo) => (
                        <button
                          key={tipo}
                          type="button"
                          role="radio"
                          aria-checked={tipoDocumento === tipo}
                          onClick={() => {
                            setTipoDocumento(tipo);
                            setNumeroDocumento("");
                          }}
                          className={`relative rounded-full px-5 py-1.5 text-sm font-semibold transition-colors ${
                            tipoDocumento === tipo
                              ? "text-pan-crema"
                              : "text-pan-carbon-suave hover:text-pan-carbon"
                          }`}
                        >
                          {tipoDocumento === tipo && (
                            <motion.span
                              layoutId="pedido-tipo-documento-activo"
                              className="absolute inset-0 rounded-full bg-pan-terracota"
                              transition={{ duration: 0.25, ease: EASE_PREMIUM }}
                            />
                          )}
                          <span className="relative">{tipo}</span>
                        </button>
                      ))}
                    </div>
                    <div className="relative">
                      <input
                        id="documento"
                        inputMode="numeric"
                        autoComplete="off"
                        maxLength={tipoDocumento === "DNI" ? 8 : 11}
                        value={numeroDocumento}
                        onChange={(e) => {
                          const limpio = e.target.value.replace(/\D/g, "");
                          setNumeroDocumento(limpio);
                          // Al completar el largo esperado, se quita el foco
                          // de una vez: no hace falta que el cliente toque
                          // otro campo para que arranque la verificación.
                          if (limpio.length === (tipoDocumento === "DNI" ? 8 : 11)) e.target.blur();
                        }}
                        placeholder={tipoDocumento === "DNI" ? "Ingresa tu DNI" : "Ingresa tu RUC"}
                        required
                        aria-describedby="estado-documento"
                        aria-invalid={documentoValido === false}
                        className="campo-pan pr-11"
                      />
                      {/* El estado de la verificación vive DENTRO del campo:
                          es donde el cliente ya está mirando, y no empuja el
                          resto del formulario hacia abajo al aparecer. */}
                      <span className="pointer-events-none absolute inset-y-0 right-3.5 flex items-center">
                        <AnimatePresence mode="wait" initial={false}>
                          {verificandoDocumento ? (
                            <motion.span
                              key="verificando"
                              initial={{ opacity: 0, scale: 0.7 }}
                              animate={{ opacity: 1, scale: 1 }}
                              exit={{ opacity: 0, scale: 0.7 }}
                              transition={{ duration: 0.15 }}
                            >
                              <Loader2 className="h-4 w-4 animate-spin text-pan-bronce-oscuro" />
                            </motion.span>
                          ) : documentoValido === true ? (
                            <motion.span
                              key="valido"
                              initial={{ opacity: 0, scale: 0.5 }}
                              animate={{ opacity: 1, scale: 1 }}
                              exit={{ opacity: 0, scale: 0.5 }}
                              transition={{ type: "spring", stiffness: 400, damping: 18 }}
                            >
                              <CheckCircle2 className="h-4 w-4 text-emerald-600" />
                            </motion.span>
                          ) : null}
                        </AnimatePresence>
                      </span>
                    </div>
                    <div id="estado-documento" aria-live="polite" className="min-h-[1.1rem]">
                      {verificandoDocumento && (
                        <p className="mt-1.5 text-xs text-pan-carbon-suave">Verificando documento…</p>
                      )}
                      {!verificandoDocumento && avisoDocumento && (
                        <p className="mt-1.5 text-xs font-medium text-red-700">{avisoDocumento}</p>
                      )}
                      {!verificandoDocumento && documentoValido === true && (
                        <p className="mt-1.5 text-xs font-medium text-emerald-700">Documento verificado.</p>
                      )}
                    </div>
                  </div>

                  <div>
                    <label htmlFor="telefono" className="mb-1.5 block text-sm font-medium text-pan-carbon">
                      Celular
                    </label>
                    <input
                      id="telefono"
                      inputMode="numeric"
                      autoComplete="tel-national"
                      maxLength={9}
                      value={telefono}
                      onChange={(e) => setTelefono(e.target.value.replace(/\D/g, ""))}
                      placeholder="Ingresa tu número de celular"
                      required
                      className="campo-pan"
                    />
                  </div>
                </fieldset>

                <fieldset className="space-y-5 border-0 p-0">
                  <PasoFormulario numero={2} titulo="Tu pedido" icono={Wheat} listo={paso2Listo} />

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
                    {/* Estado de error del catálogo con salida: antes era
                        una línea de texto rojo sin nada que hacer más que
                        recargar la página a mano. */}
                    <AnimatePresence>
                      {errorCatalogo && !cargandoProductos && (
                        <motion.div
                          initial={{ opacity: 0, height: 0 }}
                          animate={{ opacity: 1, height: "auto" }}
                          exit={{ opacity: 0, height: 0 }}
                          transition={{ duration: 0.25, ease: EASE_PREMIUM }}
                          className="overflow-hidden"
                        >
                          <div className="mt-2 flex items-start gap-2.5 rounded-xl border border-pan-borde/50 bg-pan-crema px-4 py-3">
                            <WifiOff className="mt-0.5 h-4 w-4 shrink-0 text-pan-terracota" strokeWidth={1.75} />
                            <div className="min-w-0 flex-1">
                              <p className="text-xs leading-relaxed text-pan-carbon-suave">{errorCatalogo}</p>
                              <button
                                type="button"
                                onClick={() => void cargarCatalogo(true)}
                                className="mt-2 inline-flex items-center gap-1.5 rounded text-xs font-semibold text-pan-terracota transition-colors hover:text-pan-terracota-profundo"
                              >
                                <RotateCw className="h-3.5 w-3.5" />
                                Reintentar
                              </button>
                            </div>
                          </div>
                        </motion.div>
                      )}
                    </AnimatePresence>
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
                      className="campo-pan"
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
                      className="campo-pan resize-none"
                    />
                  </div>
                </fieldset>

                {/* El bloque de recojo entra y sale animado, y va al final
                    del formulario: al aparecer/desaparecer en el medio (que
                    es donde estaba antes) empujaba de golpe los campos de
                    abajo cada vez que se cambiaba de pan. */}
                <AnimatePresence initial={false}>
                  {mostrarCamposRecojo && horarios && (
                    <motion.fieldset
                      initial={{ opacity: 0, height: 0 }}
                      animate={{ opacity: 1, height: "auto" }}
                      exit={{ opacity: 0, height: 0 }}
                      transition={{ duration: 0.35, ease: EASE_PREMIUM }}
                      className="overflow-hidden border-0 p-0"
                    >
                      <div className="space-y-5">
                        <PasoFormulario numero={3} titulo="Recojo" icono={CalendarClock} listo={paso3Listo} />

                        <div>
                          <div className="grid grid-cols-2 gap-3">
                            <SelectorFecha
                              ref={selectorFechaRef}
                              id="fecha-recojo"
                              valor={fechaRecojo}
                              onChange={setFechaRecojo}
                              minimo={minimoFechaRecojo}
                              aviso={avisoFechaPrimero ? "Primero elige la fecha, después podrás elegir la hora." : undefined}
                            />
                            <SelectorHora
                              ref={selectorHoraRef}
                              id="hora-recojo"
                              valor={horaRecojo}
                              onChange={setHoraRecojo}
                              minimoHoy={minimoHoraHoy}
                              maximoHoy={maximoHoraHoy}
                              minimoSiempre={minimoHoraSiempre}
                              maximoSiempre={maximoHoraSiempre}
                              puedeAbrir={!!fechaRecojo}
                              onIntentoBloqueado={alIntentarAbrirHoraSinFecha}
                            />
                          </div>
                          <p className="mt-2 text-xs leading-relaxed text-pan-carbon-suave">
                            {franja
                              ? `Por ahora, el recojo está disponible de ${formatearHora12(franja.piso)} a ${formatearHora12(franja.tope)}. `
                              : "Por ahora no estamos recibiendo pedidos nuevos. "}
                            Pedidos hasta las {formatearHora12(horarios.horaLimitePedido)} se recogen hoy mismo
                            desde las {formatearHora12(horarios.horaRecojoMismoDia)}. Después de esa hora, el
                            recojo pasa para el día siguiente desde las{" "}
                            {formatearHora12(horarios.horaRecojoDiaSiguiente)}, o desde las{" "}
                            {formatearHora12(horarios.horaRecojoMismoDia)} si el pedido llega pasadas las{" "}
                            {formatearHora12(horarios.horaInicioPedidoTarde)}.
                          </p>
                          <AnimatePresence>
                            {fueraDeVentanaActual && (
                              <motion.div
                                initial={{ opacity: 0, y: -4, height: 0 }}
                                animate={{ opacity: 1, y: 0, height: "auto" }}
                                exit={{ opacity: 0, y: -4, height: 0 }}
                                transition={{ duration: 0.25, ease: EASE_PREMIUM }}
                                className="mt-2 flex items-start gap-2.5 overflow-hidden rounded-xl border border-amber-300 bg-amber-50 px-4 py-3"
                              >
                                <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-amber-600" strokeWidth={1.75} />
                                <p className="text-xs font-medium text-amber-800">
                                  Ese horario ya cerró para recojo. Igual registramos tu pedido y te
                                  confirmamos por WhatsApp, al número que dejes, si tenemos stock disponible
                                  para separarlo.
                                </p>
                              </motion.div>
                            )}
                          </AnimatePresence>
                        </div>
                      </div>
                    </motion.fieldset>
                  )}
                </AnimatePresence>

                <div className="space-y-4">
                  <AnimatePresence initial={false}>
                    {productoSeleccionado && cantidadNum > 0 && (
                      <motion.div
                        key="total"
                        initial={{ opacity: 0, scale: 0.96, height: 0 }}
                        animate={{ opacity: 1, scale: 1, height: "auto" }}
                        exit={{ opacity: 0, scale: 0.96, height: 0 }}
                        transition={{ duration: 0.28, ease: EASE_PREMIUM }}
                        className="flex items-center justify-between rounded-xl border border-pan-terracota/15 bg-pan-terracota-suave/40 px-4 py-3"
                      >
                        <span className="text-sm font-medium text-pan-carbon">Total estimado</span>
                        {/* La cifra se reanima cada vez que cambia (`key`),
                            así el cliente nota que se recalculó al escribir
                            otra cantidad. */}
                        <motion.span
                          key={total}
                          initial={{ opacity: 0, y: -6 }}
                          animate={{ opacity: 1, y: 0 }}
                          transition={{ duration: 0.25, ease: EASE_PREMIUM }}
                          className="text-lg font-semibold text-pan-terracota"
                        >
                          S/ {total.toFixed(2)}
                        </motion.span>
                      </motion.div>
                    )}
                  </AnimatePresence>

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
                </div>
              </motion.form>
            )}
          </AnimatePresence>
          </motion.div>
        </div>
      </div>
    </section>
  );
}

/** Cabecera de un tramo del formulario: número, nombre y una marca que se
 * enciende cuando ese tramo ya quedó completo. El formulario sigue siendo
 * una sola pantalla (nada de pasos que obliguen a avanzar y retroceder),
 * pero ahora se lee como tres bloques con principio y fin en vez de una
 * lista larga de campos sueltos. */
function PasoFormulario({
  numero,
  titulo,
  icono: Icono,
  listo,
}: {
  numero: number;
  titulo: string;
  icono: React.ComponentType<{ className?: string; strokeWidth?: number }>;
  listo: boolean;
}) {
  return (
    <div className="flex items-center gap-3">
      <span
        className={`relative flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-xs font-bold transition-colors duration-400 ${
          listo ? "bg-emerald-600 text-white" : "bg-pan-terracota-suave/70 text-pan-terracota-profundo"
        }`}
      >
        <AnimatePresence mode="wait" initial={false}>
          {listo ? (
            <motion.span
              key="listo"
              initial={{ scale: 0, rotate: -45 }}
              animate={{ scale: 1, rotate: 0 }}
              exit={{ scale: 0 }}
              transition={{ type: "spring", stiffness: 420, damping: 20 }}
            >
              <CheckCircle2 className="h-4 w-4" strokeWidth={2.4} />
            </motion.span>
          ) : (
            <motion.span key="numero" initial={{ scale: 0.6 }} animate={{ scale: 1 }} exit={{ scale: 0 }}>
              {numero}
            </motion.span>
          )}
        </AnimatePresence>
      </span>
      <span className="flex items-center gap-2 text-sm font-semibold tracking-wide text-pan-carbon">
        <Icono className="h-4 w-4 text-pan-bronce-oscuro" strokeWidth={1.75} />
        {titulo}
      </span>
      <span aria-hidden="true" className="h-px flex-1 bg-gradient-to-r from-pan-borde/40 to-transparent" />
    </div>
  );
}

/** Una fila del resumen de "pedido recibido" — mismo formato etiqueta +
 * valor para documento, producto, recojo, etc. */
function FilaDetallePedido({ etiqueta, valor }: { etiqueta: string; valor: string }) {
  return (
    <div className="flex items-start justify-between gap-4">
      <span className="text-pan-carbon-suave">{etiqueta}</span>
      <span className="text-right font-medium text-pan-carbon">{valor}</span>
    </div>
  );
}
