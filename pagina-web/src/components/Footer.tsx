import { SITE } from "../data/config";

export function Footer() {
  return (
    <footer className="border-t border-carbon-800 px-6 py-10">
      <div className="mx-auto flex max-w-6xl flex-col items-center justify-between gap-4 text-sm text-carbon-400 sm:flex-row">
        <p>
          © {new Date().getFullYear()} {SITE.nombre} — {SITE.claim}
        </p>
        <p className="text-carbon-600">Hecho con Flutter, Node.js y Azure SQL.</p>
      </div>
    </footer>
  );
}
