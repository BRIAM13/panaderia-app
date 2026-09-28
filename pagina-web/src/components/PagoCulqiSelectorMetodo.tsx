import { motion } from "framer-motion";
import { AlertTriangle, ChevronRight, CreditCard, ShieldCheck, Smartphone } from "lucide-react";
import { EASE_PREMIUM } from "../utils/animacion";
import { FONDO_YAPE } from "./PagoCulqiYape";

/** Los dos medios de pago que ofrece el checkout de Culqi. Los dos terminan
 * en el mismo token de Culqi y en el mismo endpoint del backend. Vive acá (y
 * no en `PagoCulqi.tsx`) para que el selector no tenga que importar al padre. */
export type MetodoPagoCulqi = "TARJETA" | "YAPE";

/** Mismo degradado que la tarjeta de vista previa (`TarjetaPreview`), para
 * que el ícono de la opción "Tarjeta" ya se lea como la tarjeta que el
 * cliente va a ver en el paso siguiente. */
const FONDO_TARJETA_OPCION =
  "linear-gradient(135deg, var(--color-pan-carbon) 0%, var(--color-pan-terracota-profundo) 55%, var(--color-pan-terracota) 100%)";

interface SelectorMetodoPagoProps {
  numeroPedidoDia: number;
  total: number;
  /** null = se puede yapear este total; texto = por qué no. Con texto, la
   * opción Yape se muestra apagada y con el motivo debajo, en vez de dejar
   * que el cliente la elija y recién se entere dentro del formulario. */
  yapeNoDisponible: string | null;
  onElegir: (metodo: MetodoPagoCulqi) => void;
  onCancelar?: () => void;
  etiquetaCancelar: string;
  compacto: boolean;
}

/**
 * El PRIMER paso del checkout: "¿Cómo quieres pagar?". Dos opciones grandes,
 * Tarjeta y Yape, y NINGUNA viene elegida — el cliente tiene que tocar una
 * para recién ver el formulario de ese medio. Pedido explícito del dueño
 * (2026-09-27): no quería el selector de pestañas que ya mostraba un
 * formulario por defecto, sino una decisión clara antes de pagar.
 *
 * Es puramente visual: quién carga CulqiJS, valida y genera el token sigue
 * siendo `PagoCulqi`; esto solo le avisa qué eligió el cliente.
 */
export function SelectorMetodoPago({
  numeroPedidoDia,
  total,
  yapeNoDisponible,
  onElegir,
  onCancelar,
  etiquetaCancelar,
  compacto,
}: SelectorMetodoPagoProps) {
  return (
    <div className="space-y-4">
      {/* El monto ANTES de las opciones: es lo que el cliente necesita tener
          claro para decidir con qué pagar (Yape tiene tope, por ejemplo).
          Mismo panel de resumen que ve después dentro del formulario. */}
      <div className="flex items-center justify-between gap-3 rounded-2xl border border-pan-borde/40 bg-pan-crema px-4 py-3.5 sm:px-5 sm:py-4">
        <div className="min-w-0">
          <p className="text-[11px] font-semibold tracking-[0.14em] text-pan-carbon-suave uppercase">
            Pedido #{numeroPedidoDia}
          </p>
          <p className="mt-0.5 text-sm font-medium text-pan-carbon">Total a pagar</p>
        </div>
        <span className="shrink-0 text-2xl font-bold tabular-nums text-pan-terracota sm:text-[1.75rem]">
          S/ {total.toFixed(2)}
        </span>
      </div>

      <div role="group" aria-labelledby="titulo-metodo-pago">
        <h4
          id="titulo-metodo-pago"
          className="font-[family-name:var(--font-display-panaderia)] text-lg font-semibold text-pan-carbon sm:text-xl"
        >
          ¿Cómo quieres pagar?
        </h4>
        <p className="mt-0.5 text-[13px] leading-relaxed text-pan-carbon-suave">
          Elige un medio para continuar. Los dos son seguros y el cobro sale al instante.
        </p>

        {/* Dos tarjetas grandes, una por medio. En escritorio van lado a
            lado; en celular y en el panel compacto de "mis pedidos" se
            apilan. Son botones de acción (no radios): acá no hay nada
            marcado hasta que el cliente toca una. */}
        <div className={`mt-3 grid grid-cols-1 gap-3 ${compacto ? "" : "sm:grid-cols-2"}`}>
          <OpcionMetodo
            titulo="Tarjeta"
            descripcion="Crédito o débito"
            fondoIcono={FONDO_TARJETA_OPCION}
            Icono={CreditCard}
            onClick={() => onElegir("TARJETA")}
          />
          <OpcionMetodo
            titulo="Yape"
            descripcion="Desde tu app de Yape"
            fondoIcono={FONDO_YAPE}
            Icono={Smartphone}
            motivoDeshabilitado={yapeNoDisponible}
            onClick={() => onElegir("YAPE")}
          />
        </div>
      </div>

      <p className="flex items-start gap-2 text-xs leading-relaxed text-pan-carbon-suave">
        <ShieldCheck className="mt-0.5 h-3.5 w-3.5 shrink-0 text-emerald-600" strokeWidth={1.75} />
        Pago seguro procesado por Culqi (certificado PCI-DSS). Tus datos nunca pasan por nuestros servidores.
      </p>

      {/* Salir del pago entero también desde el primer paso: el mismo botón
          secundario que en el formulario, para que no haya que elegir un
          medio solo para poder cancelar. */}
      {onCancelar && (
        <div className={`flex pt-0.5 ${compacto ? "" : "sm:justify-start"}`}>
          <motion.button
            type="button"
            onClick={onCancelar}
            whileTap={{ scale: 0.98 }}
            className={`boton-relleno flex min-h-12 w-full items-center justify-center rounded-full border border-pan-borde bg-pan-crema-suave px-6 py-3 text-sm font-semibold text-pan-carbon-suave ${
              compacto ? "" : "sm:w-auto sm:min-w-32"
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
        </div>
      )}
    </div>
  );
}

interface OpcionMetodoProps {
  titulo: string;
  descripcion: string;
  fondoIcono: string;
  Icono: typeof CreditCard;
  /** Con texto, la opción se pinta apagada, no se puede tocar y muestra el
   * motivo debajo. */
  motivoDeshabilitado?: string | null;
  onClick: () => void;
}

/**
 * Una opción del selector: ícono en un cuadro con el degradado de su medio,
 * nombre, una línea de descripción y la flecha que dice "esto lleva a otro
 * paso". Levanta y se enciende el borde al pasar el mouse, igual que las
 * tarjetas de `Nosotros`; apagada, ni se levanta ni cambia el cursor.
 */
function OpcionMetodo({ titulo, descripcion, fondoIcono, Icono, motivoDeshabilitado, onClick }: OpcionMetodoProps) {
  const deshabilitada = Boolean(motivoDeshabilitado);

  return (
    <div className="flex flex-col">
      <motion.button
        type="button"
        onClick={onClick}
        disabled={deshabilitada}
        aria-disabled={deshabilitada}
        aria-describedby={deshabilitada ? `motivo-${titulo}` : undefined}
        whileHover={deshabilitada ? undefined : { y: -3 }}
        whileTap={deshabilitada ? undefined : { scale: 0.98 }}
        transition={{ duration: 0.25, ease: EASE_PREMIUM }}
        className={`group flex min-h-20 w-full items-center gap-4 rounded-2xl border bg-pan-crema-suave p-4 text-left shadow-sm shadow-pan-carbon/5 transition-[border-color,box-shadow] duration-300 sm:p-5 ${
          deshabilitada
            ? "cursor-not-allowed border-pan-borde/30 opacity-60 saturate-50"
            : "cursor-pointer border-pan-borde/50 hover:border-pan-terracota hover:shadow-lg hover:shadow-pan-terracota/15 focus-visible:border-pan-terracota"
        }`}
      >
        <span
          aria-hidden="true"
          className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl text-pan-crema shadow-md shadow-pan-carbon/15 transition-transform duration-500 ease-[cubic-bezier(0.16,1,0.3,1)] group-hover:-rotate-6 group-hover:scale-110 group-disabled:transform-none"
          style={{ background: fondoIcono }}
        >
          <Icono className="h-6 w-6" strokeWidth={1.75} />
        </span>
        <span className="min-w-0 flex-1">
          <span className="block text-base font-semibold text-pan-carbon">{titulo}</span>
          <span className="mt-0.5 block text-[13px] leading-snug text-pan-carbon-suave">{descripcion}</span>
        </span>
        <ChevronRight
          aria-hidden="true"
          className="h-5 w-5 shrink-0 text-pan-carbon-suave/70 transition-transform duration-300 group-hover:translate-x-1 group-hover:text-pan-terracota group-disabled:transform-none"
          strokeWidth={2}
        />
      </motion.button>

      {deshabilitada && (
        <p
          id={`motivo-${titulo}`}
          className="mt-2 flex items-start gap-2 rounded-xl border border-amber-300 bg-amber-50 px-3.5 py-2.5 text-xs leading-relaxed font-medium text-amber-800"
        >
          <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0 text-amber-600" strokeWidth={1.75} />
          {motivoDeshabilitado}
        </p>
      )}
    </div>
  );
}
