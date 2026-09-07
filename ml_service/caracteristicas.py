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

import catalogo
import feriados_peru

# Variables tratadas como categóricas (se codifican one-hot). El día de la
# semana y el mes son categóricos y no numéricos a propósito: la distancia
# entre "lunes" (0) y "domingo" (6) no es 6, y diciembre no es "11 más" que
# enero — son ciclos, no escalas.
COLUMNAS_CATEGORICAS = ["id_tienda", "id_producto", "dia_semana", "mes"]

# Variante CON el rubro de la tienda. `tipo_rubro` se deriva de `id_tienda`
# vía `catalogo.rubro_de_tienda`, nunca se recibe desde afuera: si el llamador
# pudiera mandarlo, una tienda podría llegar etiquetada de una forma en
# entrenamiento y de otra en inferencia, que es exactamente el skew que este
# módulo existe para evitar.
COLUMNAS_CATEGORICAS_CON_RUBRO = ["id_tienda", "tipo_rubro", "id_producto",
                                  "dia_semana", "mes"]

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

# Contrato por defecto (13 variables: 4 categóricas + 9 numéricas). Es el que
# consume el modelo desplegado; se mantiene intacto a propósito.
COLUMNAS = COLUMNAS_CATEGORICAS + COLUMNAS_NUMERICAS

# Contrato del experimento de rubro (14 variables).
COLUMNAS_CON_RUBRO = COLUMNAS_CATEGORICAS_CON_RUBRO + COLUMNAS_NUMERICAS


def columnas_categoricas(incluir_rubro: bool = False) -> list[str]:
    """Categóricas del contrato pedido, para armar el ColumnTransformer."""
    return list(
        COLUMNAS_CATEGORICAS_CON_RUBRO if incluir_rubro else COLUMNAS_CATEGORICAS
    )


def columnas(incluir_rubro: bool = False) -> list[str]:
    """Contrato completo de features, en orden fijo."""
    return list(COLUMNAS_CON_RUBRO if incluir_rubro else COLUMNAS)


def _fila(fecha: date, id_tienda: int, id_producto: int, fecha_origen: date) -> dict:
    return {
        "id_tienda": id_tienda,
        "tipo_rubro": catalogo.rubro_de_tienda(id_tienda),
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
    incluir_rubro: bool = False,
) -> pd.DataFrame:
    """Convierte una secuencia de (fecha, id_tienda, id_producto) en el
    DataFrame de features, con las columnas siempre en el mismo orden.

    `fecha_origen` es el primer día del historial de entrenamiento. Se guarda
    en la metadata del modelo y se vuelve a pasar en inferencia para que
    `dias_desde_inicio` signifique lo mismo en ambos lados.

    `incluir_rubro` selecciona el contrato de features. NO es una opción que
    el llamador elija a mano en inferencia: se lee de la metadata del modelo
    entrenado (ver `predictor.py`), de modo que el juego de columnas siempre
    sea el mismo con el que se ajustó el pipeline.
    """
    cols = columnas(incluir_rubro)
    filas = [
        _fila(fecha, id_tienda, id_producto, fecha_origen)
        for fecha, id_tienda, id_producto in registros
    ]
    if not filas:
        return pd.DataFrame(columns=cols)
    return pd.DataFrame(filas)[cols]


def desde_dataframe(
    df: pd.DataFrame, fecha_origen: date, incluir_rubro: bool = False
) -> pd.DataFrame:
    """Igual que `construir`, pero tomando un DataFrame que ya tiene las
    columnas `fecha`, `id_tienda` e `id_producto`."""
    return construir(
        zip(df["fecha"], df["id_tienda"], df["id_producto"]),
        fecha_origen,
        incluir_rubro,
    )
