import { Suspense, lazy, useEffect, useRef, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import {
  AlertTriangle,
  CalendarClock,
  CheckCircle2,
  Loader2,
  Pencil,
  RotateCw,
  ShieldCheck,
  ShoppingBag,
  UserRound,
  WifiOff,
  Wheat,
} from "lucide-react";
import { CANTIDAD_MINIMA_UNIDAD } from "../data/config";
import { ApiError, crearPedidoPublico, type PedidoPublicoResultado } from "../services/api";
import type { CatalogoPublico } from "../hooks/useCatalogoPublico";
import {
  LONGITUD_DOCUMENTO,
  textoNoEncontrado,
  useVerificacionDocumento,
  type TipoDocumento,
} from "../hooks/useVerificacionDocumento";
import {
  esMuyProntoHoy,
  esMuyTardeHoy,
  estaFueraDeVentana,
  formatearHora12,
  franjaEfectiva,
  fueraDeHorarioAtencion,
  hayVentanaHoy,
  horaMinimaHoy,
  hoyISO,
} from "../utils/horariosPan";
import { EASE_PREMIUM, VIEWPORT_REVEAL } from "../utils/animacion";
import { EncabezadoSeccion } from "./EncabezadoSeccion";
import { MascotaPanadero } from "./MascotaPanadero";
import { ResumenPedidoExito, type DetallePedidoEnviado } from "./ResumenPedidoExito";
import type { SelectorFechaHandle } from "./SelectorFecha";
import type { SelectorHoraHandle } from "./SelectorHora";
import { SelectorProducto } from "./SelectorProducto";
import { SelectorTipoDocumento } from "./SelectorTipoDocumento";

// El calendario y la rueda de horas solo existen para el pan vendido por
// unidad, y recién después de que el visitante eligió un pan — nunca al
// abrir la página, y nunca en un pedido de pan de hamburguesa (que se
// vende por paquete y no lleva hora de recojo). Entre los dos son el bloque
// de código más grande del formulario, así que viajan en su propio archivo
// y se descargan en el momento en que hacen falta.
const SelectorFecha = lazy(() =>
  import("./SelectorFecha").then((m) => ({ default: m.SelectorFecha })),
);
const SelectorHora = lazy(() => import("./SelectorHora").then((m) => ({ default: m.SelectorHora })));

/** Misma regla que EMAIL_REGEX en el backend (middlewares/validators.js):
 * un chequeo de forma, no de existencia — evita el viaje al servidor por un
 * correo obviamente mal escrito, pero la validación que manda es la de allá. */
const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

interface PedidoFormProps {
  /** El catálogo lo trae App y lo comparte con el menú de arriba: el precio
   * que se muestra en la tarjeta y el que se cobra acá salen del mismo
   * fetch, así que no pueden separarse. */
  catalogo: CatalogoPublico;
  /** Se avisa hacia arriba cuando el pedido ya entró, para que el sondeo
   * del catálogo se detenga: sobre la pantalla de confirmación no hay nada
   * que refrescar. */
  onPedidoEnviado: (enviado: boolean) => void;
  /** El id del pan que el visitante tocó en "Pedir este pan" desde el menú
   * de arriba, o null si llegó acá por su cuenta (scroll, link del navbar).
   * Vive en Landing porque quien lo dispara (Menu) es hermano de este
   * formulario, no un ancestro ni un descendiente. */
  productoElegidoEnMenu: number | null;
}

export function PedidoForm({ catalogo, onPedidoEnviado, productoElegidoEnMenu }: PedidoFormProps) {
  const { productos, horarios, cargando: cargandoProductos, error: errorCatalogo, recargar } = catalogo;

  // ORDEN DEL FORMULARIO: primero el pedido (pan, cantidad, recojo) y
  // recién al final los datos personales. El documento con verificación
  // contra RENIEC/SUNAT es el paso más incómodo de todos y estaba PRIMERO:
  // había que entregar el DNI antes de haber visto un solo precio ni el
  // total. Ahora se pide cuando el visitante ya sabe qué va a pedir y
  // cuánto le cuesta. La verificación en sí no cambió ni se relajó: sigue
  // bloqueando el envío igual que antes (ver `enviar`).
  const [idProducto, setIdProducto] = useState<number | "">("");
  const [cantidad, setCantidad] = useState("");
  const [notas, setNotas] = useState("");
  const [fechaRecojo, setFechaRecojo] = useState("");
  const [horaRecojo, setHoraRecojo] = useState("");
  const [avisoFechaPrimero, setAvisoFechaPrimero] = useState(false);
  const selectorFechaRef = useRef<SelectorFechaHandle>(null);
  const selectorHoraRef = useRef<SelectorHoraHandle>(null);
  const abrirHoraLuegoDeFechaRef = useRef(false);

  const [tipoDocumento, setTipoDocumento] = useState<TipoDocumento>("DNI");
  const [numeroDocumento, setNumeroDocumento] = useState("");
  const [telefono, setTelefono] = useState("");
  const [email, setEmail] = useState("");
  // Solo aplican cuando ya teníamos ese dato guardado y NO está verificado:
  // el cliente ve el valor enmascarado y, si toca "Cambiar", se le abre un
  // campo vacío para escribir uno nuevo. Nunca se le pide editar un valor a
  // medio tapar (`j***@gmail.com`), que sería imposible de completar bien.
  const [cambiandoTelefono, setCambiandoTelefono] = useState(false);
  const [cambiandoEmail, setCambiandoEmail] = useState(false);
  const {
    valido: documentoValido,
    verificando: verificandoDocumento,
    aviso: avisoDocumento,
    contacto,
  } = useVerificacionDocumento(numeroDocumento, tipoDocumento);

  // Tres estados por canal (correo y celular), según lo que el backend ya
  // tenga guardado de este documento:
  //   sin dato          -> campo normal, vacío y editable
  //   guardado sin verificar -> se muestra la máscara + "Cambiar"
  //   guardado y verificado  -> solo lectura (se cambia dentro de la app)
  // El input aparece cuando no hay nada guardado, o cuando el cliente pidió
  // cambiar un dato que todavía no estaba verificado.
  const mostrarInputTelefono = !contacto.telefono.enArchivo || (!contacto.telefono.verificado && cambiandoTelefono);
  const mostrarInputEmail = !contacto.email.enArchivo || (!contacto.email.verificado && cambiandoEmail);
  const telefonoLimpio = telefono.trim();
  const emailLimpio = email.trim();
  // Lo que de verdad viaja en el pedido: solo un valor nuevo y completo,
  // nunca la máscara. Si el cliente se quedó con el dato guardado, el campo
  // ni se manda y el backend reutiliza el que ya está en Personas.
  const enviarTelefono = mostrarInputTelefono && telefonoLimpio.length > 0;
  const enviarEmail = mostrarInputEmail && emailLimpio.length > 0;
  const telefonoResuelto = mostrarInputTelefono ? /^\d{9}$/.test(telefonoLimpio) : true;

  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [resultado, setResultado] = useState<PedidoPublicoResultado | null>(null);
  const [detalleEnviado, setDetalleEnviado] = useState<DetallePedidoEnviado | null>(null);
  const [fueraDeVentanaAlEnviar, setFueraDeVentanaAlEnviar] = useState(false);
  const [anunciarMascota, setAnunciarMascota] = useState(false);

  useEffect(() => {
    onPedidoEnviado(resultado !== null);
  }, [resultado, onPedidoEnviado]);

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

  // Rango efectivo para la fecha YA ELEGIDA (o para hoy, si todavía no se
  // eligió ninguna): los interruptores de franja (mañana 4am / tarde 3pm)
  // solo achican el rango cuando la fecha elegida es hoy — son la señal de
  // "hoy no queda stock de esa hornada", no una decisión de horario que
  // deba seguir aplicando a un pedido de mañana. Si apagó las dos y la
  // fecha elegida es hoy, "23:59"-"00:00" es un rango invertido a
  // propósito: el mismo mecanismo que ya cierra el selector cuando el piso
  // supera el techo (ver SelectorHora) deja todo deshabilitado sin
  // necesitar un caso especial aparte.
  const franja = horarios ? franjaEfectiva(fechaRecojo, horarios) : null;
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

  // El pan elegido en el menú de arriba se aplica acá apenas llega — este
  // efecto es la única vía por la que ese clic externo entra al formulario;
  // de ahí en más el visitante puede seguir cambiándolo desde el selector
  // como si lo hubiera elegido acá mismo. Si vuelve a tocar "Pedir este
  // pan" con OTRO pan, el id cambia y esto se repite; con el MISMO pan no
  // hay nada que reaplicar (ya está elegido).
  useEffect(() => {
    if (productoElegidoEnMenu != null) setIdProducto(productoElegidoEnMenu);
  }, [productoElegidoEnMenu]);

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
  }, [tipoDocumento, numeroDocumento, telefono, email, idProducto, cantidad, notas, fechaRecojo, horaRecojo]);

  // Al conocerse (o cambiar) el documento, lo que ya tenemos guardado de él
  // manda sobre lo que el cliente hubiera tecleado antes: el campo vuelve a
  // mostrarse como dato guardado, sin arrastrar un valor a medio escribir
  // del documento anterior. Si el documento nuevo no tiene nada guardado, lo
  // tecleado se respeta (no hay nada que lo reemplace).
  useEffect(() => {
    if (!contacto.telefono.enArchivo) return;
    setTelefono("");
    setCambiandoTelefono(false);
  }, [contacto.telefono.enArchivo, contacto.telefono.mascara]);

  useEffect(() => {
    if (!contacto.email.enArchivo) return;
    setEmail("");
    setCambiandoEmail(false);
  }, [contacto.email.enArchivo, contacto.email.mascara]);

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

  async function enviar(e: React.FormEvent) {
    e.preventDefault();
    setError(null);

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
    // Hora que de verdad se manda al servidor: arranca igual a la que
    // eligió el cliente, pero puede corregirse más abajo si el reloj avanzó
    // mientras completaba el resto del formulario.
    let horaRecojoFinal = horaRecojo;
    if (!esPaquete) {
      if (!fechaRecojo || !horaRecojo) {
        setError("Elige una fecha y hora de recojo.");
        return;
      }
      if (horarios && fueraDeHorarioAtencion(fechaRecojo, horaRecojo, horarios)) {
        const franjaActual = franjaEfectiva(fechaRecojo, horarios);
        setError(
          franjaActual
            ? `Atendemos de ${formatearHora12(franjaActual.piso)} a ${formatearHora12(franjaActual.tope)}. Elige una hora dentro de ese horario.`
            : "Por ahora no estamos recibiendo pedidos nuevos. Intenta de nuevo más tarde.",
        );
        return;
      }
      // El reloj vivo de arriba (cada 15s) ya adelanta la hora elegida sola
      // mientras el formulario sigue abierto, pero entre el último tick y
      // este submit pueden pasar unos segundos más (verificar el documento
      // contra RENIEC/SUNAT toma su tiempo) — suficiente para que la hora
      // elegida deje de cumplir la tolerancia justo al enviar. En vez de
      // rechazar el pedido con un error y obligar al cliente a volver a
      // elegir, se aplica la misma corrección acá, con 1 minuto extra de
      // colchón para lo que tarde en llegar la petición al servidor.
      if (horarios && esMuyProntoHoy(fechaRecojo, horaRecojoFinal, horarios)) {
        horaRecojoFinal = horaMinimaHoy(horarios, new Date(Date.now() + 60_000));
        setHoraRecojo(horaRecojoFinal);
      }
      if (horarios && esMuyTardeHoy(fechaRecojo, horaRecojoFinal, horarios)) {
        setError(
          `Ya no se puede recoger hoy después de las ${formatearHora12(horarios.horaTopeRecojo)}. Elige otro horario.`,
        );
        return;
      }
      fechaEntrega = `${fechaRecojo}T${horaRecojoFinal}`;
    }

    // La verificación del documento sigue siendo un requisito duro para
    // enviar — lo único que cambió es DÓNDE se pide, no que se pida.
    const numeroDocumentoLimpio = numeroDocumento.trim();
    if (!new RegExp(`^\\d{${LONGITUD_DOCUMENTO[tipoDocumento]}}$`).test(numeroDocumentoLimpio)) {
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
      setError(avisoDocumento ?? textoNoEncontrado(tipoDocumento));
      return;
    }
    // El celular solo se exige cuando de verdad hay un campo para
    // escribirlo: si ya lo teníamos guardado y el cliente lo dejó así, el
    // pedido ya queda contactable con ese número (lo resuelve el backend por
    // documento, sin que la web llegue a verlo completo).
    if (mostrarInputTelefono && !/^\d{9}$/.test(telefonoLimpio)) {
      setError("Ingresa un número de celular válido de 9 dígitos.");
      return;
    }
    // El correo es opcional: solo se revisa el formato si escribió algo.
    if (mostrarInputEmail && emailLimpio.length > 0 && !EMAIL_REGEX.test(emailLimpio)) {
      setError("Ingresa un correo electrónico válido.");
      return;
    }

    setEnviando(true);
    try {
      const respuesta = await crearPedidoPublico({
        documento: numeroDocumentoLimpio,
        // Ausentes = "conserva lo que ya tienes guardado". Nunca se manda la
        // máscara: el backend la rechazaría y, sobre todo, sobrescribiría un
        // dato bueno con uno lleno de asteriscos.
        ...(enviarTelefono ? { telefono: telefonoLimpio } : {}),
        ...(enviarEmail ? { email: emailLimpio } : {}),
        items: [{ idProducto: Number(idProducto), cantidad: cantidadNum }],
        notas: notas.trim() || undefined,
        fechaEntrega,
      });
      // El detalle se congela acá, con lo que realmente se envió: la
      // pantalla de confirmación no debe cambiar si después se limpian los
      // campos o si el sondeo del catálogo trae otro precio.
      setDetalleEnviado({
        producto: productoSeleccionado?.nombre ?? "—",
        cantidad,
        esPaquete,
        documento: `${tipoDocumento} ${numeroDocumento}`,
        // Si se reutilizó el celular guardado, se muestra tal como el
        // cliente lo vio en el formulario: enmascarado.
        telefono: enviarTelefono ? telefonoLimpio : (contacto.telefono.mascara ?? "—"),
        fechaRecojo,
        horaRecojo: horaRecojoFinal,
        notas: notas.trim(),
      });
      setFueraDeVentanaAlEnviar(!esPaquete && fueraDeVentanaActual);
      setResultado(respuesta);
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
    setDetalleEnviado(null);
    setFueraDeVentanaAlEnviar(false);
    setNumeroDocumento("");
    setTelefono("");
    setEmail("");
    setCambiandoTelefono(false);
    setCambiandoEmail(false);
    setCantidad("");
    setNotas("");
    setFechaRecojo("");
    setHoraRecojo("");
  }

  // Cada paso se marca como resuelto en cuanto sus campos están completos.
  // No bloquea nada (el formulario sigue siendo una sola pantalla): sirve
  // para que el cliente vea de un vistazo qué le falta antes de enviar.
  const pasoPedidoListo =
    idProducto !== "" && cantidadNum > 0 && (esPaquete || cantidadNum >= CANTIDAD_MINIMA_UNIDAD);
  const pasoRecojoListo = !mostrarCamposRecojo || Boolean(fechaRecojo && horaRecojo);
  // El correo no cuenta para marcar el paso como completo: es opcional. El
  // celular sí, salvo que ya lo tengamos guardado (ahí no hay nada que
  // escribir: el paso queda listo con solo verificar el documento).
  const pasoDatosListo = documentoValido === true && telefonoResuelto;
  // El recojo solo cuenta como paso propio cuando se muestra (pan por
  // unidad): con el pan de hamburguesa, "Tus datos" es el paso 2, no el 3.
  const numeroPasoDatos = mostrarCamposRecojo ? 3 : 2;

  return (
    <section id="pedido" className="px-6 py-24 sm:py-32">
      <div className="mx-auto max-w-xl">
        <motion.div
          initial={{ opacity: 0 }}
          whileInView={{ opacity: 1 }}
          viewport={VIEWPORT_REVEAL}
          onViewportEnter={() => setAnunciarMascota(true)}
          transition={{ duration: 0.4 }}
        >
          <EncabezadoSeccion
            etiqueta="Pedidos"
            icono={ShoppingBag}
            titulo="Haz tu"
            tituloDestacado="pedido"
            descripcion="Elige tu pan y cuándo lo recoges; los datos te los pedimos al final. No necesitas crear ninguna cuenta ni contraseña."
          />
        </motion.div>

        {/* Segundo destino de scroll de la sección, aparte de `#pedido`.
            Los botones que prometen empezar un pedido YA ("Pedir ahora" del
            navbar, "Pedir este pan" del menú) apuntan acá y no al título:
            aterrizando en `#pedido` la pantalla se llenaba con la cabecera
            de la sección y el formulario quedaba fuera de vista, así que el
            clic terminaba pidiendo un segundo scroll a mano. Los enlaces de
            navegación genéricos (hero, footer, menú del navbar) siguen
            yendo al título, que es lo que corresponde al recorrer la
            página. El `scroll-mt` compensa dos cosas a la vez: el navbar
            fijo (~60px en celular, ~68px desde sm) y todo lo que asoma POR
            ENCIMA de este div, que es lo que de verdad manda: el panadero
            (-top-24 = 96px, -top-32 = 128px desde sm) y, más arriba
            todavía, su globo de diálogo. Sin contar ese asomo la barra le
            cortaba el gorro; contando solo al panadero, le cortaba el
            globo.

            Y la entrada de scroll es de ESTE div, no de cada hijo: el
            panadero y la tarjeta aparecen juntos, en el mismo movimiento.
            Cuando cada uno traía su propio `whileInView`, sus observadores
            cruzaban el umbral en momentos distintos —el panadero está más
            arriba en la página— y se veía llegar primero al panadero, solo,
            sobre un hueco vacío. */}
        <motion.div
          id="pedido-formulario"
          initial="oculto"
          whileInView="visible"
          viewport={{ once: true, margin: "-80px" }}
          variants={{
            oculto: { opacity: 0, y: 24 },
            visible: { opacity: 1, y: 0, transition: { duration: 0.6, ease: EASE_PREMIUM } },
          }}
          className="relative mt-32 scroll-mt-52 sm:mt-36 sm:scroll-mt-60"
        >
          <MascotaPanadero anunciar={anunciarMascota} celebrando={resultado !== null} />

          <motion.div
            // El escalón mínimo de la tarjeta ya no depende del scroll: la
            // etiqueta de variante baja desde el padre, así que este retraso
            // de 0,1s es una cascada deliberada DENTRO de la misma entrada,
            // no dos entradas distintas disparadas en momentos distintos.
            variants={{
              oculto: { opacity: 0, y: 10 },
              visible: {
                opacity: 1,
                y: 0,
                transition: { duration: 0.5, ease: EASE_PREMIUM, delay: 0.1 },
              },
            }}
            className="relative z-10 rounded-3xl border border-pan-borde/50 bg-pan-crema-suave p-5 shadow-md shadow-pan-carbon/5 sm:p-8"
          >
            <AnimatePresence mode="wait">
              {resultado && detalleEnviado ? (
                <ResumenPedidoExito
                  key="exito"
                  resultado={resultado}
                  detalle={detalleEnviado}
                  fueraDeVentana={fueraDeVentanaAlEnviar}
                  onPedirDeNuevo={pedirOtroVez}
                />
              ) : (
                <motion.form
                  key="formulario"
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  onSubmit={enviar}
                  className="space-y-8"
                >
                  <fieldset className="space-y-5 border-0 p-0">
                    <PasoFormulario numero={1} titulo="Tu pedido" icono={Wheat} listo={pasoPedidoListo} />

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
                                  onClick={recargar}
                                  className="-mx-2 mt-1 inline-flex min-h-11 items-center gap-1.5 rounded px-2 text-xs font-semibold text-pan-terracota transition-colors hover:text-pan-terracota-profundo"
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
                            ? `Cada paquete trae 12 panes de hamburguesa · S/ ${productoSeleccionado.precioUnitario.toFixed(2)} el paquete.`
                            : `Pedido mínimo: ${CANTIDAD_MINIMA_UNIDAD} panes · S/ ${productoSeleccionado.precioUnitario.toFixed(2)} c/u.`}
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

                    {/* El total ya sale acá arriba, pegado a la cantidad —
                        antes vivía al lado del botón de enviar, después de
                        todos los datos personales: el visitante tenía que
                        entregar su DNI para recién enterarse de cuánto le
                        iba a costar. */}
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

                  {/* El bloque de recojo entra y sale animado: al aparecer o
                      desaparecer empuja los campos de abajo cada vez que se
                      cambia de pan, y por eso va después del pedido y no
                      intercalado entre sus campos. */}
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
                          <PasoFormulario numero={2} titulo="Recojo" icono={CalendarClock} listo={pasoRecojoListo} />

                          <div>
                            {/* Una columna en celular: repartidos en dos, cada
                                campo quedaba en 133px y una fecha ya elegida
                                ("Lun 31 de agosto") se partía en TRES
                                renglones dentro del botón. Recién con el
                                ancho de sm entran los dos en la misma fila
                                sin cortar el texto. */}
                            {/* El hueco de espera calca la rejilla real (dos
                                campos de 50px), así el alto no cambia al
                                llegar el código: este bloque entra con una
                                animación de alto, y un cambio de tamaño a
                                mitad de camino la dejaría cortada. */}
                            <Suspense
                              fallback={
                                <div className="grid grid-cols-1 gap-3 sm:grid-cols-2" aria-hidden="true">
                                  <div className="esqueleto h-[50px] rounded-xl border border-pan-borde/50" />
                                  <div className="esqueleto h-[50px] rounded-xl border border-pan-borde/50" />
                                </div>
                              }
                            >
                              <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
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
                            </Suspense>
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

                  <fieldset className="space-y-5 border-0 p-0">
                    <PasoFormulario
                      numero={numeroPasoDatos}
                      titulo="Tus datos"
                      icono={UserRound}
                      listo={pasoDatosListo}
                    />
                    <p className="-mt-2 text-xs leading-relaxed text-pan-carbon-suave">
                      Los pedimos solo para poder confirmarte el pedido y tenerlo a tu nombre cuando
                      pases a recogerlo.
                    </p>

                    <div>
                      <label htmlFor="documento" className="mb-1.5 block text-sm font-medium text-pan-carbon">
                        Documento
                      </label>
                      <div className="mb-2">
                        <SelectorTipoDocumento
                          valor={tipoDocumento}
                          onChange={(tipo) => {
                            setTipoDocumento(tipo);
                            setNumeroDocumento("");
                          }}
                          layoutId="pedido-tipo-documento-activo"
                        />
                      </div>
                      <div className="relative">
                        <input
                          id="documento"
                          inputMode="numeric"
                          autoComplete="off"
                          maxLength={LONGITUD_DOCUMENTO[tipoDocumento]}
                          value={numeroDocumento}
                          onChange={(e) => {
                            const limpio = e.target.value.replace(/\D/g, "");
                            setNumeroDocumento(limpio);
                            // Al completar el largo esperado, se quita el foco
                            // de una vez: no hace falta que el cliente toque
                            // otro campo para que arranque la verificación.
                            if (limpio.length === LONGITUD_DOCUMENTO[tipoDocumento]) e.target.blur();
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
                      {mostrarInputTelefono ? (
                        <>
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
                          {contacto.telefono.enArchivo && (
                            <BotonVolverAlGuardado
                              onClick={() => {
                                setCambiandoTelefono(false);
                                setTelefono("");
                              }}
                            />
                          )}
                        </>
                      ) : (
                        <ContactoGuardado
                          mascara={contacto.telefono.mascara}
                          verificado={contacto.telefono.verificado}
                          notaVerificado="Celular verificado — para cambiarlo, hazlo dentro de la app."
                          onCambiar={() => setCambiandoTelefono(true)}
                        />
                      )}
                    </div>

                    {/* El correo es opcional: sirve para mandarte el
                        comprobante y avisos del pedido, pero un pedido sin
                        correo se registra igual. */}
                    <div>
                      <label htmlFor="email" className="mb-1.5 block text-sm font-medium text-pan-carbon">
                        Correo electrónico <span className="font-normal text-pan-carbon-suave">(opcional)</span>
                      </label>
                      {mostrarInputEmail ? (
                        <>
                          <input
                            id="email"
                            type="email"
                            inputMode="email"
                            autoComplete="email"
                            maxLength={150}
                            value={email}
                            onChange={(e) => setEmail(e.target.value)}
                            placeholder="Ingresa tu correo electrónico"
                            className="campo-pan"
                          />
                          {contacto.email.enArchivo && (
                            <BotonVolverAlGuardado
                              onClick={() => {
                                setCambiandoEmail(false);
                                setEmail("");
                              }}
                            />
                          )}
                        </>
                      ) : (
                        <ContactoGuardado
                          mascara={contacto.email.mascara}
                          verificado={contacto.email.verificado}
                          notaVerificado="Correo verificado — para cambiarlo, hazlo dentro de la app."
                          onCambiar={() => setCambiandoEmail(true)}
                        />
                      )}
                    </div>
                  </fieldset>

                  <div className="space-y-4">
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
        </motion.div>
      </div>
    </section>
  );
}

/** Un dato de contacto que ya teníamos guardado de este documento, mostrado
 * SIEMPRE enmascarado (`j***@gmail.com`, `9*****321`): el valor completo no
 * sale nunca del servidor, porque saber un DNI ajeno no debería alcanzar
 * para averiguar el correo o el celular de su dueño.
 *
 * Dos variantes:
 *  - sin verificar: se puede reemplazar por uno nuevo ("Cambiar" abre un
 *    campo vacío — jamás se le pide al cliente editar un texto con
 *    asteriscos, que no podría completar bien).
 *  - verificado: solo lectura. Cambiarlo exige el código de verificación
 *    que vive dentro de la app, no este formulario público. */
function ContactoGuardado({
  mascara,
  verificado,
  notaVerificado,
  onCambiar,
}: {
  mascara: string | null;
  verificado: boolean;
  notaVerificado: string;
  onCambiar: () => void;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, y: -4 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.25, ease: EASE_PREMIUM }}
      className="rounded-xl border border-pan-borde/50 bg-pan-crema px-4 py-3"
    >
      <div className="flex flex-wrap items-center justify-between gap-x-3 gap-y-1">
        <span className="flex min-w-0 items-center gap-2">
          {verificado && <ShieldCheck className="h-4 w-4 shrink-0 text-emerald-600" strokeWidth={1.75} />}
          <span className="truncate font-medium tracking-wide text-pan-carbon">{mascara ?? "—"}</span>
        </span>
        {!verificado && (
          <button
            type="button"
            onClick={onCambiar}
            className="-mx-2 inline-flex min-h-11 items-center gap-1.5 rounded px-2 text-xs font-semibold text-pan-terracota transition-colors hover:text-pan-terracota-profundo"
          >
            <Pencil className="h-3.5 w-3.5" strokeWidth={2} />
            Cambiar
          </button>
        )}
      </div>
      <p className="mt-0.5 text-xs leading-relaxed text-pan-carbon-suave">
        {verificado ? notaVerificado : "Lo tomamos de un pedido anterior. Te lo mostramos a medias por tu seguridad."}
      </p>
    </motion.div>
  );
}

/** Salida del modo "Cambiar": descarta lo que se escribió y vuelve a usar el
 * dato guardado, para que abrir el campo por curiosidad no obligue a
 * escribir el número/correo de nuevo. */
function BotonVolverAlGuardado({ onClick }: { onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="-mx-2 mt-1 inline-flex min-h-11 items-center gap-1.5 rounded px-2 text-xs font-semibold text-pan-carbon-suave transition-colors hover:text-pan-carbon"
    >
      <RotateCw className="h-3.5 w-3.5" strokeWidth={2} />
      Usar el dato que ya teníamos
    </button>
  );
}

/** Cabecera de un tramo del formulario: número, nombre y una marca que se
 * enciende cuando ese tramo ya quedó completo. El formulario sigue siendo
 * una sola pantalla (nada de pasos que obliguen a avanzar y retroceder),
 * pero se lee como bloques con principio y fin en vez de una lista larga de
 * campos sueltos. */
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
