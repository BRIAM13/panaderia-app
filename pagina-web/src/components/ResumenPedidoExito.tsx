import { useEffect, useRef } from "react";
import { motion } from "framer-motion";
import { AlertTriangle, BadgePercent, CheckCircle2, CreditCard, ShieldCheck } from "lucide-react";
import type { PedidoPublicoResultado } from "../services/api";
import { formatearFechaBonita, formatearHora12 } from "../utils/horariosPan";
import { montoDescontado, textoDescuento } from "../utils/descuentos";
import { EASE_PREMIUM } from "../utils/animacion";

export interface DetallePedidoEnviado {
  producto: string;
  cantidad: string;
  esPaquete: boolean;
  documento: string;
  telefono: string;
  /** "YYYY-MM-DD" y "HH:mm", vacíos en los pedidos por paquete (que no
   * usan el flujo de recojo con fecha/hora). */
  fechaRecojo: string;
  horaRecojo: string;
  notas: string;
}

interface ResumenPedidoExitoProps {
  resultado: PedidoPublicoResultado;
  detalle: DetallePedidoEnviado;
  /** El horario elegido ya había cerrado al enviar: se avisa que la
   * confirmación depende de que quede stock. */
  fueraDeVentana: boolean;
  /** Solo en Panadería con el cobro por adelantado encendido: true si Culqi
   * ya confirmó el cobro de la tarjeta, false si el cliente salió de la
   * pantalla de pago sin pagar ("lo pago después"). Se ignora en los pedidos
   * que no se pagan por adelantado. */
  pagoConfirmado?: boolean;
  onPedirDeNuevo: () => void;
}

/** La pantalla que reemplaza al formulario una vez que el pedido entró:
 * número, total y el detalle exacto de lo que se envió, para que el cliente
 * pueda contrastarlo con lo que quería pedir. */
export function ResumenPedidoExito({
  resultado,
  detalle,
  fueraDeVentana,
  pagoConfirmado = false,
  onPedirDeNuevo,
}: ResumenPedidoExitoProps) {
  // El foco salta al título: quien navega con teclado o lector de pantalla
  // necesita que se le anuncie que el formulario ya no está y qué lo
  // reemplazó.
  const tituloRef = useRef<HTMLHeadingElement>(null);
  useEffect(() => {
    const id = window.setTimeout(() => tituloRef.current?.focus(), 250);
    return () => window.clearTimeout(id);
  }, []);

  // Ausente con un backend viejo (o cuando el pedido no llevó descuento):
  // en ese caso la pantalla queda exactamente como era antes.
  const descuento = resultado.descuentoCliente ?? null;
  // Solo los pedidos de Panadería con el cobro por adelantado encendido pasan
  // por el pago con tarjeta. En cualquier otro ("NO_APLICA", o ausente con un
  // backend viejo) esta pantalla es exactamente la de siempre.
  //
  // El aviso de pago se muestra en los DOS desenlaces posibles de ese flujo:
  // 'VERIFICANDO' (salió sin pagar, todavía le falta) y 'PAGADO' (Culqi
  // cobró). Antes bastaba con mirar 'VERIFICANDO' porque el pago lo confirmaba
  // una persona mucho después; ahora se confirma en la misma petición, así que
  // el estado ya viene resuelto cuando esta pantalla aparece.
  const hayPagoPorAdelantado =
    resultado.estadoPagoAdelanto === "VERIFICANDO" || resultado.estadoPagoAdelanto === "PAGADO";

  return (
    <motion.div
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
        {/* Onda que se expande una sola vez detrás del check — el "clic"
            visual que confirma que algo se completó. */}
        <motion.span
          initial={{ scale: 0.6, opacity: 0.5 }}
          animate={{ scale: 2.1, opacity: 0 }}
          transition={{ duration: 1, ease: "easeOut", delay: 0.15 }}
          className="absolute inset-0 rounded-full bg-emerald-500/30"
        />
        <CheckCircle2 className="relative h-14 w-14 text-emerald-600" strokeWidth={1.6} />
      </motion.div>
      <h3
        ref={tituloRef}
        tabIndex={-1}
        className="mt-4 font-[family-name:var(--font-display-panaderia)] text-2xl font-semibold text-pan-carbon outline-none"
      >
        Pedido #{resultado.numeroPedidoDia} recibido
      </h3>
      <p className="mt-2 text-pan-carbon-suave">{resultado.mensaje}</p>
      {/* Todo lo de acá sale de la respuesta del SERVIDOR, no de lo que la
          web había estimado: si por lo que sea el descuento que se aplicó
          terminó siendo otro (el historial del cliente se calcula de nuevo
          al guardar el pedido), lo que el cliente ve es lo que de verdad se
          guardó. */}
      {descuento && resultado.subtotal != null && (
        <motion.div
          initial={{ opacity: 0, y: -4 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.3, ease: EASE_PREMIUM, delay: 0.25 }}
          className="mx-auto mt-4 flex max-w-sm items-center justify-center gap-2 rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-2.5"
        >
          <BadgePercent className="h-4 w-4 shrink-0 text-emerald-600" strokeWidth={1.75} />
          <p className="text-xs font-medium text-emerald-800">
            {textoDescuento(descuento)}: ahorraste S/{" "}
            {montoDescontado(resultado.subtotal, descuento.porcentaje).toFixed(2)}
          </p>
        </motion.div>
      )}
      <p className="mt-3 text-lg font-semibold text-pan-terracota">
        Total: S/ {resultado.total.toFixed(2)}
      </p>

      {/* Estado del pago por adelantado. NO se vuelve a decir "recibido"
          (ya lo dice el título de arriba): lo que falta contar acá es en qué
          quedó el pago, que es lo único que el cliente todavía no sabe. */}
      {hayPagoPorAdelantado && (
        <div
          className={`mx-auto mt-4 flex max-w-sm items-start gap-2.5 rounded-xl border px-4 py-3 text-left ${
            pagoConfirmado ? "border-emerald-200 bg-emerald-50" : "border-amber-300 bg-amber-50"
          }`}
        >
          {pagoConfirmado ? (
            <ShieldCheck className="mt-0.5 h-4 w-4 shrink-0 text-emerald-600" strokeWidth={1.75} />
          ) : (
            <CreditCard className="mt-0.5 h-4 w-4 shrink-0 text-amber-600" strokeWidth={1.75} />
          )}
          <p
            className={`text-xs leading-relaxed font-medium ${
              pagoConfirmado ? "text-emerald-800" : "text-amber-800"
            }`}
          >
            {pagoConfirmado
              ? "Tu pago con tarjeta quedó confirmado y ya estamos preparando tu pedido. Te llega el comprobante al correo que dejaste."
              : "Tu pedido está guardado, pero todavía nos falta tu pago. Vuelve a “Ver mi pedido”, busca tu documento y págalo con tarjeta desde ahí."}
          </p>
        </div>
      )}

      <div className="mx-auto mt-5 max-w-sm space-y-2.5 rounded-2xl border border-pan-borde/25 bg-pan-crema px-5 py-4 text-left text-sm">
        <FilaDetallePedido etiqueta="Producto" valor={detalle.producto} />
        <FilaDetallePedido
          etiqueta={detalle.esPaquete ? "Paquetes" : "Cantidad"}
          valor={detalle.cantidad || "—"}
        />
        <FilaDetallePedido etiqueta="Documento" valor={detalle.documento} />
        <FilaDetallePedido etiqueta="Celular" valor={detalle.telefono} />
        {!detalle.esPaquete && detalle.fechaRecojo && detalle.horaRecojo && (
          <FilaDetallePedido
            etiqueta="Recojo"
            valor={`${formatearFechaBonita(detalle.fechaRecojo)}, ${formatearHora12(detalle.horaRecojo)}`}
          />
        )}
        {detalle.notas && <FilaDetallePedido etiqueta="Notas" valor={detalle.notas} />}
      </div>

      {fueraDeVentana && (
        <div className="mx-auto mt-4 flex max-w-sm items-start gap-2.5 rounded-xl border border-amber-300 bg-amber-50 px-4 py-3 text-left">
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-amber-600" strokeWidth={1.75} />
          <p className="text-xs font-medium text-amber-800">
            Como el horario elegido ya cerró, te confirmaremos por WhatsApp al número que dejaste si
            tenemos stock disponible para separar tu pedido.
          </p>
        </div>
      )}
      <button
        onClick={onPedirDeNuevo}
        className="boton-relleno mt-6 inline-flex min-h-12 items-center justify-center rounded-full border border-pan-borde px-6 text-sm font-semibold text-pan-carbon"
      >
        Hacer otro pedido
      </button>
    </motion.div>
  );
}

/** Una fila del resumen — mismo formato etiqueta + valor para documento,
 * producto, recojo, etc. */
function FilaDetallePedido({ etiqueta, valor }: { etiqueta: string; valor: string }) {
  return (
    // La etiqueta no se parte nunca y el valor se queda con el resto del
    // ancho: una nota larga o un nombre de pan largo se acomodaban antes
    // empujando la etiqueta hasta partirla ("Doc- / umento") en pantallas
    // angostas. `break-words` corta además una palabra sin espacios que no
    // entre por sí sola.
    <div className="flex items-start justify-between gap-4">
      <span className="shrink-0 text-pan-carbon-suave">{etiqueta}</span>
      <span className="min-w-0 text-right font-medium break-words text-pan-carbon">{valor}</span>
    </div>
  );
}
