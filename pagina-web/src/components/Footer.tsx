import { SITE, UBICACION } from "../data/config";

export function Footer() {
  return (
    <footer id="pie-de-pagina" className="relative border-t border-pan-borde/60 bg-pan-crema px-6 py-10">
      <div className="absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-pan-terracota/40 to-transparent" />
      <div className="mx-auto flex max-w-6xl flex-col items-center justify-between gap-4 text-sm text-pan-carbon-suave sm:flex-row">
        <p>
          © {new Date().getFullYear()} {SITE.nombre} — {UBICACION.direccion}, {UBICACION.ciudad}
        </p>
        <a
          href="/privacidad/"
          className="font-medium text-pan-carbon-suave transition-colors hover:text-pan-terracota"
        >
          Política de privacidad
        </a>
      </div>
      <div className="mx-auto mt-6 max-w-6xl border-t border-pan-borde/30 pt-4 text-center">
        <p className="text-xs text-pan-carbon-suave">
          {SITE.nombre} opera bajo {SITE.nombreComercial} · RUC {SITE.ruc}
        </p>
      </div>
    </footer>
  );
}
