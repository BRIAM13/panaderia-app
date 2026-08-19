import { SITE, UBICACION } from "../data/config";

export function Footer() {
  return (
    <footer id="pie-de-pagina" className="relative border-t border-pan-bronce-suave/60 bg-pan-crema px-6 py-10">
      <div className="absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-pan-terracota/40 to-transparent" />
      <div className="mx-auto flex max-w-6xl flex-col items-center justify-between gap-4 text-sm text-pan-carbon-suave sm:flex-row">
        <p>
          © {new Date().getFullYear()} {SITE.nombre}, {UBICACION.direccion}, {UBICACION.ciudad}
        </p>
        <a href="/privacidad/" className="text-pan-carbon-suave transition-colors hover:text-pan-terracota">
          Política de privacidad
        </a>
      </div>
      <p className="mx-auto mt-4 max-w-6xl text-center text-xs text-pan-carbon-suave">
        {SITE.nombre} opera bajo {SITE.nombreComercial} · RUC {SITE.ruc}
      </p>
    </footer>
  );
}
