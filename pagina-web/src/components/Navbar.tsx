import { useState } from "react";
import { motion, useMotionValueEvent, useScroll } from "framer-motion";
import { Menu as MenuIcon, X, User, Download } from "lucide-react";
import { SITE } from "../data/config";
import { desplazarASeccion } from "../utils/scroll";
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

export function Navbar() {
  const [abierto, setAbierto] = useState(false);
  const [conSombra, setConSombra] = useState(false);
  const [modalDescargaAbierto, setModalDescargaAbierto] = useState(false);
  const { scrollY } = useScroll();

  // Solo se eleva con sombra una vez que el contenido empieza a pasar por
  // debajo — recién ahí tiene sentido que se "despegue" visualmente.
  useMotionValueEvent(scrollY, "change", (valor) => {
    setConSombra(valor > 8);
  });

  return (
    <motion.header
      initial={{ opacity: 0, y: -16 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.5, ease: [0.16, 1, 0.3, 1] }}
      className={`fixed inset-x-0 top-0 z-50 border-b bg-pan-crema/85 backdrop-blur-md transition-shadow duration-300 ${
        conSombra
          ? "border-pan-borde shadow-md shadow-pan-carbon/5"
          : "border-pan-borde/60 shadow-none"
      }`}
    >
      <div className="mx-auto flex max-w-6xl items-center justify-between px-6 py-4">
        <a
          href="/"
          className="font-[family-name:var(--font-display-panaderia)] text-xl font-semibold text-pan-carbon transition-colors hover:text-pan-terracota"
        >
          {SITE.nombre}
        </a>

        <nav className="hidden items-center gap-8 md:flex">
          {ENLACES.map((enlace) => (
            <a
              key={enlace.href}
              href={enlace.href}
              onClick={(e) => {
                e.preventDefault();
                desplazarASeccion(enlace.href.slice(1));
              }}
              className="group relative text-sm font-medium text-pan-carbon-suave transition-colors hover:text-pan-terracota"
            >
              {enlace.texto}
              <span className="absolute -bottom-1 left-0 h-[1.5px] w-0 bg-pan-terracota transition-all duration-300 group-hover:w-full" />
            </a>
          ))}
          {/* app.panaderiaronceros.com es la app Flutter completa (login,
              mis pedidos, mis deudas, hacer pedido nuevo, cancelar) — se
              reusa tal cual en vez de duplicar esa lógica acá. */}
          <a
            href="https://app.panaderiaronceros.com/"
            className="inline-flex items-center gap-1.5 text-sm font-medium text-pan-carbon-suave transition-colors hover:text-pan-terracota"
          >
            <User className="h-4 w-4" />
            Iniciar sesión
          </a>
          {ES_ANDROID && (
            <button
              type="button"
              onClick={() => setModalDescargaAbierto(true)}
              className="boton-relleno inline-flex items-center gap-1.5 rounded-full border border-pan-borde bg-pan-crema-suave px-4 py-2 text-sm font-medium text-pan-carbon"
            >
              <Download className="h-4 w-4" />
              Descargar app
            </button>
          )}
          <a
            href="#pedido"
            onClick={(e) => {
              e.preventDefault();
              desplazarASeccion("pedido");
            }}
            className="rounded-full bg-pan-terracota px-5 py-2.5 text-sm font-semibold text-pan-crema transition-transform hover:scale-105"
          >
            Pedir ahora
          </a>
        </nav>

        <button
          onClick={() => setAbierto((v) => !v)}
          className="rounded-lg p-1 text-pan-carbon transition-colors hover:text-pan-terracota md:hidden"
          aria-label="Abrir menú"
        >
          {abierto ? <X className="h-6 w-6" /> : <MenuIcon className="h-6 w-6" />}
        </button>
      </div>

      {abierto && (
        <motion.nav
          initial={{ opacity: 0, height: 0 }}
          animate={{ opacity: 1, height: "auto" }}
          exit={{ opacity: 0, height: 0 }}
          className="flex flex-col gap-1 border-t border-pan-borde/60 px-6 py-4 md:hidden"
        >
          {ENLACES.map((enlace) => (
            <a
              key={enlace.href}
              href={enlace.href}
              onClick={(e) => {
                e.preventDefault();
                setAbierto(false);
                desplazarASeccion(enlace.href.slice(1));
              }}
              className="rounded-lg px-3 py-2.5 text-sm font-medium text-pan-carbon-suave transition-colors hover:bg-pan-crema-muted"
            >
              {enlace.texto}
            </a>
          ))}
          <a
            href="https://app.panaderiaronceros.com/"
            onClick={() => setAbierto(false)}
            className="rounded-lg px-3 py-2.5 text-sm font-medium text-pan-carbon-suave hover:bg-pan-crema-muted"
          >
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
              <Download className="h-4 w-4" />
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
        </motion.nav>
      )}

      <DescargarAppModal abierto={modalDescargaAbierto} onCerrar={() => setModalDescargaAbierto(false)} />
    </motion.header>
  );
}
