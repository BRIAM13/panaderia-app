"""
Entrenamiento y validación del modelo de predicción de demanda.

Metodología
-----------
* Datos: agregado diario (`demanda_diaria`) del historial SINTÉTICO generado
  por `generar_datos_sinteticos.py`. Nunca se lee la base de producción.

* Partición TEMPORAL, no aleatoria. Se elige una fecha de corte y todo lo
  anterior es entrenamiento, todo lo posterior es validación. Un split
  aleatorio en una serie de tiempo filtra información del futuro hacia el
  entrenamiento (el modelo vería el martes y el jueves para "predecir" el
  miércoles) y produce métricas optimistas que no se sostienen en producción.
  El corte se hace por FECHA y no por fila, para que ningún día quede partido
  entre los dos conjuntos.

* Modelos comparados (los tres se evalúan sobre exactamente la misma
  validación y se reporta el desempeño de todos):
    1. Línea base estacional — la media histórica por tienda+producto+día de
       la semana. No es machine learning: es lo que un panadero con experiencia
       hace mentalmente. Sirve como piso: un modelo que no la supere no
       justifica su complejidad.
    2. RandomForestRegressor — bagging de árboles.
    3. GradientBoostingRegressor — boosting de árboles.
  Se selecciona el de menor MAE en validación.

* Métricas: MAE (error medio en unidades/paquetes, la que el negocio entiende
  directamente), RMSE (penaliza los errores grandes, los que dejan al negocio
  sin stock o con merma), MAPE (error relativo, comparable entre productos de
  escalas muy distintas) y R².

Por qué árboles y no deep learning: con ~4.400 observaciones diarias y 15
features tabulares, un ensamble de árboles es el estándar; una red neuronal no
tendría datos para justificar su capacidad, sería más difícil de interpretar y
no habría forma honesta de defender su elección en la tesis. Los árboles además
entregan importancias de variables, que sirven como evidencia de que el modelo
aprendió los patrones del negocio (día de la semana, feriados) y no ruido.
"""

from __future__ import annotations

import argparse
import json
import sqlite3
from datetime import date, datetime, timezone
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import GradientBoostingRegressor, RandomForestRegressor
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder

import caracteristicas
from catalogo import POR_ID

VERSION_MODELO = "1.0.0"

DIR_BASE = Path(__file__).parent
RUTA_BD = DIR_BASE / "data" / "entrenamiento.db"
DIR_MODELOS = DIR_BASE / "modelos"
RUTA_MODELO = DIR_MODELOS / "modelo_demanda.joblib"
RUTA_METRICAS = DIR_MODELOS / "metricas.json"
RUTA_REPORTE = DIR_MODELOS / "REPORTE_METRICAS.md"

# Proporción final del historial reservada para validación.
PROPORCION_VALIDACION = 0.20


# --------------------------------------------------------------------------
# Datos
# --------------------------------------------------------------------------

def cargar_demanda(ruta_bd: Path = RUTA_BD) -> pd.DataFrame:
    if not ruta_bd.exists():
        raise FileNotFoundError(
            f"No existe {ruta_bd}. Corre primero: python generar_datos_sinteticos.py"
        )
    con = sqlite3.connect(ruta_bd)
    try:
        df = pd.read_sql_query(
            "SELECT fecha, id_tienda, id_producto, cantidad "
            "FROM demanda_diaria ORDER BY fecha, id_tienda, id_producto",
            con,
        )
    finally:
        con.close()
    df["fecha"] = pd.to_datetime(df["fecha"]).dt.date
    return df


def partir_temporalmente(
    df: pd.DataFrame, proporcion_validacion: float = PROPORCION_VALIDACION
) -> tuple[pd.DataFrame, pd.DataFrame, date]:
    """Divide por fecha de corte: entrenamiento = pasado, validación = futuro."""
    fechas = sorted(df["fecha"].unique())
    corte_idx = int(len(fechas) * (1 - proporcion_validacion))
    fecha_corte = fechas[corte_idx]
    entrenamiento = df[df["fecha"] < fecha_corte].copy()
    validacion = df[df["fecha"] >= fecha_corte].copy()
    return entrenamiento, validacion, fecha_corte


# --------------------------------------------------------------------------
# Métricas
# --------------------------------------------------------------------------

def calcular_metricas(y_real: np.ndarray, y_pred: np.ndarray) -> dict[str, float]:
    y_real = np.asarray(y_real, dtype=float)
    y_pred = np.asarray(y_pred, dtype=float)

    mae = float(mean_absolute_error(y_real, y_pred))
    rmse = float(np.sqrt(mean_squared_error(y_real, y_pred)))
    # MAPE ignorando los días de demanda 0 (la división sería indefinida).
    no_cero = y_real > 0
    if no_cero.any():
        mape = float(
            np.mean(np.abs((y_real[no_cero] - y_pred[no_cero]) / y_real[no_cero])) * 100
        )
    else:
        mape = float("nan")
    return {
        "mae": round(mae, 3),
        "rmse": round(rmse, 3),
        "mape_pct": round(mape, 3),
        "r2": round(float(r2_score(y_real, y_pred)), 4),
    }


# --------------------------------------------------------------------------
# Modelos
# --------------------------------------------------------------------------

def construir_pipeline(regresor) -> Pipeline:
    """One-hot para las categóricas + el regresor. Las numéricas pasan tal
    cual: los árboles no necesitan escalado."""
    preproceso = ColumnTransformer(
        transformers=[
            (
                "categoricas",
                OneHotEncoder(handle_unknown="ignore", sparse_output=False),
                caracteristicas.COLUMNAS_CATEGORICAS,
            ),
        ],
        remainder="passthrough",
    )
    return Pipeline([("preproceso", preproceso), ("regresor", regresor)])


def linea_base_estacional(
    entrenamiento: pd.DataFrame, validacion: pd.DataFrame
) -> np.ndarray:
    """Media histórica por tienda+producto+día de la semana. Si un grupo no
    aparece en entrenamiento, cae a la media del producto."""
    ent = entrenamiento.copy()
    ent["dia_semana"] = [f.weekday() for f in ent["fecha"]]
    medias = (
        ent.groupby(["id_tienda", "id_producto", "dia_semana"])["cantidad"]
        .mean()
        .to_dict()
    )
    medias_producto = ent.groupby("id_producto")["cantidad"].mean().to_dict()

    predicciones = []
    for fecha, id_tienda, id_producto in zip(
        validacion["fecha"], validacion["id_tienda"], validacion["id_producto"]
    ):
        clave = (id_tienda, id_producto, fecha.weekday())
        predicciones.append(medias.get(clave, medias_producto.get(id_producto, 0.0)))
    return np.asarray(predicciones, dtype=float)


def cota_de_ruido(validacion: pd.DataFrame, fecha_origen: date) -> dict:
    """Compara el error del modelo contra el ERROR IRREDUCIBLE del problema.

    Este diagnóstico solo es posible porque los datos son sintéticos: se
    conoce la demanda esperada real λ(d,p) que usó el generador antes de
    sortear el ruido. Un "oráculo" que predijera exactamente λ todos los días
    seguiría cometiendo error, porque la demanda observada es una realización
    aleatoria alrededor de λ. Ese error es el piso teórico: ningún modelo,
    por bueno que sea, puede bajar de ahí.

    La razón `MAE_modelo / MAE_oráculo` es entonces la respuesta a la pregunta
    que de verdad importa metodológicamente: ¿cuánto del error observado es
    culpa del modelo y cuánto es azar irreducible del negocio? Un valor
    cercano a 1.0 significa que el modelo recuperó prácticamente toda la
    estructura predecible que se le inyectó.

    Nota para la tesis: esta cota NO es trasladable a producción. En datos
    reales λ es desconocida, así que este número valida la METODOLOGÍA (las
    features y el modelo capturan bien la señal), no la exactitud futura.
    """
    # Import local: el entrenamiento no depende del generador salvo para este
    # diagnóstico, que solo tiene sentido en el entorno sintético.
    import generar_datos_sinteticos as generador

    lambdas = []
    for fecha, id_producto in zip(validacion["fecha"], validacion["id_producto"]):
        producto = POR_ID[int(id_producto)]
        offset = (fecha - fecha_origen).days
        crecimiento = (1 + producto.crecimiento_anual) ** (offset / 365.0)
        lambdas.append(
            producto.demanda_base * crecimiento * generador.factor_dia(fecha, producto)
        )

    df = validacion.assign(lambda_real=lambdas)
    detalle = []
    for id_producto, grupo in df.groupby("id_producto"):
        mae_modelo = float((grupo["cantidad"] - grupo["prediccion"]).abs().mean())
        mae_oraculo = float((grupo["cantidad"] - grupo["lambda_real"]).abs().mean())
        producto = POR_ID[int(id_producto)]
        detalle.append(
            {
                "id_producto": int(id_producto),
                "nombre_producto": producto.nombre_producto,
                "mae_modelo": round(mae_modelo, 3),
                "mae_oraculo_irreducible": round(mae_oraculo, 3),
                "razon": round(mae_modelo / mae_oraculo, 3) if mae_oraculo else None,
            }
        )

    mae_modelo = float((df["cantidad"] - df["prediccion"]).abs().mean())
    mae_oraculo = float((df["cantidad"] - df["lambda_real"]).abs().mean())
    return {
        "descripcion": (
            "MAE del modelo frente al MAE de un oráculo que conoce la demanda "
            "esperada real del generador. La razón mide qué fracción del error "
            "es atribuible al modelo y no al azar irreducible."
        ),
        "solo_valido_en_datos_sinteticos": True,
        "mae_modelo": round(mae_modelo, 3),
        "mae_oraculo_irreducible": round(mae_oraculo, 3),
        "razon": round(mae_modelo / mae_oraculo, 3) if mae_oraculo else None,
        "por_producto": detalle,
    }


def importancias(pipeline: Pipeline) -> list[dict]:
    """Importancia de cada variable en el modelo ganador, con los nombres ya
    resueltos tras el one-hot. Se agrupan las columnas one-hot de vuelta a su
    variable original para que la tabla sea legible en la tesis."""
    nombres = list(pipeline.named_steps["preproceso"].get_feature_names_out())
    pesos = pipeline.named_steps["regresor"].feature_importances_

    agrupado: dict[str, float] = {}
    for nombre, peso in zip(nombres, pesos):
        limpio = nombre.split("__", 1)[-1]
        # 'id_producto_3' → 'id_producto'; 'dia_semana_6' → 'dia_semana'
        for original in caracteristicas.COLUMNAS_CATEGORICAS:
            if limpio.startswith(original + "_"):
                limpio = original
                break
        agrupado[limpio] = agrupado.get(limpio, 0.0) + float(peso)

    return [
        {"variable": k, "importancia": round(v, 4)}
        for k, v in sorted(agrupado.items(), key=lambda kv: kv[1], reverse=True)
    ]


# --------------------------------------------------------------------------
# Entrenamiento
# --------------------------------------------------------------------------

def entrenar(semilla: int = 42) -> dict:
    df = cargar_demanda()
    entrenamiento, validacion, fecha_corte = partir_temporalmente(df)
    fecha_origen = min(df["fecha"])

    X_ent = caracteristicas.desde_dataframe(entrenamiento, fecha_origen)
    y_ent = entrenamiento["cantidad"].to_numpy()
    X_val = caracteristicas.desde_dataframe(validacion, fecha_origen)
    y_val = validacion["cantidad"].to_numpy()

    resultados: dict[str, dict] = {}

    # 1. Línea base (sin ML)
    resultados["linea_base_estacional"] = calcular_metricas(
        y_val, linea_base_estacional(entrenamiento, validacion)
    )

    # 2. y 3. Modelos de árboles
    candidatos = {
        "random_forest": RandomForestRegressor(
            n_estimators=400,
            max_depth=None,
            min_samples_leaf=3,
            random_state=semilla,
            n_jobs=-1,
        ),
        "gradient_boosting": GradientBoostingRegressor(
            n_estimators=500,
            learning_rate=0.05,
            max_depth=3,
            subsample=0.9,
            random_state=semilla,
        ),
    }

    pipelines: dict[str, Pipeline] = {}
    for nombre, regresor in candidatos.items():
        pipeline = construir_pipeline(regresor)
        pipeline.fit(X_ent, y_ent)
        # La demanda no puede ser negativa: se recorta en 0 igual que en
        # inferencia, para que la métrica refleje lo que se sirve de verdad.
        pred = np.clip(pipeline.predict(X_val), 0, None)
        resultados[nombre] = calcular_metricas(y_val, pred)
        pipelines[nombre] = pipeline

    ganador = min(pipelines, key=lambda n: resultados[n]["mae"])
    pipeline_ganador = pipelines[ganador]

    # Métricas desglosadas por producto para el modelo ganador: el MAE global
    # está dominado por Panadería (cientos de unidades/día) y escondería el
    # desempeño en Hamburguesas (decenas de paquetes/día).
    pred_ganador = np.clip(pipeline_ganador.predict(X_val), 0, None)
    validacion = validacion.assign(prediccion=pred_ganador)
    por_producto = []
    for (id_tienda, id_producto), grupo in validacion.groupby(
        ["id_tienda", "id_producto"]
    ):
        producto = POR_ID.get(int(id_producto))
        por_producto.append(
            {
                "id_tienda": int(id_tienda),
                "id_producto": int(id_producto),
                "nombre_tienda": producto.nombre_tienda if producto else "?",
                "nombre_producto": producto.nombre_producto if producto else "?",
                "unidad": producto.unidad if producto else "?",
                "demanda_media_diaria": round(float(grupo["cantidad"].mean()), 2),
                **calcular_metricas(
                    grupo["cantidad"].to_numpy(), grupo["prediccion"].to_numpy()
                ),
            }
        )

    metricas = {
        "version_modelo": VERSION_MODELO,
        "modelo_seleccionado": ganador,
        "criterio_seleccion": "menor MAE en el conjunto de validación temporal",
        "entrenado_en": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "origen_datos": "SINTÉTICO (data/entrenamiento.db) — no se usó la base de producción",
        "particion": {
            "tipo": "temporal (cronológica, sin barajar)",
            "fecha_origen": fecha_origen.isoformat(),
            "fecha_corte": fecha_corte.isoformat(),
            "fecha_fin": max(df["fecha"]).isoformat(),
            "filas_entrenamiento": int(len(entrenamiento)),
            "filas_validacion": int(len(validacion)),
            "dias_entrenamiento": int(entrenamiento["fecha"].nunique()),
            "dias_validacion": int(validacion["fecha"].nunique()),
        },
        "metricas_validacion": resultados,
        "metricas_por_producto": por_producto,
        "cota_de_ruido": cota_de_ruido(validacion, fecha_origen),
        "importancia_variables": importancias(pipeline_ganador),
        "features": caracteristicas.COLUMNAS,
    }

    DIR_MODELOS.mkdir(parents=True, exist_ok=True)
    joblib.dump(
        {
            "pipeline": pipeline_ganador,
            "fecha_origen": fecha_origen,
            "columnas": caracteristicas.COLUMNAS,
            "version_modelo": VERSION_MODELO,
            "nombre_modelo": ganador,
            "entrenado_en": metricas["entrenado_en"],
        },
        RUTA_MODELO,
    )
    RUTA_METRICAS.write_text(
        json.dumps(metricas, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    RUTA_REPORTE.write_text(reporte_markdown(metricas), encoding="utf-8")

    return metricas


def reporte_markdown(m: dict) -> str:
    """Reporte legible de las métricas, pensado para citarse en el capítulo de
    resultados de la tesis."""
    p = m["particion"]
    lineas = [
        "# Reporte de validación — modelo de predicción de demanda",
        "",
        "> Generado automáticamente por `entrenar_modelo.py`. No editar a mano.",
        "",
        f"- **Versión del modelo:** {m['version_modelo']}",
        f"- **Modelo seleccionado:** `{m['modelo_seleccionado']}` "
        f"({m['criterio_seleccion']})",
        f"- **Entrenado:** {m['entrenado_en']}",
        f"- **Origen de los datos:** {m['origen_datos']}",
        "",
        "## Partición temporal",
        "",
        f"- Tipo: {p['tipo']}",
        f"- Entrenamiento: {p['fecha_origen']} - {p['fecha_corte']} "
        f"({p['dias_entrenamiento']} días, {p['filas_entrenamiento']} observaciones)",
        f"- Validación: {p['fecha_corte']} - {p['fecha_fin']} "
        f"({p['dias_validacion']} días, {p['filas_validacion']} observaciones)",
        "",
        "## Comparación de modelos (conjunto de validación)",
        "",
        "| Modelo | MAE | RMSE | MAPE (%) | R² |",
        "|---|---:|---:|---:|---:|",
    ]
    for nombre, met in m["metricas_validacion"].items():
        marca = " **(seleccionado)**" if nombre == m["modelo_seleccionado"] else ""
        lineas.append(
            f"| `{nombre}`{marca} | {met['mae']} | {met['rmse']} | "
            f"{met['mape_pct']} | {met['r2']} |"
        )

    lineas += [
        "",
        "## Desempeño por producto (modelo seleccionado)",
        "",
        "| Tienda | Producto | Unidad | Demanda media/día | MAE | RMSE | MAPE (%) | R² |",
        "|---|---|---|---:|---:|---:|---:|---:|",
    ]
    for f in m["metricas_por_producto"]:
        lineas.append(
            f"| {f['nombre_tienda']} | {f['nombre_producto']} | {f['unidad']} | "
            f"{f['demanda_media_diaria']} | {f['mae']} | {f['rmse']} | "
            f"{f['mape_pct']} | {f['r2']} |"
        )

    c = m["cota_de_ruido"]
    lineas += [
        "",
        "## Error del modelo vs. error irreducible",
        "",
        "Un oráculo que conociera exactamente la demanda esperada del generador",
        "seguiría equivocándose, porque la demanda observada es una realización",
        "aleatoria. Ese es el piso teórico del problema. La razón de abajo separa",
        "el error atribuible al modelo del azar irreducible del negocio.",
        "",
        "| Producto | MAE modelo | MAE oráculo (piso) | Razón |",
        "|---|---:|---:|---:|",
    ]
    for f in c["por_producto"]:
        lineas.append(
            f"| {f['nombre_producto']} | {f['mae_modelo']} | "
            f"{f['mae_oraculo_irreducible']} | {f['razon']} |"
        )
    lineas += [
        f"| **Global** | **{c['mae_modelo']}** | "
        f"**{c['mae_oraculo_irreducible']}** | **{c['razon']}** |",
        "",
        f"Es decir: el modelo comete un {round((c['razon'] - 1) * 100, 1)}% más de "
        "error que el mejor predictor posible sobre estos datos. El resto del",
        "error observado es ruido que ningún modelo puede eliminar.",
        "",
        "Este diagnóstico solo puede calcularse porque los datos son sintéticos",
        "(en datos reales la demanda esperada es desconocida). Valida la",
        "METODOLOGÍA, no la exactitud futura en producción.",
        "",
        "## Importancia de variables (modelo seleccionado)",
        "",
        "| Variable | Importancia |",
        "|---|---:|",
    ]
    for f in m["importancia_variables"]:
        lineas.append(f"| `{f['variable']}` | {f['importancia']} |")

    lineas += [
        "",
        "---",
        "",
        "**Limitación declarada.** Estas métricas describen el desempeño del",
        "modelo sobre un historial SINTÉTICO construido a partir de supuestos",
        "declarados del negocio, no sobre ventas reales. Miden que la",
        "metodología (features, partición temporal, elección de modelo)",
        "recupera correctamente los patrones que se le inyectaron; no",
        "constituyen una estimación del error que se obtendrá en producción.",
        "El detalle de esta decisión de diseño está en el README del servicio.",
        "",
    ]
    return "\n".join(lineas)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Entrena y valida el modelo de predicción de demanda."
    )
    parser.add_argument("--semilla", type=int, default=42)
    args = parser.parse_args()

    m = entrenar(semilla=args.semilla)

    print("Entrenamiento terminado\n")
    p = m["particion"]
    print(f"  Entrenamiento : {p['fecha_origen']} - {p['fecha_corte']} "
          f"({p['dias_entrenamiento']} días, {p['filas_entrenamiento']} obs.)")
    print(f"  Validación    : {p['fecha_corte']} - {p['fecha_fin']} "
          f"({p['dias_validacion']} días, {p['filas_validacion']} obs.)\n")
    print(f"  {'modelo':<26}{'MAE':>9}{'RMSE':>9}{'MAPE%':>9}{'R2':>9}")
    for nombre, met in m["metricas_validacion"].items():
        print(f"  {nombre:<26}{met['mae']:>9.3f}{met['rmse']:>9.3f}"
              f"{met['mape_pct']:>9.2f}{met['r2']:>9.4f}")
    c = m["cota_de_ruido"]
    print(f"\n  Seleccionado: {m['modelo_seleccionado']}")
    print(f"  MAE {c['mae_modelo']} vs piso irreducible {c['mae_oraculo_irreducible']}"
          f" (razon {c['razon']})")
    print(f"  Modelo   -> {RUTA_MODELO}")
    print(f"  Métricas -> {RUTA_METRICAS}")
    print(f"  Reporte  -> {RUTA_REPORTE}")


if __name__ == "__main__":
    main()
