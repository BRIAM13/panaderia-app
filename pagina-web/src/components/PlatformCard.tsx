import { useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { QRCodeSVG } from "qrcode.react";
import { Smartphone, Laptop, Globe, Download, ExternalLink, Clock, Lock } from "lucide-react";
import type { PlataformaDescarga } from "../data/config";

const ICONOS: Record<PlataformaDescarga["id"], React.ComponentType<{ className?: string }>> = {
  android: Smartphone,
  ios: Smartphone,
  windows: Laptop,
  macos: Laptop,
  web: Globe,
};

const EASE_PREMIUM = [0.16, 1, 0.3, 1] as const;

export function PlatformCard({
  plataforma,
  destacado,
}: {
  plataforma: PlataformaDescarga;
  destacado: boolean;
}) {
  const [abierto, setAbierto] = useState(false);
  const Icono = ICONOS[plataforma.id];
  const disponible = plataforma.estado === "disponible";

  // "archivo" puede ser una ruta propia del sitio (ej. la app Web en
  // /app/) o una URL externa completa (ej. el .apk en GitHub Releases) —
  // solo se antepone el origen del sitio cuando es relativa.
  const esUrlAbsoluta = plataforma.archivo?.startsWith("http");
  const urlDescarga =
    typeof window !== "undefined" && plataforma.archivo
      ? esUrlAbsoluta
        ? plataforma.archivo
        : window.location.origin + plataforma.archivo
      : (plataforma.archivo ?? "");

  return (
    <motion.div
      layout
      transition={{ duration: 0.4, ease: EASE_PREMIUM }}
      className={`overflow-hidden rounded-2xl border bg-carbon-900 ${
        destacado ? "border-neon-green/50 shadow-[0_0_40px_-15px_rgba(57,255,176,0.35)]" : "border-carbon-700"
      }`}
    >
      <button
        onClick={() => disponible && setAbierto((v) => !v)}
        className={`flex w-full items-center gap-4 p-5 text-left ${disponible ? "cursor-pointer" : "cursor-default"}`}
      >
        <div
          className={`flex h-11 w-11 shrink-0 items-center justify-center rounded-xl ${
            disponible ? "bg-neon-green/10 text-neon-green" : "bg-carbon-800 text-carbon-400"
          }`}
        >
          <Icono className="h-5 w-5" />
        </div>

        <div className="flex-1">
          <div className="flex items-center gap-2">
            <h3 className="font-[family-name:var(--font-display)] font-semibold text-white">
              {plataforma.nombre}
            </h3>
            {destacado && (
              <span className="rounded-full bg-neon-green/15 px-2 py-0.5 text-[10px] font-medium text-neon-green">
                tu dispositivo
              </span>
            )}
          </div>
          <p className="mt-0.5 text-sm text-carbon-400">{plataforma.descripcionEstado}</p>
        </div>

        {disponible ? (
          plataforma.tipoAccion === "abrir" ? (
            <ExternalLink className="h-4 w-4 shrink-0 text-carbon-400" />
          ) : (
            <Download className="h-4 w-4 shrink-0 text-carbon-400" />
          )
        ) : plataforma.estado === "en-camino" ? (
          <Clock className="h-4 w-4 shrink-0 text-carbon-400" />
        ) : (
          <Lock className="h-4 w-4 shrink-0 text-carbon-400" />
        )}
      </button>

      <AnimatePresence>
        {abierto && disponible && (
          <motion.div
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: "auto", opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            transition={{ duration: 0.35, ease: EASE_PREMIUM }}
          >
            <div className="flex flex-col items-center gap-4 border-t border-carbon-700 p-6">
              {plataforma.viaQr ? (
                <>
                  <div className="rounded-xl bg-white p-3">
                    <QRCodeSVG value={urlDescarga} size={140} />
                  </div>
                  <p className="text-center text-xs text-carbon-400">
                    {plataforma.tipoAccion === "abrir"
                      ? "Escanea con tu celular para abrirla ahí"
                      : `Escanea con tu celular para descargar ${plataforma.nombreArchivo}`}
                  </p>
                </>
              ) : null}
              {plataforma.tipoAccion === "abrir" ? (
                <a
                  href={plataforma.archivo ?? "#"}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center gap-2 rounded-full bg-gradient-to-r from-neon-green to-cyber-violet px-5 py-2.5 text-sm font-semibold text-carbon-950 transition-transform hover:scale-105"
                >
                  <ExternalLink className="h-4 w-4" />
                  Abrir la app web
                </a>
              ) : (
                <a
                  href={plataforma.archivo ?? "#"}
                  download
                  className="inline-flex items-center gap-2 rounded-full bg-gradient-to-r from-neon-green to-cyber-violet px-5 py-2.5 text-sm font-semibold text-carbon-950 transition-transform hover:scale-105"
                >
                  <Download className="h-4 w-4" />
                  Descargar {plataforma.nombreArchivo}
                </a>
              )}
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </motion.div>
  );
}
