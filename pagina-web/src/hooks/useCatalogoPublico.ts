import { useCallback, useEffect, useRef, useState } from "react";
import { PRODUCTOS } from "../data/config";
import {
  obtenerCatalogoPublico,
  type HorariosPanaderia,
  type ProductoPublico,
} from "../services/api";
import { filtrarProductosDelMenu, nombresSinCoincidencia } from "../utils/catalogoMenu";

const NOMBRES_CONFIGURADOS = PRODUCTOS.map((p) => p.nombreEnCatalogo);

const MENSAJE_ERROR =
  "No pudimos cargar el catálogo porque el servidor puede estar despertando. Intenta de nuevo en un momento.";

// Los horarios (y sobre todo los 2 interruptores de franja) pueden cambiar
// en cualquier momento desde la app: sin este sondeo, alguien que ya tenía
// la página abierta seguía viendo el horario viejo hasta recargar.
const INTERVALO_SONDEO_MS = 30000;

export interface CatalogoPublico {
  /** Ya filtrados a los panes que la web ofrece (ver filtrarProductosDelMenu). */
  productos: ProductoPublico[];
  horarios: HorariosPanaderia | null;
  cargando: boolean;
  error: string | null;
  /** Vuelve a intentar la carga mostrando el esqueleto — lo usa el botón
   * "Reintentar" del estado de error. */
  recargar: () => void;
}

interface Opciones {
  /** true detiene el sondeo periódico (no la carga inicial). Se usa una vez
   * que el pedido ya se envió: sobre la pantalla de confirmación no hay
   * nada que refrescar. */
  pausado?: boolean;
}

/** Única fuente del catálogo público (precios + horarios) para toda la
 * página: el menú y el formulario de pedido leen de acá, así que el precio
 * que se muestra arriba y el que se cobra abajo salen literalmente del
 * mismo fetch y no pueden separarse.
 *
 * Se llama UNA sola vez, desde App — no desde cada componente que necesite
 * datos, o cada uno abriría su propio sondeo cada 30 segundos. */
export function useCatalogoPublico({ pausado = false }: Opciones = {}): CatalogoPublico {
  const [productos, setProductos] = useState<ProductoPublico[]>([]);
  const [horarios, setHorarios] = useState<HorariosPanaderia | null>(null);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);
  // El aviso de nombres que no cruzan se da una sola vez por sesión, no en
  // cada ciclo del sondeo.
  const yaAvisoDeNombres = useRef(false);

  const aplicar = useCallback((lista: ProductoPublico[], horariosCatalogo: HorariosPanaderia) => {
    if (import.meta.env.DEV && !yaAvisoDeNombres.current) {
      const faltantes = nombresSinCoincidencia(lista, NOMBRES_CONFIGURADOS);
      if (faltantes.length > 0) {
        yaAvisoDeNombres.current = true;
        console.warn(
          `[catálogo] Estos nombres de src/data/config.ts no existen en el catálogo del servidor y ` +
            `por eso su pan no aparece en el formulario: ${faltantes.join(", ")}. ` +
            `El cruce es por texto exacto contra Productos.Nombre — revisa si lo renombraron en la app.`,
        );
      }
    }
    setProductos(filtrarProductosDelMenu(lista, NOMBRES_CONFIGURADOS));
    setHorarios(horariosCatalogo);
    setError(null);
  }, []);

  const cargar = useCallback(
    async (esReintento: boolean) => {
      if (esReintento) {
        setCargando(true);
        setError(null);
      }
      try {
        const { productos: lista, horarios: horariosCatalogo } = await obtenerCatalogoPublico();
        aplicar(lista, horariosCatalogo);
      } catch {
        setError(MENSAJE_ERROR);
      } finally {
        setCargando(false);
      }
    },
    [aplicar],
  );

  useEffect(() => {
    void cargar(false);
  }, [cargar]);

  // Sondeo silencioso: un refresco que falla (red, servidor despertando)
  // simplemente se reintenta en el próximo ciclo, sin tocar lo ya cargado
  // ni mostrarle un error a nadie.
  useEffect(() => {
    if (pausado) return;
    const id = window.setInterval(() => {
      obtenerCatalogoPublico()
        .then(({ productos: lista, horarios: horariosCatalogo }) => aplicar(lista, horariosCatalogo))
        .catch(() => {});
    }, INTERVALO_SONDEO_MS);
    return () => window.clearInterval(id);
  }, [pausado, aplicar]);

  const recargar = useCallback(() => void cargar(true), [cargar]);

  return { productos, horarios, cargando, error, recargar };
}
