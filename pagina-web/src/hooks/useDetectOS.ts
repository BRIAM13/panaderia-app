import { useEffect, useState } from "react";
import type { OS } from "../data/config";

/**
 * Detección best-effort del sistema operativo del visitante, solo para
 * resaltar/preseleccionar la tarjeta de descarga más probable — nunca para
 * decidir algo crítico, así que un falso negativo no rompe nada.
 */
export function useDetectOS(): OS | null {
  const [os, setOs] = useState<OS | null>(null);

  useEffect(() => {
    const ua = navigator.userAgent;
    if (/Android/i.test(ua)) setOs("android");
    else if (/iPhone|iPad|iPod/i.test(ua)) setOs("ios");
    else if (/Macintosh/i.test(ua)) setOs("macos");
    else if (/Windows/i.test(ua)) setOs("windows");
    else setOs("web");
  }, []);

  return os;
}
