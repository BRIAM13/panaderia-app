import { AnimatePresence, motion } from "framer-motion";
import { KeyRound, Mail, Smartphone, Timer } from "lucide-react";
import { limpiarEmail } from "../utils/tarjeta";
import {
  LARGO_CODIGO_YAPE,
  celularParaVistaPrevia,
  formatearCelular,
  limpiarCelular,
  limpiarCodigoYape,
} from "../utils/yape";
import { EASE_PREMIUM } from "../utils/animacion";

/**
 * Las piezas de Yape del checkout de Culqi (`PagoCulqi.tsx`): el panel de
 * vista previa que ocupa el lugar de la tarjeta, y los tres campos que Yape
 * necesita. Viven en su propio archivo por tamaño, no por independencia —
 * quien carga CulqiJS, elige el método, valida, genera el token y muestra el
 * error/los botones sigue siendo `PagoCulqi`. Esto es solo lo que se PINTA
 * distinto cuando el cliente elige Yape.
 *
 * Los `id`/`data-culqi` de los campos NO son decorativos: CulqiJS v4 lee
 * `yape[phone]` y `yape[code]` directamente del DOM cuando se le pide
 * generar el token (`getYapeFormData()` en el bundle v4: busca
 * `[data-culqi="yape[phone]"]` o `getElementById("yape[phone]")`, y manda
 * `{ otp, number_phone, amount }` a `/v2/tokens/yape`). Confirmado el
 * 2026-09-27 contra el bundle y el demo oficial `culqi/culqi-reactjs-demo-jsv4`.
 */

/** Morado de Yape — a propósito NO es de la paleta del sitio: el panel tiene
 * que leerse de un vistazo como "esto es Yape", igual que la tarjeta se lee
 * como una tarjeta. El brillo dorado encima sí es el del proyecto, para que
 * no se sienta pegado de otra página. */
export const FONDO_YAPE = "linear-gradient(135deg, #2a0b3a 0%, #742284 55%, #8f2ea3 100%)";

/**
 * Lo que va a la izquierda en modo Yape, en el mismo hueco (misma proporción
 * 1.6:1) que ocupa la tarjeta en modo tarjeta, para que cambiar de método no
 * mueva el resto de la pantalla. Es el "comprobante" que el cliente va a ver
 * en su app: el monto grande, su celular tal como lo escribe y los seis
 * puntos del código llenándose — la misma idea del CVC en el reverso de la
 * tarjeta, solo que acá el celular sí se muestra entero: no es un dato
 * sensible, y verlo ayuda a cazar el dígito mal tecleado antes de generar el
 * token.
 *
 * `monto` es lo que SALE del Yape del cliente (lo elegido más la comisión de
 * la pasarela), no el total del pedido: es la cifra que va a ver en su app.
 */
export function VistaPreviaYape({ celular, codigo, monto }: { celular: string; codigo: string; monto: number }) {
  const digitosCodigo = limpiarCodigoYape(codigo).length;

  return (
    <div aria-hidden="true" className="relative aspect-[1.6/1] w-full">
      <div
        className="absolute inset-0 overflow-hidden rounded-2xl p-5 shadow-lg shadow-pan-carbon/20"
        style={{ background: FONDO_YAPE }}
      >
        <div
          className="absolute -top-12 -right-12 h-44 w-44 rounded-full opacity-30 blur-2xl"
          style={{ background: "var(--color-pan-oro)" }}
        />
        <div
          className="absolute -bottom-16 -left-10 h-40 w-40 rounded-full opacity-25 blur-2xl"
          style={{ background: "#c05ad6" }}
        />

        <div className="relative flex h-full flex-col justify-between text-pan-crema">
          <div className="flex items-start justify-between">
            {/* Wordmark como texto, sin logo: no es un activo nuestro, y el
                nombre en minúscula con el morado ya lo identifica. */}
            <span className="text-2xl leading-none font-bold tracking-tight lowercase">yape</span>
            <span className="flex h-8 w-8 items-center justify-center rounded-full bg-pan-crema/15 ring-1 ring-pan-crema/25">
              <Smartphone className="h-4 w-4" strokeWidth={1.75} />
            </span>
          </div>

          <div>
            <p className="text-[10px] tracking-[0.16em] text-pan-crema/65 uppercase">Vas a yapear</p>
            <p className="text-2xl font-bold tabular-nums sm:text-[1.75rem]">S/ {monto.toFixed(2)}</p>
          </div>

          <div className="flex items-end justify-between gap-4">
            <div className="min-w-0">
              <p className="text-[10px] tracking-[0.16em] text-pan-crema/65 uppercase">Desde el celular</p>
              <p className="font-mono text-base tracking-widest tabular-nums sm:text-lg">
                {celularParaVistaPrevia(celular)}
              </p>
            </div>
            <div className="shrink-0 text-right">
              <p className="text-[10px] tracking-[0.16em] text-pan-crema/65 uppercase">Código</p>
              <div className="mt-1 flex items-center gap-1.5">
                {Array.from({ length: LARGO_CODIGO_YAPE }, (_, i) => (
                  <span key={i} className="relative h-2.5 w-2.5 rounded-full bg-pan-crema/25">
                    <AnimatePresence initial={false}>
                      {i < digitosCodigo && (
                        <motion.span
                          initial={{ scale: 0.3, opacity: 0 }}
                          animate={{ scale: 1, opacity: 1 }}
                          exit={{ scale: 0.3, opacity: 0 }}
                          transition={{ duration: 0.18, ease: EASE_PREMIUM }}
                          className="absolute inset-0 rounded-full bg-pan-crema shadow-[0_0_8px_rgba(253,246,236,0.7)]"
                        />
                      )}
                    </AnimatePresence>
                  </span>
                ))}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

interface CamposYapeProps {
  celular: string;
  codigo: string;
  email: string;
  onCelular: (valor: string) => void;
  onCodigo: (valor: string) => void;
  onEmail: (valor: string) => void;
}

/**
 * Los campos del modo Yape, en el orden en que conviene llenarlos: primero
 * el celular y el correo (no caducan), y AL FINAL el código de aprobación,
 * con las instrucciones pegadas justo encima — porque el código vale unos
 * dos minutos desde que la app lo genera, y no tiene sentido pedirlo antes
 * de que el cliente haya escrito lo demás.
 *
 * Cada `onX` recibe el valor ya limpio (solo dígitos / sin espacios): la
 * limpieza es de acá, la validación de si alcanza es de `PagoCulqi`.
 */
export function CamposYape({ celular, codigo, email, onCelular, onCodigo, onEmail }: CamposYapeProps) {
  return (
    <>
      <div>
        <label htmlFor="celular-yape" className="mb-1 block text-[13px] font-medium text-pan-carbon">
          Tu celular con Yape
        </label>
        <div className="relative">
          <input
            id="celular-yape"
            type="tel"
            inputMode="numeric"
            autoComplete="tel-national"
            value={formatearCelular(celular)}
            onChange={(e) => onCelular(limpiarCelular(e.target.value))}
            placeholder="987 654 321"
            // 9 dígitos + los 2 espacios del formato.
            maxLength={11}
            required
            className="campo-pan select-text pr-10 tabular-nums"
          />
          <Smartphone
            className="pointer-events-none absolute inset-y-0 right-3.5 my-auto h-4 w-4 text-pan-carbon-suave"
            strokeWidth={1.75}
          />
        </div>
        {/* El campo que CulqiJS de verdad lee (ver el encabezado): los 9
            dígitos pelados, sin el formato visual. `hidden` por lo mismo que
            los `card[...]` del modo tarjeta. */}
        <input type="hidden" id="yape[phone]" name="yape[phone]" data-culqi="yape[phone]" value={celular} readOnly />
      </div>

      <div>
        <label htmlFor="correo-yape" className="mb-1 block text-[13px] font-medium text-pan-carbon">
          Correo electrónico
        </label>
        <div className="relative">
          <input
            id="correo-yape"
            type="email"
            inputMode="email"
            autoComplete="email"
            value={email}
            onChange={(e) => onEmail(limpiarEmail(e.target.value))}
            placeholder="tucorreo@ejemplo.com"
            required
            className="campo-pan select-text pr-9"
          />
          <Mail
            className="pointer-events-none absolute inset-y-0 right-3.5 my-auto h-4 w-4 text-pan-carbon-suave"
            strokeWidth={1.75}
          />
        </div>
        <p className="mt-1 text-xs text-pan-carbon-suave">Ahí te llega el comprobante de Culqi.</p>
      </div>

      {/* Cómo conseguir el código, en tres pasos y sin rodeos. Va pegado al
          campo del código y no arriba de todo: es lo último que el cliente
          hace, y así lo lee justo cuando lo necesita. */}
      <ol className="space-y-1.5 rounded-xl border border-pan-borde/40 bg-pan-crema px-4 py-3 text-[13px] leading-snug text-pan-carbon">
        <PasoYape numero={1}>
          Abre tu app de Yape y toca <strong className="font-semibold">Código de aprobación</strong> en el menú.
        </PasoYape>
        <PasoYape numero={2}>Genera el código: son 6 dígitos y vale unos 2 minutos.</PasoYape>
        <PasoYape numero={3}>Escríbelo acá abajo y confirma. El cobro sale de tu Yape al instante.</PasoYape>
      </ol>

      <div>
        <label htmlFor="yape[code]" className="mb-1 block text-[13px] font-medium text-pan-carbon">
          Código de aprobación
        </label>
        <div className="relative">
          {/* Este sí es el campo real que lee CulqiJS: el código no lleva
              formato, así que no hace falta un campo oculto aparte. */}
          <input
            id="yape[code]"
            name="yape[code]"
            data-culqi="yape[code]"
            inputMode="numeric"
            autoComplete="one-time-code"
            value={codigo}
            onChange={(e) => onCodigo(limpiarCodigoYape(e.target.value))}
            placeholder="123456"
            maxLength={LARGO_CODIGO_YAPE}
            required
            className="campo-pan select-text pr-10 font-mono text-lg tracking-[0.35em] tabular-nums placeholder:font-sans placeholder:text-base placeholder:tracking-normal"
          />
          <KeyRound
            className="pointer-events-none absolute inset-y-0 right-3.5 my-auto h-4 w-4 text-pan-carbon-suave"
            strokeWidth={1.75}
          />
        </div>
        <p className="mt-1 flex items-center gap-1.5 text-xs text-pan-carbon-suave">
          <Timer className="h-3.5 w-3.5 shrink-0" strokeWidth={1.75} />
          Si se te pasa el tiempo, genera otro en tu app y vuelve a intentar.
        </p>
      </div>
    </>
  );
}

function PasoYape({ numero, children }: { numero: number; children: React.ReactNode }) {
  return (
    <li className="flex items-start gap-2.5">
      <span className="mt-px flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-pan-terracota/10 text-[11px] font-bold text-pan-terracota tabular-nums">
        {numero}
      </span>
      <span className="min-w-0">{children}</span>
    </li>
  );
}
