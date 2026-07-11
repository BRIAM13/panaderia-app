import { motion } from "framer-motion";
import type { OS } from "../data/config";

const OPCIONES: { id: OS; etiqueta: string }[] = [
  { id: "web", etiqueta: "Web" },
  { id: "android", etiqueta: "Android" },
  { id: "ios", etiqueta: "iOS" },
  { id: "windows", etiqueta: "Windows" },
  { id: "macos", etiqueta: "macOS" },
];

interface Props {
  activo: OS;
  onCambiar: (os: OS) => void;
}

export function PlatformSelector({ activo, onCambiar }: Props) {
  return (
    <div className="inline-flex flex-wrap justify-center gap-1 rounded-full border border-carbon-700 bg-carbon-900/80 p-1.5 backdrop-blur-sm">
      {OPCIONES.map((opcion) => {
        const seleccionado = opcion.id === activo;
        return (
          <button
            key={opcion.id}
            onClick={() => onCambiar(opcion.id)}
            onMouseEnter={() => onCambiar(opcion.id)}
            className="relative rounded-full px-4 py-2 text-sm font-medium text-carbon-200 transition-colors sm:px-5"
          >
            {seleccionado && (
              <motion.span
                layoutId="pastilla-activa"
                className="absolute inset-0 rounded-full bg-gradient-to-r from-neon-green/20 to-cyber-violet/20 ring-1 ring-neon-green/50"
                transition={{ type: "spring", stiffness: 300, damping: 30 }}
              />
            )}
            <span className={`relative z-10 ${seleccionado ? "text-white" : "text-carbon-400"}`}>
              {opcion.etiqueta}
            </span>
          </button>
        );
      })}
    </div>
  );
}
