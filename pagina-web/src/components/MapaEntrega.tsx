import { useEffect, useRef, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { AlertTriangle, Crosshair, Loader2, MapPin } from "lucide-react";
import * as L from "leaflet";
import "leaflet/dist/leaflet.css";
import { EASE_PREMIUM } from "../utils/animacion";
import {
  CENTRO_MAPA_POR_DEFECTO,
  ZOOM_CON_PIN,
  ZOOM_INICIAL_MAPA,
  textoErrorGeolocalizacion,
  textoPrecisionUbicacion,
  type Coordenadas,
} from "../utils/entrega";

/**
 * Tiles de OpenStreetMap, servidos por la propia fundación. Sin llave de API
 * ni cuenta de pago (a diferencia de Google Maps JavaScript API, que exige
 * tarjeta aunque el uso sea gratuito). La atribución de abajo es
 * OBLIGATORIA por la política de uso de OSM — no quitarla.
 */
const URL_TILES = "https://tile.openstreetmap.org/{z}/{x}/{y}.png";
const ATRIBUCION_TILES = '&copy; <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">OpenStreetMap</a>';

/**
 * El pin, dibujado en SVG con el terracota de la marca. Leaflet trae un pin
 * azul por defecto en PNG, pero sus rutas se rompen al pasar por el bundler
 * (hay que reconfigurarlas a mano) y además no es de la paleta. Un `divIcon`
 * con el SVG inline evita las dos cosas. La punta queda exactamente en la
 * coordenada (`iconAnchor` = abajo al centro).
 */
const ICONO_PIN = L.divIcon({
  className: "pin-entrega",
  html: `<svg xmlns="http://www.w3.org/2000/svg" width="36" height="46" viewBox="0 0 36 46" aria-hidden="true" style="display:block;filter:drop-shadow(0 4px 6px rgba(43,33,24,0.35))">
    <path d="M18 1C8.6 1 1 8.5 1 17.8 1 30.4 18 45 18 45s17-14.6 17-27.2C35 8.5 27.4 1 18 1z" fill="#b5451b" stroke="#fffbf3" stroke-width="2"/>
    <circle cx="18" cy="17.5" r="6" fill="#fffbf3"/>
  </svg>`,
  iconSize: [36, 46],
  iconAnchor: [18, 45],
});

/** Cuánto esperar al GPS antes de darse por vencidos. Diez segundos: más que
 * eso y el cliente ya cree que el botón no hizo nada. */
const TIEMPO_MAXIMO_GEOLOCALIZACION_MS = 10_000;

interface MapaEntregaProps {
  /** El pin puesto, o null si todavía no marcó nada. */
  valor: Coordenadas | null;
  onChange: (coordenadas: Coordenadas) => void;
}

/**
 * El mapa donde el cliente marca dónde entregar: toca para poner el pin,
 * lo arrastra para afinarlo, o pide "Usar mi ubicación actual". Es un
 * componente CONTROLADO: el pin que se ve es siempre `valor`, y cualquier
 * cambio (toque, arrastre, GPS) sale por `onChange`.
 *
 * La geolocalización NUNCA se pide sola al montar: solo cuando el cliente
 * toca el botón. Un permiso de ubicación pedido sin que nadie lo haya pedido
 * es la forma más rápida de que lo nieguen para siempre — y además el mapa
 * funciona perfectamente sin él.
 *
 * Se carga de forma diferida desde PedidoForm (Leaflet pesa ~40 KB gz y
 * solo hace falta si el cliente elige delivery).
 */
export function MapaEntrega({ valor, onChange }: MapaEntregaProps) {
  const contenedorRef = useRef<HTMLDivElement>(null);
  const mapaRef = useRef<L.Map | null>(null);
  const pinRef = useRef<L.Marker | null>(null);
  // `onChange` cambia de identidad en cada render del padre; los listeners
  // de Leaflet se registran una sola vez, así que leen siempre la última
  // versión desde acá.
  const onChangeRef = useRef(onChange);
  onChangeRef.current = onChange;

  const [buscandoUbicacion, setBuscandoUbicacion] = useState(false);
  const [avisoUbicacion, setAvisoUbicacion] = useState<{ texto: string; tono: "error" | "atencion" } | null>(null);

  // Crear el mapa UNA vez por montaje y destruirlo al salir — Leaflet no
  // sobrevive a que React le vuelva a montar el mismo div.
  useEffect(() => {
    const contenedor = contenedorRef.current;
    if (!contenedor || mapaRef.current) return;

    const centro = valor ?? CENTRO_MAPA_POR_DEFECTO;
    const mapa = L.map(contenedor, {
      center: [centro.latitud, centro.longitud],
      zoom: valor ? ZOOM_CON_PIN : ZOOM_INICIAL_MAPA,
      // Sin zoom con la rueda: el mapa vive dentro de un formulario largo y
      // la rueda tiene que seguir siendo "bajar la página", no acercar el
      // mapa por accidente. Quedan los botones +/− y el pellizco en táctil.
      scrollWheelZoom: false,
      // La atribución es obligatoria (OSM), pero sin el prefijo "Leaflet" que
      // viene por defecto: solo el crédito que de verdad corresponde.
      attributionControl: false,
    });
    L.control.attribution({ prefix: false }).addTo(mapa);
    L.tileLayer(URL_TILES, { maxZoom: 19, attribution: ATRIBUCION_TILES }).addTo(mapa);

    mapa.on("click", (evento: L.LeafletMouseEvent) => {
      onChangeRef.current(redondear(evento.latlng));
    });

    mapaRef.current = mapa;

    // El contenedor entra animado en alto (ver el bloque de delivery en
    // PedidoForm): Leaflet mide el tamaño al crearse y, si en ese momento
    // medía 0, los tiles quedan recortados. Cada cambio de tamaño le avisa.
    const observador = new ResizeObserver(() => mapa.invalidateSize({ animate: false }));
    observador.observe(contenedor);

    return () => {
      observador.disconnect();
      mapa.remove();
      mapaRef.current = null;
      pinRef.current = null;
    };
    // `valor` solo decide el encuadre INICIAL; los cambios siguientes los
    // maneja el efecto de abajo.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Sincronizar el pin con `valor`: crearlo la primera vez, moverlo después.
  useEffect(() => {
    const mapa = mapaRef.current;
    if (!mapa || !valor) return;
    const posicion: L.LatLngExpression = [valor.latitud, valor.longitud];

    if (!pinRef.current) {
      const pin = L.marker(posicion, {
        icon: ICONO_PIN,
        draggable: true,
        keyboard: false,
        title: "Lugar de entrega. Arrástralo para ajustarlo.",
      }).addTo(mapa);
      pin.on("dragend", () => {
        onChangeRef.current(redondear(pin.getLatLng()));
      });
      pinRef.current = pin;
      // Primer pin: acercar a nivel de cuadra para que pueda afinarlo.
      mapa.flyTo(posicion, Math.max(mapa.getZoom(), ZOOM_CON_PIN), { duration: 0.6 });
      return;
    }

    const actual = pinRef.current.getLatLng();
    if (actual.lat !== valor.latitud || actual.lng !== valor.longitud) {
      pinRef.current.setLatLng(posicion);
      // Si el pin se movió desde afuera (GPS), llevar la vista hasta él. Un
      // arrastre a mano ya lo tiene a la vista y esto no hace nada visible.
      if (!mapa.getBounds().contains(posicion)) {
        mapa.flyTo(posicion, Math.max(mapa.getZoom(), ZOOM_CON_PIN), { duration: 0.6 });
      }
    }
  }, [valor]);

  function usarUbicacionActual() {
    setAvisoUbicacion(null);
    // `isSecureContext` falso = la página está en http:// y no en localhost:
    // los navegadores apagan la geolocalización ahí sin decir por qué.
    if (typeof navigator === "undefined" || !("geolocation" in navigator) || !window.isSecureContext) {
      setAvisoUbicacion({ texto: textoErrorGeolocalizacion(null), tono: "error" });
      return;
    }
    setBuscandoUbicacion(true);
    navigator.geolocation.getCurrentPosition(
      (posicion) => {
        setBuscandoUbicacion(false);
        const { latitude, longitude, accuracy } = posicion.coords;
        onChangeRef.current(redondear({ lat: latitude, lng: longitude }));
        const mapa = mapaRef.current;
        if (mapa) mapa.flyTo([latitude, longitude], ZOOM_CON_PIN, { duration: 0.8 });
        const avisoPrecision = textoPrecisionUbicacion(accuracy);
        setAvisoUbicacion(avisoPrecision ? { texto: avisoPrecision, tono: "atencion" } : null);
      },
      (error) => {
        setBuscandoUbicacion(false);
        setAvisoUbicacion({ texto: textoErrorGeolocalizacion(error.code), tono: "error" });
      },
      { enableHighAccuracy: true, timeout: TIEMPO_MAXIMO_GEOLOCALIZACION_MS, maximumAge: 0 },
    );
  }

  return (
    <div>
      {/* `isolate` encierra los z-index internos de Leaflet (llegan hasta
          1000) para que los controles del mapa nunca se dibujen por encima
          del navbar fijo ni de las hojas emergentes de los selectores. */}
      <div className="relative isolate overflow-hidden rounded-2xl border border-pan-borde/50 shadow-sm shadow-pan-carbon/5">
        <div
          ref={contenedorRef}
          role="application"
          aria-label="Mapa para marcar el lugar de entrega. Toca el mapa para poner el pin y arrástralo para ajustarlo."
          className="h-64 w-full bg-pan-crema-muted sm:h-72"
        />
        {/* Pista flotante mientras no hay pin: desaparece sola al ponerlo.
            No bloquea toques (`pointer-events-none`), así el cliente puede
            tocar justo debajo de ella. */}
        <AnimatePresence>
          {!valor && (
            <motion.div
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: 8 }}
              transition={{ duration: 0.3, ease: EASE_PREMIUM }}
              className="pointer-events-none absolute inset-x-0 bottom-3 z-[1000] flex justify-center px-3"
            >
              <span className="inline-flex items-center gap-1.5 rounded-full border border-pan-borde/40 bg-pan-crema-suave/95 px-3.5 py-1.5 text-xs font-medium text-pan-carbon shadow-md shadow-pan-carbon/10 backdrop-blur-sm">
                <MapPin className="h-3.5 w-3.5 text-pan-terracota" strokeWidth={2} />
                Toca el mapa para poner el pin
              </span>
            </motion.div>
          )}
        </AnimatePresence>
      </div>

      <div className="mt-2.5 flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
        <motion.button
          type="button"
          onClick={usarUbicacionActual}
          disabled={buscandoUbicacion}
          whileTap={buscandoUbicacion ? undefined : { scale: 0.98 }}
          className="boton-relleno inline-flex min-h-11 items-center justify-center gap-2 rounded-full border border-pan-borde bg-pan-crema-suave px-4 py-2 text-sm font-semibold text-pan-carbon shadow-sm shadow-pan-carbon/5 disabled:opacity-60 sm:w-auto"
          style={
            {
              "--color-relleno": "var(--color-pan-crema-muted)",
              "--color-relleno-texto": "var(--color-pan-carbon)",
            } as React.CSSProperties
          }
        >
          {buscandoUbicacion ? (
            <>
              <Loader2 className="h-4 w-4 animate-spin text-pan-terracota" />
              Buscando tu ubicación…
            </>
          ) : (
            <>
              <Crosshair className="h-4 w-4 text-pan-terracota" strokeWidth={2} />
              Usar mi ubicación actual
            </>
          )}
        </motion.button>
        <p className="text-xs leading-relaxed text-pan-carbon-suave sm:max-w-[16rem] sm:text-right">
          {valor
            ? "Pin puesto. Arrástralo si no quedó justo sobre tu casa."
            : "Te pediremos permiso solo si tocas el botón."}
        </p>
      </div>

      <AnimatePresence>
        {avisoUbicacion && (
          <motion.div
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: "auto" }}
            exit={{ opacity: 0, height: 0 }}
            transition={{ duration: 0.25, ease: EASE_PREMIUM }}
            className="overflow-hidden"
            role="status"
            aria-live="polite"
          >
            <div
              className={`mt-2 flex items-start gap-2.5 rounded-xl border px-4 py-3 ${
                avisoUbicacion.tono === "error" ? "border-red-200 bg-red-50" : "border-amber-300 bg-amber-50"
              }`}
            >
              <AlertTriangle
                className={`mt-0.5 h-4 w-4 shrink-0 ${
                  avisoUbicacion.tono === "error" ? "text-red-600" : "text-amber-600"
                }`}
                strokeWidth={1.75}
              />
              <p
                className={`text-xs leading-relaxed font-medium ${
                  avisoUbicacion.tono === "error" ? "text-red-700" : "text-amber-800"
                }`}
              >
                {avisoUbicacion.texto}
              </p>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

/** 7 decimales (~1 cm), los mismos que guarda el backend: evita mandar
 * colas de punto flotante de 15 dígitos que no aportan nada. */
function redondear(punto: { lat: number; lng: number }): Coordenadas {
  return {
    latitud: Number(punto.lat.toFixed(7)),
    longitud: Number(punto.lng.toFixed(7)),
  };
}
