import { SITE } from "../data/config";

export function Footer() {
  return (
    <footer className="border-t border-carbon-800 px-6 py-10">
      <div className="mx-auto flex max-w-6xl flex-col items-center justify-between gap-4 text-sm text-carbon-400 sm:flex-row">
        <p>
          © {new Date().getFullYear()} {SITE.nombre} — {SITE.claim}
        </p>
        <a href="/privacidad/" className="text-carbon-400 hover:text-carbon-200">
          Política de privacidad
        </a>
      </div>
    </footer>
  );
}
