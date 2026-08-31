import { useEffect, useState } from "react";
import { AnimatePresence, motion, useMotionValueEvent, useScroll } from "framer-motion";
import { Menu as MenuIcon, X, User, Download } from "lucide-react";
import { SITE } from "../data/config";
import { desplazarASeccion } from "../utils/scroll";
import { EASE_PREMIUM } from "../utils/animacion";
import { DescargarAppModal } from "./DescargarAppModal";

const ENLACES = [
  { href: "#nosotros", texto: "Nosotros" },
  { href: "#menu", texto: "Nuestro pan" },
  { href: "#pedido", texto: "Hacer un pedido" },
  { href: "#ubicacion", texto: "Ubicación" },
];

// La app instalable (.apk) solo tiene sentido ofrecerla a quien navega
// desde Android — en cualquier otro dispositivo el archivo no sirve de
// nada y solo confundiría.
const ES_ANDROID = typeof navigator !== "undefined" && /Android/i.test(navigator.userAgent);

/** Devuelve el id de la sección que el visitante está mirando ahora mismo.
 * Se usa un IntersectionObserver (no un cálculo de posiciones en cada
 * evento de scroll) para no hacer trabajo de layout en cada cuadro. El
 * recorte superior descuenta el alto del navbar fijo, y el inferior obliga
 * a que la sección esté realmente en la mitad superior de la pantalla
 * antes de considerarse "la actual". */
function useSeccionActiva(ids: string[]): string | null {
  const [activa, setActiva] = useState<string | null>(null);

  useEffect(() => {
    const secciones = ids
      .map((id) => document.getElementById(id))
      .filter((el): el is HTMLElement => el !== null);
    if (secciones.length === 0) return;

    const visibles = new Map<string, number>();
    const observador = new IntersectionObserver(
      (entradas) => {
        for (const entrada of entradas) {
          if (entrada.isIntersecting) visibles.set(entrada.target.id, entrada.intersectionRatio);
          else visibles.delete(entrada.target.id);
        }
        // Con varias secciones a la vista gana la que más superficie ocupa
        // dentro de la franja observada — así el resaltado no parpadea
        // entre dos vecinas al cruzar el límite.
        let mejor: string | null = null;
        let mejorRatio = 0;
        for (const [id, ratio] of visibles) {
          if (ratio > mejorRatio) {
            mejor = id;
            mejorRatio = ratio;
          }
        }
        setActiva(mejor);
      },
      { rootMargin: "-80px 0px -55% 0px", threshold: [0.05, 0.25, 0.5, 0.75, 1] },
    );

    secciones.forEach((seccion) => observador.observe(seccion));
    return () => observador.disconnect();
  }, [ids]);

  return activa;
}

const IDS_SECCIONES = ENLACES.map((e) => e.href.slice(1));

export function Navbar() {
  const [abierto, setAbierto] = useState(false);
  const [conSombra, setConSombra] = useState(false);
  const [modalDescargaAbierto, setModalDescargaAbierto] = useState(false);
  const { scrollY } = useScroll();
  const seccionActiva = useSeccionActiva(IDS_SECCIONES);

  // Solo se eleva con sombra una vez que el contenido empieza a pasar por
  // debajo — recién ahí tiene sentido que se "despegue" visualmente.
  useMotionValueEvent(scrollY, "change", (valor) => {
    setConSombra(valor > 8);
  });

  // El menú móvil se cierra con Escape (lo que cualquiera espera de un
  // panel desplegado) y deja de poder desplazarse el fondo mientras está
  // abierto, para que el gesto de scroll no mueva la página por debajo.
  useEffect(() => {
    if (!abierto) return;
    const alPresionar = (e: KeyboardEvent) => {
      if (e.key === "Escape") setAbierto(false);
    };
    window.addEventListener("keydown", alPresionar);
    return () => window.removeEventListener("keydown", alPresionar);
  }, [abierto]);

  return (
    <motion.header
      initial={{ opacity: 0, y: -16 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.5, ease: EASE_PREMIUM }}
      className={`fixed inset-x-0 top-0 z-50 border-b bg-pan-crema/85 backdrop-blur-md transition-shadow duration-300 ${
        conSombra
          ? "border-pan-borde shadow-md shadow-pan-carbon/5"
          : "border-pan-borde/60 shadow-none"
      }`}
    >
      <div className="mx-auto flex max-w-6xl items-center justify-between px-6 py-4">
        <a
          href="/"
          className="group flex items-center gap-2.5 rounded-lg font-[family-name:var(--font-display-panaderia)] text-xl font-semibold text-pan-carbon transition-colors hover:text-pan-terracota"
        >
          {/* Sello de la marca: las iniciales dentro de un cuadro cálido.
              El logotipo era solo texto y la barra se veía vacía a la
              izquierda frente al peso de la navegación a la derecha. */}
          <span
            aria-hidden="true"
            className="flex h-9 w-9 items-center justify-center rounded-xl bg-gradient-to-br from-pan-terracota to-pan-terracota-profundo text-sm font-bold text-pan-crema shadow-sm shadow-pan-terracota/25 transition-transform duration-300 group-hover:-rotate-6"
          >
            PR
          </span>
          {SITE.nombre}
        </a>

        <nav className="hidden items-center gap-8 md:flex">
          {ENLACES.map((enlace) => {
            const activo = seccionActiva === enlace.href.slice(1);
            return (
              <a
                key={enlace.href}
                href={enlace.href}
                onClick={(e) => {
                  e.preventDefault();
                  desplazarASeccion(enlace.href.slice(1));
                }}
                aria-current={activo ? "true" : undefined}
                className={`group relative rounded text-sm font-medium transition-colors ${
                  activo ? "text-pan-terracota" : "text-pan-carbon-suave hover:text-pan-terracota"
                }`}
              >
                {enlace.texto}
                {/* Dos subrayados distintos a propósito: el del hover crece
                    desde la izquierda en cada enlace, y el de la sección
                    actual se DESLIZA de un enlace al siguiente (layoutId)
                    conforme avanza el scroll — así el visitante siempre
                    sabe en qué parte de la página está. */}
                {activo ? (
                  <motion.span
                    layoutId="navbar-seccion-activa"
                    transition={{ duration: 0.4, ease: EASE_PREMIUM }}
                    className="absolute -bottom-1 left-0 h-[1.5px] w-full bg-pan-terracota"
                  />
                ) : (
                  <span className="absolute -bottom-1 left-0 h-[1.5px] w-0 bg-pan-terracota/50 transition-all duration-300 group-hover:w-full" />
                )}
              </a>
            );
          })}
          {/* app.panaderiaronceros.com es la app Flutter completa (login,
              mis pedidos, mis deudas, hacer pedido nuevo, cancelar) — se
              reusa tal cual en vez de duplicar esa lógica acá. */}
          <a
            href="https://app.panaderiaronceros.com/"
            className="inline-flex items-center gap-1.5 rounded text-sm font-medium text-pan-carbon-suave transition-colors hover:text-pan-terracota"
          >
            <User className="h-4 w-4" strokeWidth={1.75} />
            Iniciar sesión
          </a>
          {ES_ANDROID && (
            <button
              type="button"
              onClick={() => setModalDescargaAbierto(true)}
              className="boton-relleno inline-flex items-center gap-1.5 rounded-full border border-pan-borde bg-pan-crema-suave px-4 py-2 text-sm font-medium text-pan-carbon"
            >
              <Download className="h-4 w-4" strokeWidth={1.75} />
              Descargar app
            </button>
          )}
          <motion.a
            href="#pedido"
            onClick={(e) => {
              e.preventDefault();
              desplazarASeccion("pedido");
            }}
            whileHover={{ scale: 1.05, y: -1 }}
            whileTap={{ scale: 0.97 }}
            className="rounded-full bg-pan-terracota px-5 py-2.5 text-sm font-semibold text-pan-crema shadow-sm shadow-pan-terracota/25 transition-shadow hover:shadow-md hover:shadow-pan-terracota/35"
          >
            Pedir ahora
          </motion.a>
        </nav>

        <button
          onClick={() => setAbierto((v) => !v)}
          className="rounded-lg p-1 text-pan-carbon transition-colors hover:text-pan-terracota md:hidden"
          aria-label={abierto ? "Cerrar menú" : "Abrir menú"}
          aria-expanded={abierto}
          aria-controls="menu-movil"
        >
          {/* El ícono cruza de hamburguesa a X con un giro, en vez de
              cambiar de golpe entre dos dibujos distintos. */}
          <AnimatePresence mode="wait" initial={false}>
            <motion.span
              key={abierto ? "cerrar" : "abrir"}
              initial={{ rotate: -90, opacity: 0 }}
              animate={{ rotate: 0, opacity: 1 }}
              exit={{ rotate: 90, opacity: 0 }}
              transition={{ duration: 0.2, ease: EASE_PREMIUM }}
              className="block"
            >
              {abierto ? <X className="h-6 w-6" /> : <MenuIcon className="h-6 w-6" />}
            </motion.span>
          </AnimatePresence>
        </button>
      </div>

      {/* Antes este panel no estaba envuelto en AnimatePresence, así que su
          `exit` nunca llegaba a ejecutarse: aparecía animado y desaparecía
          de golpe. */}
      <AnimatePresence initial={false}>
        {abierto && (
          <motion.nav
            id="menu-movil"
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: "auto" }}
            exit={{ opacity: 0, height: 0 }}
            transition={{ duration: 0.3, ease: EASE_PREMIUM }}
            className="overflow-hidden border-t border-pan-borde/60 md:hidden"
          >
            {/* Fondo propio, opaco: la barra de arriba es translúcida a
                propósito, pero un panel desplegado sin fondo dejaba leer
                el titular de la portada por detrás de sus enlaces. */}
            <div className="flex flex-col gap-1 bg-pan-crema px-6 py-4">
              {ENLACES.map((enlace) => {
                const activo = seccionActiva === enlace.href.slice(1);
                return (
                  <a
                    key={enlace.href}
                    href={enlace.href}
                    onClick={(e) => {
                      e.preventDefault();
                      setAbierto(false);
                      desplazarASeccion(enlace.href.slice(1));
                    }}
                    aria-current={activo ? "true" : undefined}
                    className={`rounded-lg px-3 py-2.5 text-sm font-medium transition-colors ${
                      activo
                        ? "bg-pan-terracota-suave/45 text-pan-terracota"
                        : "text-pan-carbon-suave hover:bg-pan-crema-muted"
                    }`}
                  >
                    {enlace.texto}
                  </a>
                );
              })}
              <a
                href="https://app.panaderiaronceros.com/"
                onClick={() => setAbierto(false)}
                className="flex items-center gap-1.5 rounded-lg px-3 py-2.5 text-sm font-medium text-pan-carbon-suave hover:bg-pan-crema-muted"
              >
                <User className="h-4 w-4" strokeWidth={1.75} />
                Iniciar sesión
              </a>
              {ES_ANDROID && (
                <button
                  type="button"
                  onClick={() => {
                    setAbierto(false);
                    setModalDescargaAbierto(true);
                  }}
                  className="flex items-center gap-1.5 rounded-lg px-3 py-2.5 text-left text-sm font-medium text-pan-carbon-suave hover:bg-pan-crema-muted"
                >
                  <Download className="h-4 w-4" strokeWidth={1.75} />
                  Descargar app
                </button>
              )}
              <a
                href="#pedido"
                onClick={(e) => {
                  e.preventDefault();
                  setAbierto(false);
                  desplazarASeccion("pedido");
                }}
                className="mt-2 rounded-full bg-pan-terracota px-5 py-2.5 text-center text-sm font-semibold text-pan-crema transition-opacity hover:opacity-90"
              >
                Pedir ahora
              </a>
            </div>
          </motion.nav>
        )}
      </AnimatePresence>

      <DescargarAppModal abierto={modalDescargaAbierto} onCerrar={() => setModalDescargaAbierto(false)} />
    </motion.header>
  );
}
