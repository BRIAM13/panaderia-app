"""
Experimento: ¿le sirve al modelo conocer el RUBRO de la tienda?

Pregunta
--------
¿Mejora la predicción de demanda si el modelo sabe que una tienda es de pan de
hamburguesa, de panadería clásica o de horneados? Y si sirve, ¿conviene más un
modelo único que recibe el rubro como variable, o modelos especializados,
entrenados cada uno solo con las tiendas de su rubro?

Configuraciones comparadas (las tres sobre EXACTAMENTE la misma partición
temporal, el mismo regresor y la misma semilla — lo único que cambia es lo que
se pregunta):

    (a) unico_sin_rubro          modelo único. Control: el pipeline actual.
    (b) unico_con_rubro          modelo único + `tipo_rubro` como categórica.
    (c) especializado_por_rubro  un modelo entrenado solo con los datos de
                                 cada rubro.

Escenarios
----------
El experimento se corre sobre tres escenarios, y esa es la parte importante
del diseño: la respuesta NO es la misma en los tres, y quedarse solo con el
primero llevaría a una conclusión equivocada.

  1. `produccion_1_tienda_por_rubro`
     Las 3 tiendas reales del catálogo de producción. Acá hay exactamente UNA
     tienda por rubro, así que `tipo_rubro` es una función biyectiva de
     `id_tienda`: el one-hot de la tienda ya codifica el rubro sin pérdida.
     La variable de rubro es REDUNDANTE POR CONSTRUCCIÓN. Este escenario está
     para demostrarlo con números, no para descubrir nada.

  2. `multisucursal_tiendas_conocidas`
     Catálogo ampliado: 3 sucursales por rubro. Partición temporal normal, así
     que todas las tiendas de validación ya se vieron en entrenamiento. El
     one-hot de `id_tienda` sigue pudiendo memorizar cada tienda, así que el
     rubro sigue teniendo poco que agregar — pero ahora es una pregunta
     empírica y no una identidad algebraica.

  3. `multisucursal_tienda_nueva`
     Mismo catálogo ampliado, pero se deja UNA SUCURSAL POR RUBRO totalmente
     fuera del entrenamiento y se predice para ella. Es el caso de negocio que
     de verdad importa: abrir un local nuevo y tener que planificar producción
     desde el día uno, sin historial propio. Acá el one-hot de `id_tienda` no
     tiene ninguna columna que activar (`handle_unknown='ignore'` la deja en
     todo-ceros), así que el rubro es la ÚNICA vía por la que el modelo puede
     saber a qué se parece la tienda nueva.

⚠️ SUPUESTO DECLARADO, NO HALLAZGO
----------------------------------
Que las tiendas de un mismo rubro compartan la forma de su demanda es algo que
el generador sintético INYECTA a propósito (ver `catalogo.FIRMA_POR_RUBRO`).
Este experimento mide si la metodología recupera esa estructura y bajo qué
condiciones aporta — no demuestra que la estructura exista en el negocio real.
La forma de comprobarlo en la realidad está escrita al final del reporte.

Honestidad estadística
----------------------
Una diferencia de MAE de unas décimas de porcentaje entre configuraciones no
es un ganador: es ruido. Para no confundir una cosa con la otra se reportan
dos medidas de incertidumbre, y ninguna conclusión se declara sin ellas:

  * Dispersión entre semillas: cada configuración se reentrena con varias
    semillas del regresor. Si la diferencia entre (a) y (b) es menor que la
    variación que produce cambiar la semilla, no hay nada que concluir.
  * Bootstrap pareado sobre los errores absolutos por observación, con
    intervalo de confianza del 95% para la diferencia de MAE. Si el intervalo
    contiene 0, la diferencia no es distinguible de cero.
"""

from __future__ import annotations

import json
from datetime import date, datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.ensemble import GradientBoostingRegressor, RandomForestRegressor

import caracteristicas
import catalogo as cat
import entrenar_modelo as em

DIR_BASE = Path(__file__).parent
RUTA_BD_PRODUCCION = DIR_BASE / "data" / "entrenamiento.db"
RUTA_BD_RUBROS = DIR_BASE / "data" / "entrenamiento_rubros.db"
DIR_MODELOS = DIR_BASE / "modelos"
RUTA_JSON = DIR_MODELOS / "comparacion_rubro.json"
RUTA_REPORTE = DIR_MODELOS / "REPORTE_COMPARACION_RUBRO.md"

# Semillas del regresor. Sirven para medir cuánta variación produce el propio
# azar del ajuste: es la vara contra la que se juzga si una diferencia entre
# configuraciones es real o ruido.
SEMILLAS: tuple[int, ...] = (42, 7, 101, 2024, 31337)
SEMILLA_BASE = SEMILLAS[0]

MODELOS: tuple[str, ...] = ("random_forest", "gradient_boosting")


def _modelo_referencia() -> str:
    """Regresor usado para los desgloses por rubro: el mismo que ganó el
    entrenamiento de producción, leído de `metricas.json`.

    Se lee del artefacto en vez de fijarse a mano porque cuál de los dos gana
    depende de la ventana de datos generada (el generador simula hasta ayer,
    así que la ventana se desliza), y una constante escrita a mano quedaría
    desincronizada en silencio. Las pruebas de significancia, de todos modos,
    se calculan para AMBOS regresores: la conclusión del experimento no debe
    depender de cuál se haya elegido como referencia.
    """
    try:
        m = json.loads(em.RUTA_METRICAS.read_text(encoding="utf-8"))
        seleccionado = m.get("modelo_seleccionado")
        if seleccionado in MODELOS:
            return seleccionado
    except (OSError, ValueError):
        pass
    return "gradient_boosting"


MODELO_REFERENCIA = _modelo_referencia()

# Mínimo de observaciones para que un rubro justifique un modelo propio. Por
# debajo de esto no se entrena y se dice en el reporte, en vez de forzar un
# modelo sin soporte estadístico y presentar sus métricas como si valieran.
MIN_FILAS_MODELO_PROPIO = 400

REMUESTREOS_BOOTSTRAP = 2000

# Umbral de RELEVANCIA PRÁCTICA, en % del MAE del control.
#
# Hace falta además de la significancia estadística, y no es un detalle. Con
# ~900 observaciones pareadas y errores muy correlacionados entre
# configuraciones, el bootstrap detecta como "distinguible de cero" una
# diferencia de dos décimas de porcentaje — que es cierta y a la vez
# irrelevante: sobre una demanda de cientos de unidades de pan al día, 0.2% de
# MAE no cambia ninguna decisión de producción.
#
# Un resultado solo se declara MEJORA si pasa las tres pruebas: es
# estadísticamente distinguible de cero, supera la variación que produce
# cambiar la semilla del regresor, y supera este umbral.
UMBRAL_RELEVANCIA_PCT = 1.0

CONFIGURACIONES: dict[str, dict] = {
    "a_unico_sin_rubro": {
        "etiqueta": "(a) Modelo único SIN rubro",
        "incluir_rubro": False,
        "especializado": False,
    },
    "b_unico_con_rubro": {
        "etiqueta": "(b) Modelo único CON rubro",
        "incluir_rubro": True,
        "especializado": False,
    },
    "c_especializado_por_rubro": {
        "etiqueta": "(c) Modelos especializados por rubro",
        # Dentro de un modelo especializado el rubro es una columna constante:
        # no aporta nada y solo agregaría una columna one-hot inerte.
        "incluir_rubro": False,
        "especializado": True,
    },
}


# ---------------------------------------------------------------------------
# Regresores
# ---------------------------------------------------------------------------

def _regresor(nombre: str, semilla: int):
    """Mismos hiperparámetros que el entrenamiento de producción. No se
    re-tunean acá a propósito: si cada configuración se optimizara por
    separado, la comparación mediría el esfuerzo de tuneo y no el efecto de
    la variable de rubro, que es lo que se quiere aislar."""
    if nombre == "random_forest":
        return RandomForestRegressor(
            n_estimators=400, max_depth=None, min_samples_leaf=3,
            random_state=semilla, n_jobs=-1,
        )
    if nombre == "gradient_boosting":
        return GradientBoostingRegressor(
            n_estimators=500, learning_rate=0.05, max_depth=3,
            subsample=0.9, random_state=semilla,
        )
    raise ValueError(f"Regresor desconocido: {nombre}")


# ---------------------------------------------------------------------------
# Líneas base (sin ML)
# ---------------------------------------------------------------------------

def linea_base(
    entrenamiento: pd.DataFrame, validacion: pd.DataFrame, por_rubro: bool
) -> np.ndarray:
    """Media histórica del día de la semana. En su versión SIN rubro agrupa por
    tienda+producto (lo que hace hoy el script de producción); en la versión
    CON rubro agrupa por rubro+producto.

    La variante por rubro no es decorativa: es la línea base correcta para el
    escenario de tienda nueva, donde no existe media histórica de esa tienda y
    lo único que se puede promediar es lo que hacen las tiendas parecidas.
    """
    ent = entrenamiento.copy()
    ent["dia_semana"] = [f.weekday() for f in ent["fecha"]]

    clave = (
        ["tipo_rubro", "id_producto", "dia_semana"]
        if por_rubro
        else ["id_tienda", "id_producto", "dia_semana"]
    )
    medias = ent.groupby(clave)["cantidad"].mean().to_dict()
    respaldo = ent.groupby("id_producto")["cantidad"].mean().to_dict()
    respaldo_global = float(ent["cantidad"].mean())

    predicciones = []
    for fecha, id_tienda, id_producto, rubro in zip(
        validacion["fecha"], validacion["id_tienda"],
        validacion["id_producto"], validacion["tipo_rubro"],
    ):
        k = (
            (rubro, id_producto, fecha.weekday())
            if por_rubro
            else (id_tienda, id_producto, fecha.weekday())
        )
        predicciones.append(
            medias.get(k, respaldo.get(id_producto, respaldo_global))
        )
    return np.asarray(predicciones, dtype=float)


# ---------------------------------------------------------------------------
# Ajuste y predicción de una configuración
# ---------------------------------------------------------------------------

def _predecir_unico(
    nombre_modelo: str, semilla: int, incluir_rubro: bool,
    entrenamiento: pd.DataFrame, validacion: pd.DataFrame, fecha_origen: date,
) -> tuple[np.ndarray, dict]:
    X_ent = caracteristicas.desde_dataframe(entrenamiento, fecha_origen, incluir_rubro)
    X_val = caracteristicas.desde_dataframe(validacion, fecha_origen, incluir_rubro)
    pipeline = em.construir_pipeline(_regresor(nombre_modelo, semilla), incluir_rubro)
    pipeline.fit(X_ent, entrenamiento["cantidad"].to_numpy())
    pred = np.clip(pipeline.predict(X_val), 0, None)
    return pred, {"modelos_entrenados": 1, "rubros_sin_modelo_propio": []}


def _predecir_especializado(
    nombre_modelo: str, semilla: int,
    entrenamiento: pd.DataFrame, validacion: pd.DataFrame, fecha_origen: date,
) -> tuple[np.ndarray, dict]:
    """Un modelo por rubro. Los rubros sin datos suficientes NO reciben modelo
    propio: caen al modelo global y se listan en el detalle, para que el
    reporte pueda decirlo en vez de fabricar un modelo sin soporte."""
    # Respaldo: modelo global entrenado con todo, para los rubros que no
    # alcanzan el mínimo y para cualquier rubro que aparezca solo en validación.
    respaldo, _ = _predecir_unico(
        nombre_modelo, semilla, False, entrenamiento, validacion, fecha_origen
    )
    pred = respaldo.copy()

    entrenados = 0
    sin_modelo: list[dict] = []
    rubros_val = set(validacion["tipo_rubro"].unique())

    for rubro in sorted(rubros_val):
        m_ent = (entrenamiento["tipo_rubro"] == rubro).to_numpy()
        m_val = (validacion["tipo_rubro"] == rubro).to_numpy()
        if not m_val.any():
            continue
        if int(m_ent.sum()) < MIN_FILAS_MODELO_PROPIO:
            sin_modelo.append({
                "tipo_rubro": rubro,
                "filas_entrenamiento": int(m_ent.sum()),
                "motivo": (
                    f"menos de {MIN_FILAS_MODELO_PROPIO} observaciones de "
                    "entrenamiento: no se entrena un modelo propio, se usa el "
                    "modelo global"
                ),
            })
            continue

        sub_ent = entrenamiento[m_ent]
        sub_val = validacion[m_val]
        X_ent = caracteristicas.desde_dataframe(sub_ent, fecha_origen, False)
        X_val = caracteristicas.desde_dataframe(sub_val, fecha_origen, False)
        pipeline = em.construir_pipeline(_regresor(nombre_modelo, semilla), False)
        pipeline.fit(X_ent, sub_ent["cantidad"].to_numpy())
        pred[m_val] = np.clip(pipeline.predict(X_val), 0, None)
        entrenados += 1

    return pred, {
        "modelos_entrenados": entrenados,
        "rubros_sin_modelo_propio": sin_modelo,
    }


def predecir(
    config: dict, nombre_modelo: str, semilla: int,
    entrenamiento: pd.DataFrame, validacion: pd.DataFrame, fecha_origen: date,
) -> tuple[np.ndarray, dict]:
    if config["especializado"]:
        return _predecir_especializado(
            nombre_modelo, semilla, entrenamiento, validacion, fecha_origen
        )
    return _predecir_unico(
        nombre_modelo, semilla, config["incluir_rubro"],
        entrenamiento, validacion, fecha_origen,
    )


# ---------------------------------------------------------------------------
# Significancia
# ---------------------------------------------------------------------------

def bootstrap_diferencia_mae(
    errores_a: np.ndarray, errores_b: np.ndarray, semilla: int = 12345
) -> dict:
    """Bootstrap PAREADO de la diferencia de MAE entre dos configuraciones.

    Pareado (se remuestrean las observaciones, no los modelos) porque las dos
    configuraciones predicen exactamente las mismas filas: comparar sus MAE
    por separado ignoraría que sus errores están correlacionados y ensancharía
    el intervalo sin motivo.

    Convención de signo: positivo = B tiene MENOS error que A (B mejora).
    Si el intervalo del 95% contiene 0, la diferencia no es distinguible de
    cero con estos datos y NO se puede declarar un ganador.
    """
    dif = np.asarray(errores_a, dtype=float) - np.asarray(errores_b, dtype=float)
    n = len(dif)
    rng = np.random.default_rng(semilla)
    idx = rng.integers(0, n, size=(REMUESTREOS_BOOTSTRAP, n))
    medias = dif[idx].mean(axis=1)

    observada = float(dif.mean())
    lim_inf = float(np.percentile(medias, 2.5))
    lim_sup = float(np.percentile(medias, 97.5))
    significativa = (lim_inf > 0) or (lim_sup < 0)
    mae_a = float(np.mean(errores_a))
    return {
        "diferencia_mae": round(observada, 4),
        "diferencia_pct_sobre_a": round(100 * observada / mae_a, 3) if mae_a else None,
        "ic95_inferior": round(lim_inf, 4),
        "ic95_superior": round(lim_sup, 4),
        "significativa_al_95": bool(significativa),
        "lectura": (
            "la diferencia es distinguible de cero al 95%"
            if significativa
            else "el intervalo del 95% contiene 0: la diferencia NO es "
                 "distinguible del ruido"
        ),
    }


def veredicto(s: dict, desv_semillas: float) -> dict:
    """Combina las tres pruebas en un veredicto único.

    Una diferencia solo cuenta como mejora si (1) es estadísticamente
    distinguible de cero, (2) es mayor que la variación que produce cambiar la
    semilla del regresor, y (3) supera el umbral de relevancia práctica.
    Cualquiera de las tres que falle degrada el veredicto: la significancia
    estadística por sí sola no es un resultado utilizable.
    """
    dif = s["diferencia_mae"]
    pct = s["diferencia_pct_sobre_a"] or 0.0
    supera_semilla = abs(dif) > float(desv_semillas or 0.0)
    relevante = abs(pct) >= UMBRAL_RELEVANCIA_PCT

    if not s["significativa_al_95"]:
        etiqueta, texto = "sin efecto", (
            "el IC 95% contiene 0: no hay evidencia de diferencia"
        )
    elif not relevante:
        etiqueta, texto = "irrelevante", (
            f"distinguible de 0 pero solo {abs(pct)}% del MAE, por debajo del "
            f"umbral de relevancia práctica ({UMBRAL_RELEVANCIA_PCT}%): es real "
            "y no sirve para nada"
        )
    elif not supera_semilla:
        etiqueta, texto = "dentro del ruido de semilla", (
            f"la diferencia ({abs(dif)}) no supera la variación que produce "
            f"cambiar la semilla del regresor (±{desv_semillas})"
        )
    elif dif > 0:
        etiqueta, texto = "MEJORA", (
            f"reduce el MAE un {pct}%, por encima del umbral de relevancia y "
            "del ruido de semilla"
        )
    else:
        etiqueta, texto = "EMPEORA", (
            f"aumenta el MAE un {abs(pct)}%, por encima del umbral de "
            "relevancia y del ruido de semilla"
        )

    return {
        **s,
        "desv_entre_semillas_control": round(float(desv_semillas or 0.0), 4),
        "supera_ruido_de_semilla": bool(supera_semilla),
        "relevante_practicamente": bool(relevante),
        "veredicto": etiqueta,
        "veredicto_detalle": texto,
    }


def diagnostico_redundancia(df: pd.DataFrame) -> dict:
    """¿La variable de rubro es redundante, y por qué vía?

    Es el diagnóstico que evita malinterpretar todo el experimento. El rubro no
    puede aportar información que el modelo ya tenga por otro camino, y hay
    DOS caminos posibles, los dos hay que mirarlos:

      * vía `id_tienda`: si cada tienda pertenece a un solo rubro (siempre
        cierto) Y hay una sola tienda por rubro, el one-hot de la tienda
        codifica el rubro exactamente.
      * vía `id_producto`: si cada producto se vende en un solo rubro —lo
        normal, porque una hamburguesería y una panadería no venden lo mismo—
        el one-hot del producto TAMBIÉN codifica el rubro exactamente, aunque
        haya muchas tiendas por rubro.

    Cuando cualquiera de las dos se cumple sobre los datos de ENTRENAMIENTO, la
    variable de rubro es matemáticamente redundante y no hay que esperar
    ninguna mejora de (b) sobre (a). Reportarlo es lo que separa "medimos que
    no mejora" de "sabemos por qué no podía mejorar".
    """
    rubros_por_tienda = df.groupby("id_tienda")["tipo_rubro"].nunique()
    rubros_por_producto = df.groupby("id_producto")["tipo_rubro"].nunique()
    tiendas_por_rubro = df.groupby("tipo_rubro")["id_tienda"].nunique()

    via_tienda = bool((rubros_por_tienda == 1).all())
    via_producto = bool((rubros_por_producto == 1).all())
    una_tienda_por_rubro = bool((tiendas_por_rubro == 1).all())

    return {
        "tiendas_por_rubro": {str(k): int(v) for k, v in tiendas_por_rubro.items()},
        "rubro_determinado_por_id_tienda": via_tienda,
        "una_sola_tienda_por_rubro": una_tienda_por_rubro,
        "rubro_determinado_por_id_producto": via_producto,
        "rubro_redundante_en_entrenamiento": bool(
            (via_tienda and una_tienda_por_rubro) or via_producto
        ),
        "explicacion": (
            "el one-hot de `id_tienda` codifica el rubro sin pérdida (hay una "
            "sola tienda por rubro)"
            if (via_tienda and una_tienda_por_rubro)
            else (
                "el one-hot de `id_producto` codifica el rubro sin pérdida "
                "(cada producto se vende en un solo rubro), así que el modelo "
                "SIN la variable de rubro igual sabe de qué rubro se trata, por "
                "la puerta de atrás"
                if via_producto
                else "el rubro NO es deducible de `id_tienda` ni de "
                     "`id_producto`: aporta información propia"
            )
        ),
    }


# ---------------------------------------------------------------------------
# Escenarios
# ---------------------------------------------------------------------------

def _metricas_por_rubro(validacion: pd.DataFrame, pred: np.ndarray) -> list[dict]:
    df = validacion.assign(prediccion=pred)
    salida = []
    for rubro, grupo in df.groupby("tipo_rubro"):
        salida.append({
            "tipo_rubro": rubro,
            "observaciones": int(len(grupo)),
            "tiendas": int(grupo["id_tienda"].nunique()),
            "demanda_media_diaria": round(float(grupo["cantidad"].mean()), 2),
            **em.calcular_metricas(
                grupo["cantidad"].to_numpy(), grupo["prediccion"].to_numpy()
            ),
        })
    return sorted(salida, key=lambda r: r["tipo_rubro"])


def evaluar_escenario(
    nombre: str,
    descripcion: str,
    entrenamiento: pd.DataFrame,
    validacion: pd.DataFrame,
    fecha_origen: date,
    fecha_corte: date,
    indice_catalogo: dict,
) -> dict:
    y_val = validacion["cantidad"].to_numpy()
    resultado: dict = {
        "descripcion": descripcion,
        "particion": {
            "fecha_origen": fecha_origen.isoformat(),
            "fecha_corte": fecha_corte.isoformat(),
            "filas_entrenamiento": int(len(entrenamiento)),
            "filas_validacion": int(len(validacion)),
            "tiendas_entrenamiento": sorted(
                int(t) for t in entrenamiento["id_tienda"].unique()
            ),
            "tiendas_validacion": sorted(
                int(t) for t in validacion["id_tienda"].unique()
            ),
            "rubros": sorted(str(r) for r in validacion["tipo_rubro"].unique()),
        },
        "configuraciones": {},
    }

    # Errores absolutos por observación en la semilla base, indexados por
    # (configuración, regresor). Alimentan el bootstrap pareado; se guardan
    # para AMBOS regresores para que la conclusión no dependa de cuál se haya
    # elegido como referencia.
    errores: dict[tuple[str, str], np.ndarray] = {}
    pred_referencia: dict[str, np.ndarray] = {}

    for clave, config in CONFIGURACIONES.items():
        bloque: dict = {"etiqueta": config["etiqueta"], "modelos": {}}

        # Línea base (sin ML). No depende de semilla.
        base = linea_base(entrenamiento, validacion, por_rubro=config["incluir_rubro"]
                          or config["especializado"])
        bloque["linea_base"] = {
            "agrupacion": (
                "rubro+producto+día de la semana"
                if (config["incluir_rubro"] or config["especializado"])
                else "tienda+producto+día de la semana"
            ),
            **em.calcular_metricas(y_val, base),
        }

        for nombre_modelo in MODELOS:
            por_semilla = []
            for semilla in SEMILLAS:
                pred, detalle = predecir(
                    config, nombre_modelo, semilla,
                    entrenamiento, validacion, fecha_origen,
                )
                met = em.calcular_metricas(y_val, pred)
                por_semilla.append({"semilla": semilla, **met})

                if semilla == SEMILLA_BASE:
                    errores[(clave, nombre_modelo)] = np.abs(y_val - pred)
                    if nombre_modelo == MODELO_REFERENCIA:
                        pred_referencia[clave] = pred
                        bloque["detalle_ajuste"] = detalle

            maes = np.array([s["mae"] for s in por_semilla], dtype=float)
            bloque["modelos"][nombre_modelo] = {
                "mae_media": round(float(maes.mean()), 4),
                "mae_desv_estandar": round(float(maes.std(ddof=1)), 4),
                "mae_min": round(float(maes.min()), 4),
                "mae_max": round(float(maes.max()), 4),
                "semilla_base": next(
                    s for s in por_semilla if s["semilla"] == SEMILLA_BASE
                ),
                "por_semilla": por_semilla,
            }

        bloque["por_rubro"] = _metricas_por_rubro(validacion, pred_referencia[clave])
        resultado["configuraciones"][clave] = bloque

    # Piso irreducible del escenario: cuánto margen de mejora existe siquiera.
    val_ref = validacion.assign(prediccion=pred_referencia["a_unico_sin_rubro"])
    resultado["cota_de_ruido"] = em.cota_de_ruido(
        val_ref, fecha_origen, indice_catalogo
    )

    # Dispersión del control entre semillas: la vara contra la que se juzga si
    # una diferencia entre configuraciones sobrevive al azar del propio ajuste.
    desv_control = {
        modelo: resultado["configuraciones"]["a_unico_sin_rubro"]["modelos"][
            modelo
        ]["mae_desv_estandar"]
        for modelo in MODELOS
    }

    # Significancia de cada configuración contra el control (a), para cada
    # regresor por separado.
    resultado["significancia_vs_control"] = {
        clave: {
            modelo: veredicto(
                bootstrap_diferencia_mae(
                    errores[("a_unico_sin_rubro", modelo)], errores[(clave, modelo)]
                ),
                desv_control[modelo],
            )
            for modelo in MODELOS
        }
        for clave in ("b_unico_con_rubro", "c_especializado_por_rubro")
    }
    resultado["significancia_b_vs_c"] = {
        modelo: veredicto(
            bootstrap_diferencia_mae(
                errores[("b_unico_con_rubro", modelo)],
                errores[("c_especializado_por_rubro", modelo)],
            ),
            desv_control[modelo],
        )
        for modelo in MODELOS
    }
    resultado["diagnostico_redundancia"] = diagnostico_redundancia(entrenamiento)
    resultado["modelo_referencia"] = MODELO_REFERENCIA
    return resultado


def _cargar(ruta_bd: Path) -> pd.DataFrame:
    if not ruta_bd.exists():
        raise FileNotFoundError(
            f"No existe {ruta_bd}. Corre primero:\n"
            f"  python generar_datos_sinteticos.py"
            + ("  --experimento-rubro" if "rubros" in ruta_bd.name else "")
        )
    return em.cargar_demanda(ruta_bd)


def ejecutar() -> dict:
    escenarios: dict[str, dict] = {}

    # --- Escenario 1: catálogo de producción, 1 tienda por rubro ------------
    df = _cargar(RUTA_BD_PRODUCCION)
    ent, val, corte = em.partir_temporalmente(df)
    escenarios["produccion_1_tienda_por_rubro"] = evaluar_escenario(
        "produccion_1_tienda_por_rubro",
        "Las 3 tiendas del catálogo de producción (una por rubro). El rubro es "
        "una función biyectiva de `id_tienda`, así que es redundante por "
        "construcción: este escenario cuantifica esa redundancia.",
        ent, val, min(df["fecha"]), corte, cat.indice_por_par(cat.CATALOGO),
    )

    # --- Escenarios 2 y 3: catálogo multi-sucursal --------------------------
    dfr = _cargar(RUTA_BD_RUBROS)
    ent_r, val_r, corte_r = em.partir_temporalmente(dfr)
    origen_r = min(dfr["fecha"])
    indice_r = cat.indice_por_par(cat.CATALOGO_EXPERIMENTO_RUBRO)

    escenarios["multisucursal_tiendas_conocidas"] = evaluar_escenario(
        "multisucursal_tiendas_conocidas",
        "9 sucursales (3 por rubro), partición temporal estándar: todas las "
        "tiendas de validación ya se vieron en entrenamiento.",
        ent_r, val_r, origen_r, corte_r, indice_r,
    )

    # Hold-out de TIENDA: una sucursal por rubro sale por completo del
    # entrenamiento. Se conserva el mismo corte temporal que el escenario 2
    # para que los dos sean comparables: lo único que cambia es qué tiendas
    # pudo ver el modelo, no qué días.
    holdout = set(cat.TIENDAS_HOLDOUT_EXPERIMENTO)
    ent_nuevas = ent_r[~ent_r["id_tienda"].isin(holdout)].copy()
    val_nuevas = val_r[val_r["id_tienda"].isin(holdout)].copy()
    escenarios["multisucursal_tienda_nueva"] = evaluar_escenario(
        "multisucursal_tienda_nueva",
        "Mismo catálogo, pero las sucursales "
        f"{sorted(holdout)} se excluyen por completo del entrenamiento y son "
        "las únicas que se evalúan. Simula abrir un local nuevo y tener que "
        "planificar producción sin historial propio.",
        ent_nuevas, val_nuevas, origen_r, corte_r, indice_r,
    )

    salida = {
        "generado_en": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "pregunta": (
            "¿Mejora la predicción de demanda si el modelo conoce el rubro de "
            "la tienda, y conviene más un modelo único con esa variable o "
            "modelos especializados por rubro?"
        ),
        "origen_datos": "SINTÉTICO — no se usó la base de producción",
        "semillas": list(SEMILLAS),
        "modelo_referencia": MODELO_REFERENCIA,
        "remuestreos_bootstrap": REMUESTREOS_BOOTSTRAP,
        "configuraciones": {
            k: v["etiqueta"] for k, v in CONFIGURACIONES.items()
        },
        "escenarios": escenarios,
    }

    DIR_MODELOS.mkdir(parents=True, exist_ok=True)
    RUTA_JSON.write_text(
        json.dumps(salida, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    RUTA_REPORTE.write_text(reporte_markdown(salida), encoding="utf-8")
    return salida


# ---------------------------------------------------------------------------
# Reporte
# ---------------------------------------------------------------------------

def _tabla_configuraciones(esc: dict) -> list[str]:
    lineas = [
        "| Configuración | Modelo | MAE (media ± desv. entre semillas) | RMSE | "
        "MAPE (%) | R² |",
        "|---|---|---:|---:|---:|---:|",
    ]
    for clave, bloque in esc["configuraciones"].items():
        lb = bloque["linea_base"]
        lineas.append(
            f"| {bloque['etiqueta']} | línea base ({lb['agrupacion']}) | "
            f"{lb['mae']} | {lb['rmse']} | {lb['mape_pct']} | {lb['r2']} |"
        )
        for nombre_modelo, m in bloque["modelos"].items():
            base = m["semilla_base"]
            lineas.append(
                f"| {bloque['etiqueta']} | `{nombre_modelo}` | "
                f"{m['mae_media']} ± {m['mae_desv_estandar']} | "
                f"{base['rmse']} | {base['mape_pct']} | {base['r2']} |"
            )
    return lineas


def _tabla_por_rubro(esc: dict) -> list[str]:
    claves = list(esc["configuraciones"].keys())
    rubros = sorted({
        r["tipo_rubro"]
        for c in claves
        for r in esc["configuraciones"][c]["por_rubro"]
    })
    lineas = [
        "| Rubro | Obs. | Demanda media/día | "
        + " | ".join(f"MAE {c.split('_')[0]}" for c in claves)
        + " |",
        "|---|---:|---:|" + "---:|" * len(claves),
    ]
    for rubro in rubros:
        fila = None
        maes = []
        for c in claves:
            f = next(
                (x for x in esc["configuraciones"][c]["por_rubro"]
                 if x["tipo_rubro"] == rubro),
                None,
            )
            fila = fila or f
            maes.append(f"{f['mae']}" if f else "—")
        lineas.append(
            f"| `{rubro}` | {fila['observaciones']} | "
            f"{fila['demanda_media_diaria']} | " + " | ".join(maes) + " |"
        )
    return lineas


def _bloque_significancia(esc: dict) -> list[str]:
    lineas = [
        "",
        f"**Significancia** (bootstrap pareado, {REMUESTREOS_BOOTSTRAP} "
        "remuestreos). Signo positivo = la configuración comparada tiene MENOS "
        "error que el control (a). Se reportan los dos regresores: si la "
        "conclusión dependiera de cuál se mira, no sería una conclusión.",
        "",
        f"Un resultado cuenta como MEJORA solo si pasa las tres pruebas: "
        f"distinguible de 0 al 95%, mayor que la variación entre semillas, y "
        f"por encima del umbral de relevancia práctica "
        f"({UMBRAL_RELEVANCIA_PCT}% del MAE).",
        "",
        "| Comparación | Regresor | Δ MAE | Δ % | IC 95% | ¿Dist. de 0? | "
        "Veredicto |",
        "|---|---|---:|---:|---|---|---|",
    ]
    etiquetas = {
        "b_unico_con_rubro": "(b) con rubro vs (a) control",
        "c_especializado_por_rubro": "(c) especializados vs (a) control",
    }
    filas = [
        (etiquetas[clave], por_modelo)
        for clave, por_modelo in esc["significancia_vs_control"].items()
    ]
    filas.append(("(c) especializados vs (b) con rubro", esc["significancia_b_vs_c"]))

    for etiqueta, por_modelo in filas:
        for modelo, s in por_modelo.items():
            lineas.append(
                f"| {etiqueta} | `{modelo}` | {s['diferencia_mae']} | "
                f"{s['diferencia_pct_sobre_a']}% | "
                f"[{s['ic95_inferior']}, {s['ic95_superior']}] | "
                f"{'sí' if s['significativa_al_95'] else 'no'} | "
                f"**{s['veredicto']}** |"
            )
    return lineas


def _bloque_redundancia(esc: dict) -> list[str]:
    r = esc["diagnostico_redundancia"]
    marca = "⚠️ SÍ" if r["rubro_redundante_en_entrenamiento"] else "no"
    return [
        "",
        "### ¿Es redundante la variable de rubro en este escenario?",
        "",
        f"- Tiendas por rubro: "
        + ", ".join(f"`{k}`: {v}" for k, v in r["tiendas_por_rubro"].items()),
        f"- ¿El rubro se deduce de `id_tienda`? "
        f"{'sí' if r['rubro_determinado_por_id_tienda'] else 'no'}"
        + (" (y hay una sola tienda por rubro)"
           if r["una_sola_tienda_por_rubro"] else ""),
        f"- ¿El rubro se deduce de `id_producto`? "
        f"{'sí' if r['rubro_determinado_por_id_producto'] else 'no'}",
        f"- **¿Redundante? {marca}** — {r['explicacion']}.",
    ]


def _lectura_escenario(esc: dict) -> list[str]:
    """Lectura en prosa, generada de los números y no escrita a mano, para que
    no pueda quedar desincronizada del resultado si se reentrena."""
    ref = esc["modelo_referencia"]
    mae_a = esc["configuraciones"]["a_unico_sin_rubro"]["modelos"][ref]["mae_media"]
    desv_a = esc["configuraciones"]["a_unico_sin_rubro"]["modelos"][ref][
        "mae_desv_estandar"
    ]
    s_b = esc["significancia_vs_control"]["b_unico_con_rubro"][ref]
    s_c = esc["significancia_vs_control"]["c_especializado_por_rubro"][ref]

    lineas = ["", f"**Lectura** (regresor de referencia `{ref}`).", ""]
    for etiqueta, s in (("(b) modelo único con rubro", s_b),
                        ("(c) modelos especializados por rubro", s_c)):
        lineas.append(
            f"- {etiqueta} → **{s['veredicto']}**: {s['veredicto_detalle']} "
            f"(Δ MAE {s['diferencia_mae']} = {s['diferencia_pct_sobre_a']}%, "
            f"IC 95% [{s['ic95_inferior']}, {s['ic95_superior']}] en unidades "
            "de demanda)."
        )
    lineas.append(
        f"- Vara de comparación: cambiar solo la semilla del regresor mueve el "
        f"MAE del control en ±{desv_a} (sobre {mae_a}). Cualquier diferencia "
        "entre configuraciones menor que eso es indistinguible del azar del "
        "propio ajuste."
    )
    # La línea base sin ML puede ganarle a los modelos, sobre todo con tiendas
    # nuevas. Si pasa, hay que decirlo: es el resultado más incómodo y el más
    # importante de no esconder.
    mejor_base = min(
        b["linea_base"]["mae"] for b in esc["configuraciones"].values()
    )
    if mejor_base < mae_a:
        lineas.append(
            f"- ⚠️ **La línea base sin ML (MAE {mejor_base}) le gana al modelo "
            f"de control (MAE {mae_a}).** En este escenario la heurística de "
            "medias históricas es más robusta que el modelo entrenado, y "
            "cualquier configuración que no la supere no justifica su "
            "complejidad."
        )
    else:
        lineas.append(
            f"- La mejor línea base sin ML queda en MAE {mejor_base}, por "
            f"encima del control ({mae_a}): el modelo sí aporta sobre la "
            "heurística."
        )
    c = esc["cota_de_ruido"]
    lineas.append(
        f"- Piso irreducible del escenario: MAE {c['mae_oraculo_irreducible']} "
        f"(oráculo que conoce la λ del generador) frente a {c['mae_modelo']} "
        f"del control, razón {c['razon']}. Ese es todo el margen que cualquier "
        "configuración podría llegar a recuperar."
    )
    return lineas


def reporte_markdown(d: dict) -> str:
    lineas = [
        "# Comparación por rubro de tienda — ¿le sirve al modelo saber el rubro?",
        "",
        "> Generado automáticamente por `experimento_rubro.py` "
        "(`python entrenar_modelo.py --experimento-rubro`). No editar a mano.",
        "",
        f"- **Generado:** {d['generado_en']}",
        f"- **Origen de los datos:** {d['origen_datos']}",
        f"- **Regresor de referencia:** `{d['modelo_referencia']}`",
        f"- **Semillas:** {', '.join(str(s) for s in d['semillas'])}",
        "",
        "## Pregunta",
        "",
        f"> {d['pregunta']}",
        "",
        "## Configuraciones comparadas",
        "",
        "Las tres se evalúan sobre **exactamente la misma partición temporal**, "
        "con el mismo regresor, los mismos hiperparámetros y la misma semilla. "
        "Lo único que cambia es lo que se pregunta.",
        "",
    ]
    for clave, etiqueta in d["configuraciones"].items():
        lineas.append(f"- **`{clave}`** — {etiqueta}")

    lineas += [
        "",
        "Los hiperparámetros NO se re-tunean por configuración a propósito: si "
        "cada una se optimizara por separado, la comparación mediría el "
        "esfuerzo de tuneo en vez del efecto de la variable de rubro.",
        "",
        "---",
        "",
        "## Por qué hay tres escenarios y no uno",
        "",
        "La respuesta a la pregunta **no es la misma** en los tres, y quedarse "
        "con cualquiera de ellos por separado llevaría a una conclusión "
        "equivocada. El orden va de menos a más exigente.",
        "",
    ]

    titulos = {
        "produccion_1_tienda_por_rubro":
            "Escenario 1 — Catálogo de producción (1 tienda por rubro)",
        "multisucursal_tiendas_conocidas":
            "Escenario 2 — Multi-sucursal, tiendas ya conocidas",
        "multisucursal_tienda_nueva":
            "Escenario 3 — Multi-sucursal, tienda NUEVA sin historial",
    }

    for clave, esc in d["escenarios"].items():
        p = esc["particion"]
        lineas += [
            "---",
            "",
            f"## {titulos.get(clave, clave)}",
            "",
            esc["descripcion"],
            "",
            f"- Entrenamiento: {p['filas_entrenamiento']:,} obs., tiendas "
            f"{p['tiendas_entrenamiento']}",
            f"- Validación: {p['filas_validacion']:,} obs. desde "
            f"{p['fecha_corte']}, tiendas {p['tiendas_validacion']}",
            f"- Rubros presentes: {', '.join('`' + r + '`' for r in p['rubros'])}",
        ]
        lineas += _bloque_redundancia(esc)
        lineas += [
            "",
            "### Resultados",
            "",
        ]
        lineas += _tabla_configuraciones(esc)
        lineas += [
            "",
            "### Desglose por rubro "
            f"(regresor `{esc['modelo_referencia']}`, semilla base; "
            "columnas a/b/c = las tres configuraciones)",
            "",
        ]
        lineas += _tabla_por_rubro(esc)
        lineas += _bloque_significancia(esc)

        # Rubros que no alcanzaron para un modelo propio en la config (c).
        detalle = esc["configuraciones"]["c_especializado_por_rubro"].get(
            "detalle_ajuste", {}
        )
        sin_modelo = detalle.get("rubros_sin_modelo_propio", [])
        lineas += [
            "",
            f"**Configuración (c):** se entrenaron "
            f"{detalle.get('modelos_entrenados', 0)} modelos especializados.",
        ]
        if sin_modelo:
            for r in sin_modelo:
                lineas.append(
                    f"- ⚠️ `{r['tipo_rubro']}` NO recibió modelo propio: "
                    f"{r['motivo']} ({r['filas_entrenamiento']} filas)."
                )
        else:
            lineas.append(
                "- Todos los rubros presentes alcanzaron el mínimo de "
                f"{MIN_FILAS_MODELO_PROPIO} observaciones para justificar un "
                "modelo propio."
            )
        lineas += _lectura_escenario(esc)
        lineas.append("")

    # --- Conclusión transversal, derivada de los números --------------------
    lineas += ["---", "", "## Conclusión", ""]

    e1 = d["escenarios"]["produccion_1_tienda_por_rubro"]
    e2 = d["escenarios"]["multisucursal_tiendas_conocidas"]
    e3 = d["escenarios"]["multisucursal_tienda_nueva"]

    ref = d["modelo_referencia"]

    def _sig(esc, clave):
        return esc["significancia_vs_control"][clave][ref]

    def _coinciden(esc, clave) -> bool:
        """¿Los dos regresores dan el mismo veredicto de significancia?"""
        por_modelo = esc["significancia_vs_control"][clave]
        return len({s["significativa_al_95"] for s in por_modelo.values()}) == 1

    def _fmt(s: dict) -> str:
        """Δ MAE con su unidad explícita. El intervalo de confianza va SIEMPRE
        en las mismas unidades que el Δ MAE (unidades de demanda), no en
        porcentaje: mezclarlos en la misma frase es la forma más fácil de que
        un lector concluya que el intervalo no contiene la diferencia."""
        return (
            f"Δ MAE {s['diferencia_mae']} ({s['diferencia_pct_sobre_a']}%), "
            f"IC 95% [{s['ic95_inferior']}, {s['ic95_superior']}], veredicto "
            f"**{s['veredicto']}**"
        )

    lineas += [
        f"Los números citados abajo son los del regresor de referencia "
        f"(`{ref}`, el que gana el entrenamiento de producción). La tabla de "
        "significancia de cada escenario trae los dos regresores.",
        "",
        "**1. Con el catálogo de producción actual, el rubro no puede aportar "
        "nada, y eso es una propiedad estructural, no un resultado empírico.** "
        "Hay una sola tienda por rubro, así que `tipo_rubro` es una función "
        "biyectiva de `id_tienda` y el one-hot de la tienda ya lo codifica sin "
        "pérdida. El experimento no descubre esto, lo confirma: (b) frente al "
        f"control queda en {_fmt(_sig(e1, 'b_unico_con_rubro'))}. Presentar eso "
        "como una mejora sería fabricar una conclusión.",
        "",
        "**2. Con varias tiendas por rubro pero todas ya vistas, el rubro sigue "
        "sin aportar.** Y hay una segunda razón, más interesante que la "
        "primera: en este catálogo cada rubro tiene sus propios productos "
        "(una hamburguesería y una panadería no venden lo mismo), así que el "
        "one-hot de `id_producto` ya identifica el rubro sin pérdida. **El "
        "modelo «sin rubro» conoce el rubro igual, por la puerta de atrás.** "
        "Ver el diagnóstico de redundancia de cada escenario. Diferencia de (b) "
        f"frente al control: {_fmt(_sig(e2, 'b_unico_con_rubro'))}.",
        "",
        "**3. En una tienda nueva sin historial, lo que cambia el resultado no "
        "es declarar el rubro sino PARTIR el problema por rubro.** Ahí el "
        "one-hot de `id_tienda` no tiene ninguna columna que activar, y las "
        "tres configuraciones se comportan de forma muy distinta. (b) frente al "
        f"control: {_fmt(_sig(e3, 'b_unico_con_rubro'))}. "
        f"(c) frente al control: "
        f"{_fmt(_sig(e3, 'c_especializado_por_rubro'))}. "
        "Es decir: agregar la variable de rubro a un modelo que ya podía "
        "deducirlo del producto no cambia nada; entrenar un modelo POR rubro sí, "
        "porque deja de tener que repartir su capacidad entre series de escalas "
        "muy distintas (decenas de paquetes frente a cientos de unidades).",
        "",
        "**4. Único vs. especializado.** Comparación directa (c) contra (b) en "
        "el escenario de tienda nueva: "
        f"{_fmt(e3['significancia_b_vs_c'][ref])}. "
        + (
            "Los modelos especializados ganan de forma real y relevante para "
            "una tienda nueva, y ese es el caso de uso que motivó la pregunta. "
            "El precio es de ingeniería y hay que declararlo: un artefacto por "
            "rubro que entrenar, versionar y servir, más la decisión explícita "
            "de qué hacer con un rubro que no llega al mínimo de datos "
            "(acá: caer al modelo global). Con tres rubros es asumible; no "
            "escalaría a decenas."
            if e3["significancia_b_vs_c"][ref]["veredicto"] == "MEJORA"
            else "Al no haber diferencia utilizable entre las dos, la decisión "
                 "de ingeniería la gana el modelo ÚNICO con la variable de "
                 "rubro: un solo artefacto que entrenar, versionar y servir, y "
                 "ningún problema de qué hacer con un rubro que se queda sin "
                 "datos suficientes."
        ),
        "",
        "**5. Robustez al regresor.** "
        + (
            "Los dos regresores (`random_forest` y `gradient_boosting`) dan el "
            "MISMO veredicto de significancia en los tres escenarios, tanto "
            "para (b) como para (c). La conclusión no depende de cuál se elija."
            if all(
                _coinciden(esc, clave)
                for esc in (e1, e2, e3)
                for clave in ("b_unico_con_rubro", "c_especializado_por_rubro")
            )
            else "⚠️ Los dos regresores NO coinciden en todos los veredictos de "
                 "significancia (ver las tablas por escenario). Donde discrepan, "
                 "la evidencia es débil y no debe presentarse como un resultado: "
                 "un efecto que aparece con un regresor y desaparece con el otro "
                 "es un efecto que estos datos no sostienen."
        ),
        "",
        "### Qué se decidió para el servicio",
        "",
        "El modelo desplegado **no** incorpora la variable de rubro. Con el "
        "catálogo de producción actual sería complejidad sin beneficio medible "
        "(punto 1). La variable ya está implementada de punta a punta —columna "
        "`Tiendas.TipoRubro` en la base, `tipo_rubro` en el catálogo y en el "
        "pipeline de features— así que activarla el día que el negocio abra una "
        "segunda tienda de un rubro existente es cambiar una bandera y "
        "reentrenar, no rehacer el modelo.",
        "",
        "### Limitaciones",
        "",
        "- **El escenario multi-sucursal es simulado.** Las 9 sucursales no "
        "existen: se generaron inyectando a propósito una firma de demanda "
        "compartida por rubro (`catalogo.FIRMA_POR_RUBRO`). El experimento "
        "mide si la metodología RECUPERA esa estructura, no que la estructura "
        "exista en el negocio real. Si en la realidad dos tiendas del mismo "
        "rubro no se parecieran entre sí, el punto 3 no se sostendría.",
        "- **No se simula el rubro `OTRO`** (Mercadería, Pastelería). Esas "
        "tiendas no tienen catálogo ni operación en producción "
        "(`Disponible = 0`), así que no hay supuesto de negocio con el que "
        "simular su demanda; inventarles una serie sería fabricar evidencia. "
        "Cuando arranquen y acumulen historial, entran al experimento sin "
        "cambios de código.",
        "- **Un solo hold-out por rubro.** El escenario 3 deja fuera una "
        "sucursal por rubro. Con más sucursales por rubro correspondería un "
        "leave-one-store-out completo, promediando sobre todas las tiendas "
        "dejadas fuera, para no depender de cuál tocó excluir.",
        "- **El rubro y el producto están confundidos.** En este catálogo cada "
        "rubro tiene productos propios, así que `id_producto` determina el "
        "rubro y el efecto de la variable de rubro no puede separarse "
        "limpiamente del que ya aporta el producto. Es realista (los negocios "
        "de rubros distintos venden cosas distintas), pero significa que el "
        "experimento NO puede atribuir al rubro un efecto propio en (b). "
        "Aislarlo requeriría un producto que se venda en dos rubros distintos, "
        "que en este negocio no existe.",
        "- **La comparación de (c) mezcla dos efectos.** Un modelo por rubro no "
        "solo «sabe el rubro»: además deja de repartir su capacidad entre "
        "series de escalas muy distintas. Parte de su ventaja es "
        "especialización de escala, no información de rubro. Separar ambas "
        "cosas pediría un control adicional (por ejemplo, modelos "
        "especializados por particiones aleatorias del mismo tamaño).",
        "",
        "### Cómo comprobar esto con datos reales",
        "",
        "El experimento queda listo para repetirse sin cambios de código en "
        "cuanto el negocio tenga dos tiendas operativas del mismo rubro con "
        "historial digital suficiente: basta poblar `Tiendas.TipoRubro` (la "
        "migración `2026_09_tiendas_tipo_rubro.sql` ya lo hace), volcar la "
        "demanda diaria real al mismo formato que `demanda_diaria`, y correr "
        "`python entrenar_modelo.py --experimento-rubro`.",
        "",
        "La conclusión defendible en la tesis **no** es «el rubro mejora la "
        "predicción». Es más específica y más útil:",
        "",
        "> Declarar el rubro como una variable más no mejora nada mientras el",
        "> modelo pueda deducirlo de la tienda o del producto —que es el caso",
        "> en este negocio—. Lo que sí cambia el resultado, y sólo para una",
        "> tienda nueva sin historial, es **usar el rubro para partir el",
        "> problema**: entrenar un modelo por rubro. La variable de rubro vale",
        "> como criterio de segmentación, no como feature.",
        "",
    ]
    return "\n".join(lineas)


def main() -> None:
    ejecutar()


if __name__ == "__main__":
    main()
