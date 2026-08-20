import { Download, Smartphone } from "lucide-react";
import { SelectorModal } from "./SelectorModal";

const ENLACE_PLAY_STORE = "https://play.google.com/store/apps/details?id=com.ronceroslabs.panaderiaronceros";
const ENLACE_APK = "/downloads/PanaderiaRonceros-latest.apk";

interface DescargarAppModalProps {
  abierto: boolean;
  onCerrar: () => void;
}

/** Al tocar "Descargar app" desde Android, en vez de bajar el .apk de una
 * vez, se le da a elegir: Play Store (recomendado — instala y actualiza
 * solo, sin permisos especiales) o el .apk directo (para quien no puede
 * usar Play Store en su celular). */
export function DescargarAppModal({ abierto, onCerrar }: DescargarAppModalProps) {
  return (
    <SelectorModal abierto={abierto} titulo="Descargar la app" onCancelar={onCerrar} mostrarPie={false}>
      <div className="space-y-2.5">
        <a
          href={ENLACE_PLAY_STORE}
          target="_blank"
          rel="noopener noreferrer"
          onClick={onCerrar}
          className="flex items-center gap-3 rounded-xl bg-pan-terracota px-4 py-3.5 text-left text-pan-crema transition-opacity hover:opacity-90"
        >
          <Smartphone className="h-5 w-5 shrink-0" />
          <span>
            <span className="block font-semibold">Google Play Store</span>
            <span className="block text-xs text-pan-crema/80">
              Recomendado — se instala y actualiza solo
            </span>
          </span>
        </a>
        <a
          href={ENLACE_APK}
          download
          onClick={onCerrar}
          className="flex items-center gap-3 rounded-xl border border-pan-borde px-4 py-3.5 text-left text-pan-carbon transition-colors hover:bg-pan-terracota-suave/25"
        >
          <Download className="h-5 w-5 shrink-0 text-pan-terracota" />
          <span>
            <span className="block font-semibold">Descargar APK</span>
            <span className="block text-xs text-pan-carbon-suave">Instalación manual, sin Play Store</span>
          </span>
        </a>
      </div>
    </SelectorModal>
  );
}
