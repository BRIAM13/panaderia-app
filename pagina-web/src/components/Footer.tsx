import { SITE, UBICACION } from "../data/config";

export function Footer() {
  return (
    <footer className="border-t border-pan-bronce-suave/60 bg-pan-crema px-6 py-10">
      <div className="mx-auto flex max-w-6xl flex-col items-center justify-between gap-4 text-sm text-pan-carbon-suave sm:flex-row">
        <p>
          © {new Date().getFullYear()} {SITE.nombre} — {UBICACION.direccion}, {UBICACION.ciudad}
        </p>
        <a href="/privacidad/" className="text-pan-carbon-suave hover:text-pan-terracota">
          Política de privacidad
        </a>
      </div>
    </footer>
  );
}
