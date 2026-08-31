"""
Ingeniería de características (features).

Este módulo es la ÚNICA fuente de verdad de cómo una fecha + tienda +
producto se convierte en el vector que ve el modelo. Lo usan tanto el script
de entrenamiento como el endpoint de predicción, a propósito: si el
entrenamiento y la inferencia construyeran las columnas por separado, bastaría
un cambio en uno de los dos para introducir un desalineamiento silencioso
(training/serving skew) que degrada las predicciones sin lanzar ningún error.
"""

from __future__ import annotations

from datetime import date
from typing import Iterable

import pandas as pd

import feriados_peru

# Variables tratadas como categóricas (se codifican one-hot). El día de la
# semana y el mes son categóricos y no numéricos a propósito: la distancia
# entre "lunes" (0) y "domingo" (6) no es 6, y diciembre no es "11 más" que
# enero — son ciclos, no escalas.
COLUMNAS_CATEGORICAS = ["id_tienda", "id_producto", "dia_semana", "mes"]

COLUMNAS_NUMERICAS = [
    "dia_del_mes",
    "semana_anio",
    "es_fin_de_semana",
    "es_feriado",
    "es_vispera_feriado",
    "es_posterior_feriado",
    "es_quincena",
    "es_fin_de_mes",
    "dias_desde_inicio",
]

COLUMNAS = COLUMNAS_CATEGORICAS + COLUMNAS_NUMERICAS


def _fila(fecha: date, id_tienda: int, id_producto: int, fecha_origen: date) -> dict:
    return {
        "id_tienda": id_tienda,
        "id_producto": id_producto,
        "dia_semana": fecha.weekday(),          # lunes = 0 … domingo = 6
        "mes": fecha.month,
        "dia_del_mes": fecha.day,
        "semana_anio": fecha.isocalendar().week,
        "es_fin_de_semana": int(fecha.weekday() >= 5),
        "es_feriado": int(feriados_peru.es_feriado(fecha)),
        "es_vispera_feriado": int(feriados_peru.es_vispera_feriado(fecha)),
        "es_posterior_feriado": int(feriados_peru.es_posterior_feriado(fecha)),
        # Quincena: en Perú buena parte del pago de sueldos cae el 15 y el
        # último día del mes, y el consumo sube alrededor de esas fechas.
        "es_quincena": int(14 <= fecha.day <= 16),
        "es_fin_de_mes": int(fecha.day >= 28 or fecha.day <= 2),
        # Índice temporal: permite al modelo capturar la tendencia de
        # crecimiento del negocio. Ver la limitación documentada en el README
        # (los modelos de árboles no extrapolan más allá del rango visto en
        # entrenamiento, así que la tendencia se aplana en el futuro lejano).
        "dias_desde_inicio": (fecha - fecha_origen).days,
    }


def construir(
    registros: Iterable[tuple[date, int, int]],
    fecha_origen: date,
) -> pd.DataFrame:
    """Convierte una secuencia de (fecha, id_tienda, id_producto) en el
    DataFrame de features, con las columnas siempre en el mismo orden.

    `fecha_origen` es el primer día del historial de entrenamiento. Se guarda
    en la metadata del modelo y se vuelve a pasar en inferencia para que
    `dias_desde_inicio` signifique lo mismo en ambos lados.
    """
    filas = [
        _fila(fecha, id_tienda, id_producto, fecha_origen)
        for fecha, id_tienda, id_producto in registros
    ]
    if not filas:
        return pd.DataFrame(columns=COLUMNAS)
    return pd.DataFrame(filas)[COLUMNAS]


def desde_dataframe(df: pd.DataFrame, fecha_origen: date) -> pd.DataFrame:
    """Igual que `construir`, pero tomando un DataFrame que ya tiene las
    columnas `fecha`, `id_tienda` e `id_producto`."""
    return construir(
        zip(df["fecha"], df["id_tienda"], df["id_producto"]),
        fecha_origen,
    )
