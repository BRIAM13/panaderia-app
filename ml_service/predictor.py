"""
Carga del modelo entrenado y lógica de inferencia.

El modelo se carga UNA vez, al arrancar el proceso, y queda en memoria: cada
petición solo hace un `predict`, nunca reentrena ni vuelve a leer el disco.
"""

from __future__ import annotations

import json
from datetime import date
from pathlib import Path

import joblib
import numpy as np

import caracteristicas
import feriados_peru

DIR_BASE = Path(__file__).parent
RUTA_MODELO = DIR_BASE / "modelos" / "modelo_demanda.joblib"
RUTA_METRICAS = DIR_BASE / "modelos" / "metricas.json"

DIAS_ES = ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"]

# --- Parámetros del ajuste por contexto reciente ---------------------------
# Mínimo de observaciones reales para que el ajuste se considere informativo.
MIN_OBSERVACIONES_CONTEXTO = 3
# Amortiguación: solo se aplica la mitad de la desviación observada. Con pocos
# días de historial real, buena parte de la diferencia es ruido, no señal; la
# amortiguación evita que una semana atípica desvíe todas las predicciones.
AMORTIGUACION = 0.5
# Recorte duro del factor: por muy raro que sea el contexto, la predicción no
# se mueve más de un 30% respecto de lo que dice el modelo.
FACTOR_MIN, FACTOR_MAX = 0.70, 1.30


class ModeloNoDisponible(RuntimeError):
    """El artefacto entrenado no existe todavía."""


class Predictor:
    def __init__(self) -> None:
        self._paquete: dict | None = None
        self._metricas: dict | None = None

    # -- carga -------------------------------------------------------------

    def cargar(self) -> None:
        if not RUTA_MODELO.exists():
            return
        self._paquete = joblib.load(RUTA_MODELO)
        if RUTA_METRICAS.exists():
            self._metricas = json.loads(RUTA_METRICAS.read_text(encoding="utf-8"))

    @property
    def cargado(self) -> bool:
        return self._paquete is not None

    @property
    def version(self) -> str | None:
        return self._paquete.get("version_modelo") if self._paquete else None

    @property
    def nombre(self) -> str | None:
        return self._paquete.get("nombre_modelo") if self._paquete else None

    @property
    def entrenado_en(self) -> str | None:
        return self._paquete.get("entrenado_en") if self._paquete else None

    @property
    def metricas(self) -> dict | None:
        return self._metricas

    def _exigir_modelo(self) -> dict:
        if self._paquete is None:
            raise ModeloNoDisponible(
                "No hay modelo entrenado. Corre: python entrenar_modelo.py"
            )
        return self._paquete

    # -- inferencia --------------------------------------------------------

    def predecir_bruto(
        self, fechas: list[date], id_tienda: int, id_producto: int
    ) -> np.ndarray:
        """Predicción del modelo, recortada en 0 (la demanda no es negativa).
        Sin redondear y sin ajuste por contexto."""
        paquete = self._exigir_modelo()
        X = caracteristicas.construir(
            ((f, id_tienda, id_producto) for f in fechas),
            paquete["fecha_origen"],
        )
        return np.clip(paquete["pipeline"].predict(X), 0, None)

    def factor_de_contexto(
        self,
        contexto: list[tuple[date, float]],
        id_tienda: int,
        id_producto: int,
    ) -> tuple[float, int, str]:
        """Calibra la predicción contra el historial real reciente.

        Compara lo que el modelo habría predicho para esos mismos días con lo
        que realmente pasó y devuelve un factor multiplicativo amortiguado y
        recortado. Es una corrección de sesgo de nivel, deliberadamente
        simple: con pocos datos reales, un ajuste más sofisticado (reentrenar,
        o un modelo jerárquico) no tendría soporte estadístico y sería más
        difícil de auditar.

        Devuelve (factor, observaciones_usadas, motivo).
        """
        if not contexto:
            return 1.0, 0, "sin contexto reciente: se usa la predicción base"
        if len(contexto) < MIN_OBSERVACIONES_CONTEXTO:
            return (
                1.0,
                len(contexto),
                f"contexto insuficiente (mínimo {MIN_OBSERVACIONES_CONTEXTO} "
                "observaciones): se usa la predicción base",
            )

        fechas = [c[0] for c in contexto]
        reales = np.asarray([c[1] for c in contexto], dtype=float)
        predichas = self.predecir_bruto(fechas, id_tienda, id_producto)

        suma_pred = float(predichas.sum())
        suma_real = float(reales.sum())
        if suma_pred <= 0:
            return 1.0, len(contexto), "predicción base nula: no se ajusta"

        crudo = suma_real / suma_pred
        amortiguado = 1.0 + AMORTIGUACION * (crudo - 1.0)
        factor = float(np.clip(amortiguado, FACTOR_MIN, FACTOR_MAX))

        motivo = (
            f"calibrado con {len(contexto)} días reales "
            f"(razón real/predicho {crudo:.3f}, amortiguada al {AMORTIGUACION:.0%} "
            f"y recortada a [{FACTOR_MIN}, {FACTOR_MAX}])"
        )
        return factor, len(contexto), motivo

    def predecir(
        self,
        fechas: list[date],
        id_tienda: int,
        id_producto: int,
        contexto: list[tuple[date, float]] | None = None,
    ) -> tuple[list[dict], float, int, str]:
        """Predicción final por fecha. Devuelve (filas, factor, obs, motivo)."""
        factor, observaciones, motivo = self.factor_de_contexto(
            contexto or [], id_tienda, id_producto
        )
        brutas = self.predecir_bruto(fechas, id_tienda, id_producto)

        filas = []
        for fecha, bruta in zip(fechas, brutas):
            ajustada = float(bruta) * factor
            filas.append(
                {
                    "fecha": fecha,
                    "diaSemana": DIAS_ES[fecha.weekday()],
                    "esFeriado": feriados_peru.es_feriado(fecha),
                    "nombreFeriado": feriados_peru.nombre_feriado(fecha),
                    "demandaPredicha": int(round(ajustada)),
                    "demandaPredichaBruta": round(float(bruta), 2),
                }
            )
        return filas, factor, observaciones, motivo


# Instancia única del proceso.
predictor = Predictor()
