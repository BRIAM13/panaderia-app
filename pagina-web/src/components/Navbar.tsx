import { useState } from "react";
import { motion } from "framer-motion";
import { Menu as MenuIcon, X, User } from "lucide-react";
import { SITE } from "../data/config";

const ENLACES = [
  { href: "#nosotros", texto: "Nosotros" },
  { href: "#menu", texto: "Nuestro pan" },
  { href: "#pedido", texto: "Hacer un pedido" },
  { href: "#ubicacion", texto: "Ubicación" },
];

export function Navbar() {
  const [abierto, setAbierto] = useState(false);

  return (
    <motion.header
      initial={{ opacity: 0, y: -16 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.5, ease: [0.16, 1, 0.3, 1] }}
      className="fixed inset-x-0 top-0 z-50 border-b border-pan-bronce-suave/60 bg-pan-crema/85 backdrop-blur-md"
    >
      <div className="mx-auto flex max-w-6xl items-center justify-between px-6 py-4">
        <a
          href="#"
          className="font-[family-name:var(--font-display-panaderia)] text-xl font-semibold text-pan-carbon"
        >
          {SITE.nombre}
        </a>

        <nav className="hidden items-center gap-8 md:flex">
          {ENLACES.map((enlace) => (
            <a
              key={enlace.href}
              href={enlace.href}
              className="text-sm font-medium text-pan-carbon-suave transition-colors hover:text-pan-terracota"
            >
              {enlace.texto}
            </a>
          ))}
          {/* /app/ es la app Flutter completa (login, mis pedidos, mis
              deudas, hacer pedido nuevo, cancelar) — se reusa tal cual en
              vez de duplicar esa lógica acá. */}
          <a
            href="/app/"
            className="inline-flex items-center gap-1.5 text-sm font-medium text-pan-carbon-suave transition-colors hover:text-pan-terracota"
          >
            <User className="h-4 w-4" />
            Iniciar sesión
          </a>
          <a
            href="#pedido"
            className="rounded-full bg-pan-terracota px-5 py-2.5 text-sm font-semibold text-pan-crema transition-transform hover:scale-105"
          >
            Pedir ahora
          </a>
        </nav>

        <button
          onClick={() => setAbierto((v) => !v)}
          className="text-pan-carbon md:hidden"
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
          className="flex flex-col gap-1 border-t border-pan-bronce-suave/60 px-6 py-4 md:hidden"
        >
          {ENLACES.map((enlace) => (
            <a
              key={enlace.href}
              href={enlace.href}
              onClick={() => setAbierto(false)}
              className="rounded-lg px-3 py-2.5 text-sm font-medium text-pan-carbon-suave hover:bg-pan-crema-muted"
            >
              {enlace.texto}
            </a>
          ))}
          <a
            href="/app/"
            onClick={() => setAbierto(false)}
            className="rounded-lg px-3 py-2.5 text-sm font-medium text-pan-carbon-suave hover:bg-pan-crema-muted"
          >
            Iniciar sesión
          </a>
          <a
            href="#pedido"
            onClick={() => setAbierto(false)}
            className="mt-2 rounded-full bg-pan-terracota px-5 py-2.5 text-center text-sm font-semibold text-pan-crema"
          >
            Pedir ahora
          </a>
        </motion.nav>
      )}
    </motion.header>
  );
}
