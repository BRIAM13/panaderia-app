import { forwardRef, useImperativeHandle, useState } from "react";
import { Check, Croissant } from "lucide-react";
import { SelectorModal } from "./SelectorModal";
import type { ProductoPublico } from "../services/api";

export interface SelectorProductoHandle {
  abrir: () => void;
}

interface SelectorProductoProps {
  id?: string;
  productos: ProductoPublico[];
  valor: number | "";
  onChange: (idProducto: number) => void;
  cargando?: boolean;
  placeholder?: string;
}

/** Selector de pan como ventana emergente: solo lista los panes reales
 * (nada de una opción "Selecciona un pan" mezclada en la lista) y elegir
 * uno ya aplica y cierra de una vez — no hace falta un paso extra de
 * "Aceptar" como en fecha/hora, porque acá no hay nada que ajustar antes
 * de confirmar. */
export const SelectorProducto = forwardRef<SelectorProductoHandle, SelectorProductoProps>(function SelectorProducto(
  { id, productos, valor, onChange, cargando = false, placeholder = "Selecciona un pan" },
  ref,
) {
  const [abierto, setAbierto] = useState(false);

  function abrir() {
    if (cargando || productos.length === 0) return;
    setAbierto(true);
  }

  useImperativeHandle(ref, () => ({ abrir }));

  const seleccionado = productos.find((p) => p.idProducto === valor);

  function elegir(idProducto: number) {
    onChange(idProducto);
    setAbierto(false);
  }

  return (
    <div className="relative">
      <button
        id={id}
        type="button"
        onClick={abrir}
        disabled={cargando || productos.length === 0}
        className={`flex w-full items-center gap-2.5 rounded-xl border border-pan-borde bg-pan-crema px-4 py-3 text-left outline-none transition-colors focus:border-pan-terracota disabled:cursor-not-allowed disabled:opacity-60 ${
          seleccionado ? "text-pan-carbon" : "text-pan-carbon-suave"
        }`}
      >
        <Croissant className="h-4 w-4 shrink-0 text-pan-terracota" />
        <span>{cargando ? "Cargando productos…" : (seleccionado?.nombre ?? placeholder)}</span>
      </button>

      <SelectorModal abierto={abierto} titulo="Elige tu pan" onCancelar={() => setAbierto(false)} mostrarPie={false}>
        <div className="max-h-80 space-y-1 overflow-y-auto">
          {productos.map((p) => {
            const activo = p.idProducto === valor;
            return (
              <button
                key={p.idProducto}
                type="button"
                onClick={() => elegir(p.idProducto)}
                className={`flex w-full items-center justify-between gap-3 rounded-xl px-4 py-3 text-left transition-colors ${
                  activo
                    ? "bg-pan-terracota text-pan-crema"
                    : "text-pan-carbon hover:bg-pan-terracota-suave/40"
                }`}
              >
                <span className="font-medium">{p.nombre}</span>
                <span className="flex items-center gap-2 shrink-0">
                  <span className={`text-sm ${activo ? "text-pan-crema/80" : "text-pan-carbon-suave"}`}>
                    S/ {p.precioUnitario.toFixed(2)}
                    {p.esPaquete ? " el paquete" : " c/u"}
                  </span>
                  {activo && <Check className="h-4 w-4" />}
                </span>
              </button>
            );
          })}
        </div>
      </SelectorModal>
    </div>
  );
});
