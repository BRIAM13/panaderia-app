import { forwardRef, useImperativeHandle, useState } from "react";
import { CalendarDays, ChevronLeft, ChevronRight } from "lucide-react";
import { SelectorModal } from "./SelectorModal";

const DIAS_SEMANA = ["D", "L", "M", "M", "J", "V", "S"];
const MESES = [
  "enero", "febrero", "marzo", "abril", "mayo", "junio",
  "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre",
];

function aClaveFecha(fecha: Date): string {
  const y = fecha.getFullYear();
  const m = String(fecha.getMonth() + 1).padStart(2, "0");
  const d = String(fecha.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

function inicioDelDia(fecha: Date): Date {
  return new Date(fecha.getFullYear(), fecha.getMonth(), fecha.getDate());
}

/** "YYYY-MM-DD" -> "Mié 19 de agosto". Exportada porque el resumen del
 * pedido (pantalla de éxito en PedidoForm) reusa el mismo formato. */
export function formatearFechaBonita(clave: string): string {
  const [y, m, d] = clave.split("-").map(Number);
  const fecha = new Date(y, m - 1, d);
  const diasCorto = ["dom", "lun", "mar", "mié", "jue", "vie", "sáb"];
  const texto = `${diasCorto[fecha.getDay()]} ${d} de ${MESES[m - 1]}`;
  return texto.charAt(0).toUpperCase() + texto.slice(1);
}

export interface SelectorFechaHandle {
  abrir: () => void;
}

interface SelectorFechaProps {
  id?: string;
  /** "YYYY-MM-DD" o "" si todavía no eligió. */
  valor: string;
  onChange: (fecha: string) => void;
  /** No se puede elegir ningún día anterior a este (inclusive). */
  minimo: Date;
  placeholder?: string;
  /** Aviso destacado dentro de la ventana (ej. "primero elige la fecha
   * para poder elegir la hora"), para cuando este selector se abrió solo
   * porque el cliente intentó abrir la hora sin haber elegido fecha. */
  aviso?: string;
}

/** Selector de fecha propio, con la paleta y el estilo del sitio — en vez
 * del <input type=date> nativo, cuyo aspecto varía según navegador/SO y no
 * combina con el resto del formulario. Nunca deja elegir un día anterior a
 * `minimo`. Abre como ventana emergente con Cancelar/Aceptar: el cliente
 * arma su elección primero y recién se aplica al aceptar. */
export const SelectorFecha = forwardRef<SelectorFechaHandle, SelectorFechaProps>(function SelectorFecha(
  { id, valor, onChange, minimo, placeholder = "Elige una fecha", aviso },
  ref,
) {
  const [abierto, setAbierto] = useState(false);
  const minimoDia = inicioDelDia(minimo);
  const [draft, setDraft] = useState(valor);
  const [mesVisible, setMesVisible] = useState(() => {
    const base = valor ? new Date(`${valor}T00:00:00`) : minimoDia;
    return new Date(base.getFullYear(), base.getMonth(), 1);
  });

  function abrir() {
    // La primera vez (todavía sin elegir nada) el calendario abre con el
    // primer día válido ya marcado, listo para aceptar de una — normalmente
    // hoy, pero si hoy ya no admite ningún horario (ver `minimo`, que el
    // padre puede empujar a mañana) arranca directo en el primer día que sí
    // sirve. Si el cliente ya había elegido una fecha antes, reabrir vuelve
    // a mostrar esa misma.
    const draftInicial = valor || aClaveFecha(minimoDia);
    setDraft(draftInicial);
    const base = valor ? new Date(`${valor}T00:00:00`) : minimoDia;
    setMesVisible(new Date(base.getFullYear(), base.getMonth(), 1));
    setAbierto(true);
  }

  function aceptar() {
    if (draft) onChange(draft);
    setAbierto(false);
  }

  // Además de vacío, un borrador que quedó apuntando a un día que ya no es
  // válido (ej. el panel se quedó abierto y "hoy" dejó de ofrecerse
  // mientras tanto) tampoco debe poder aceptarse.
  const draftInvalido = !draft || new Date(`${draft}T00:00:00`) < minimoDia;

  useImperativeHandle(ref, () => ({ abrir }));

  const primerDiaSemana = new Date(mesVisible.getFullYear(), mesVisible.getMonth(), 1).getDay();
  const diasEnMes = new Date(mesVisible.getFullYear(), mesVisible.getMonth() + 1, 0).getDate();
  const celdas: (Date | null)[] = [
    ...Array(primerDiaSemana).fill(null),
    ...Array.from({ length: diasEnMes }, (_, i) => new Date(mesVisible.getFullYear(), mesVisible.getMonth(), i + 1)),
  ];

  const hoyClave = aClaveFecha(new Date());

  return (
    <div className="relative">
      <button
        id={id}
        type="button"
        onClick={abrir}
        className={`flex w-full items-center gap-2.5 rounded-xl border border-pan-borde bg-pan-crema px-4 py-3 text-left outline-none focus:border-pan-terracota ${
          valor ? "text-pan-carbon" : "text-pan-carbon-suave"
        }`}
      >
        <CalendarDays className="h-4 w-4 shrink-0 text-pan-terracota" />
        <span>{valor ? formatearFechaBonita(valor) : placeholder}</span>
      </button>

      <SelectorModal
        abierto={abierto}
        titulo="Elige la fecha de recojo"
        onCancelar={() => setAbierto(false)}
        onAceptar={aceptar}
        aceptarDeshabilitado={draftInvalido}
      >
        {aviso && (
          <p className="mb-3 rounded-xl border border-amber-300 bg-amber-50 px-3 py-2 text-center text-xs font-medium text-amber-800">
            {aviso}
          </p>
        )}
        <div className="mb-3 flex items-center justify-between">
          <button
            type="button"
            aria-label="Mes anterior"
            onClick={() => setMesVisible((m) => new Date(m.getFullYear(), m.getMonth() - 1, 1))}
            className="rounded-full p-1.5 text-pan-carbon-suave transition-colors hover:bg-pan-crema-muted hover:text-pan-carbon"
          >
            <ChevronLeft className="h-4 w-4" />
          </button>
          <p className="text-sm font-semibold text-pan-carbon capitalize">
            {MESES[mesVisible.getMonth()]} {mesVisible.getFullYear()}
          </p>
          <button
            type="button"
            aria-label="Mes siguiente"
            onClick={() => setMesVisible((m) => new Date(m.getFullYear(), m.getMonth() + 1, 1))}
            className="rounded-full p-1.5 text-pan-carbon-suave transition-colors hover:bg-pan-crema-muted hover:text-pan-carbon"
          >
            <ChevronRight className="h-4 w-4" />
          </button>
        </div>

        <div className="grid grid-cols-7 gap-y-1 text-center">
          {DIAS_SEMANA.map((d, i) => (
            <span key={i} className="text-[11px] font-semibold text-pan-carbon-suave">
              {d}
            </span>
          ))}
          {celdas.map((dia, i) => {
            if (!dia) return <span key={i} />;
            const clave = aClaveFecha(dia);
            const deshabilitado = dia < minimoDia;
            const esHoy = clave === hoyClave;
            const seleccionado = clave === draft;
            return (
              <button
                key={i}
                type="button"
                disabled={deshabilitado}
                onClick={() => setDraft(clave)}
                className={`mx-auto flex h-8 w-8 items-center justify-center rounded-full text-sm transition-colors ${
                  seleccionado
                    ? "bg-pan-terracota font-semibold text-pan-crema"
                    : deshabilitado
                      ? "cursor-not-allowed text-pan-carbon-suave/35"
                      : esHoy
                        ? "border border-pan-terracota font-semibold text-pan-terracota hover:bg-pan-terracota-suave/50"
                        : "text-pan-carbon hover:bg-pan-terracota-suave/50"
                }`}
              >
                {dia.getDate()}
              </button>
            );
          })}
        </div>
      </SelectorModal>
    </div>
  );
});
