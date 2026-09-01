import { ExternalLink, MapPin, User } from "lucide-react";
import { SITE, UBICACION } from "../data/config";
import { desplazarASeccion } from "../utils/scroll";

const ENLACES_SECCIONES = [
  { id: "nosotros", texto: "Nosotros" },
  { id: "menu", texto: "Nuestro pan" },
  { id: "pedido", texto: "Hacer un pedido" },
  { id: "ubicacion", texto: "Ubicación" },
];

/** Cierre de la página. Antes era una sola línea de copyright: se veía
 * como el final abrupto de un sitio que hasta ahí venía muy cuidado. Ahora
 * repite la marca, deja a mano la navegación y la dirección, y recién
 * abajo del todo pone la letra chica legal — sin inventar ningún dato que
 * el negocio no tenga (no hay teléfono ni redes en data/config.ts, así que
 * no se muestran). */
export function Footer() {
  return (
    <footer id="pie-de-pagina" className="relative border-t border-pan-borde/60 bg-pan-crema px-6 pt-14 pb-10">
      <div className="absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-pan-terracota/40 to-transparent" />

      <div className="mx-auto grid max-w-6xl gap-10 sm:grid-cols-2 lg:grid-cols-4">
        <div className="lg:col-span-2">
          <p className="flex items-center gap-2.5 font-[family-name:var(--font-display-panaderia)] text-xl font-semibold text-pan-carbon">
            <span
              aria-hidden="true"
              className="flex h-9 w-9 items-center justify-center rounded-xl bg-gradient-to-br from-pan-terracota to-pan-terracota-profundo text-sm font-bold text-pan-crema shadow-sm shadow-pan-terracota/25"
            >
              PR
            </span>
            {SITE.nombre}
          </p>
          <p className="mt-4 max-w-sm text-sm leading-relaxed text-pan-carbon-suave">{SITE.claim}.</p>
          <p className="mt-3 max-w-sm text-sm leading-relaxed text-pan-carbon-suave">
            Horneamos temprano cada mañana para que el pan llegue caliente a la mesa de nuestros
            vecinos en Pisco.
          </p>
        </div>

        <nav aria-label="Secciones del sitio">
          <p className="text-xs font-semibold tracking-[0.16em] text-pan-carbon uppercase">Secciones</p>
          {/* En pantallas táctiles cada enlace ocupa una fila de 44px con su
              propio relleno (antes eran 20px de texto con 10px de aire: se
              tocaba el enlace de al lado con facilidad). Desde lg, donde se
              navega con mouse, vuelve al ritmo compacto original. */}
          <ul className="mt-3 space-y-0.5 lg:mt-4 lg:space-y-2.5">
            {ENLACES_SECCIONES.map((enlace) => (
              <li key={enlace.id}>
                <a
                  href={`#${enlace.id}`}
                  onClick={(e) => {
                    e.preventDefault();
                    desplazarASeccion(enlace.id);
                  }}
                  className="group inline-flex min-h-11 items-center gap-1.5 rounded text-sm text-pan-carbon-suave transition-colors hover:text-pan-terracota lg:min-h-0"
                >
                  <span
                    aria-hidden="true"
                    className="h-px w-0 bg-pan-terracota transition-all duration-300 group-hover:w-3"
                  />
                  {enlace.texto}
                </a>
              </li>
            ))}
          </ul>
        </nav>

        <div>
          <p className="text-xs font-semibold tracking-[0.16em] text-pan-carbon uppercase">Encuéntranos</p>
          <address className="mt-4 space-y-3 text-sm text-pan-carbon-suave not-italic">
            <a
              href={UBICACION.mapaUrl}
              target="_blank"
              rel="noopener noreferrer"
              className="group flex items-start gap-2 rounded transition-colors hover:text-pan-terracota"
            >
              <MapPin className="mt-0.5 h-4 w-4 shrink-0 text-pan-terracota" strokeWidth={1.75} />
              <span>
                {UBICACION.direccion}
                <br />
                {UBICACION.ciudad}
                <ExternalLink className="ml-1.5 inline h-3 w-3 opacity-0 transition-opacity group-hover:opacity-100" />
              </span>
            </a>
            <a
              href="https://app.panaderiaronceros.com/"
              className="flex min-h-11 items-center gap-2 rounded transition-colors hover:text-pan-terracota lg:min-h-0"
            >
              <User className="h-4 w-4 shrink-0 text-pan-terracota" strokeWidth={1.75} />
              Entrar a mi cuenta
            </a>
          </address>
        </div>
      </div>

      <div className="mx-auto mt-12 flex max-w-6xl flex-col items-center justify-between gap-3 border-t border-pan-borde/30 pt-6 text-center text-xs text-pan-carbon-suave sm:flex-row sm:text-left">
        <p>
          © {new Date().getFullYear()} {SITE.nombre} · opera bajo {SITE.nombreComercial} · RUC {SITE.ruc}
        </p>
        <a
          href="/privacidad/"
          className="inline-flex min-h-11 items-center rounded font-medium text-pan-carbon-suave transition-colors hover:text-pan-terracota lg:min-h-0"
        >
          Política de privacidad
        </a>
      </div>
    </footer>
  );
}
