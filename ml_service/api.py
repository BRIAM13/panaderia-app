"""
API HTTP del microservicio de predicción de demanda (FastAPI).

Endpoints
---------
    GET  /salud        healthcheck (no toca el modelo más allá de ver si cargó)
    GET  /info-modelo  métricas de validación, metadata y catálogo
    POST /predecir     predicción de demanda por tienda + producto + fecha(s)

Arranque:  uvicorn api:app --reload --port 8100   (desde el directorio ml_service)
Documentación interactiva:  http://127.0.0.1:8100/docs
"""

from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException

import catalogo
import esquemas
from predictor import ModeloNoDisponible, predictor

ADVERTENCIA = (
    "Predicción emitida por un modelo entrenado con datos SINTÉTICOS. Su "
    "precisión sobre la operación real mejorará conforme se acumule historial "
    "de pedidos digitales; úsala como apoyo a la decisión, no como cifra de "
    "producción."
)

LIMITACION = (
    "El modelo fue entrenado y validado sobre un historial sintético generado "
    "a partir de supuestos declarados del negocio, porque la base de datos de "
    "producción solo tiene ~131 pedidos reales en 24 días distintos, volumen "
    "insuficiente para entrenar ni validar una serie de tiempo. Las métricas "
    "de este endpoint miden la validez de la METODOLOGÍA sobre datos "
    "simulados, no el error esperado en producción."
)


@asynccontextmanager
async def ciclo_de_vida(app: FastAPI):
    # El modelo se carga una sola vez, al arrancar el proceso. Si todavía no
    # existe, el servicio igual levanta: /salud lo reporta y /predecir devuelve
    # 503 con instrucciones, en vez de que el proceso muera al arrancar.
    predictor.cargar()
    yield


app = FastAPI(
    title="Servicio de predicción de demanda — Panadería Ronceros",
    description=(
        "Microservicio de Machine Learning que estima la demanda diaria por "
        "tienda y producto.\n\n" + LIMITACION
    ),
    version="1.0.0",
    lifespan=ciclo_de_vida,
)


@app.get("/salud", response_model=esquemas.RespuestaSalud, tags=["operación"])
def salud() -> esquemas.RespuestaSalud:
    """Healthcheck. Devuelve 200 aunque el modelo no esté entrenado todavía;
    el campo `modeloCargado` es el que hay que mirar."""
    return esquemas.RespuestaSalud(
        estado="ok" if predictor.cargado else "sin_modelo",
        modeloCargado=predictor.cargado,
        versionModelo=predictor.version,
        nombreModelo=predictor.nombre,
        entrenadoEn=predictor.entrenado_en,
    )


@app.get("/info-modelo", response_model=esquemas.RespuestaInfoModelo, tags=["operación"])
def info_modelo() -> esquemas.RespuestaInfoModelo:
    """Metadata y métricas de validación del modelo en servicio."""
    m = predictor.metricas
    if not predictor.cargado or m is None:
        raise HTTPException(
            status_code=503,
            detail="No hay modelo entrenado. Corre: python entrenar_modelo.py",
        )
    return esquemas.RespuestaInfoModelo(
        versionModelo=m["version_modelo"],
        nombreModelo=m["modelo_seleccionado"],
        entrenadoEn=m["entrenado_en"],
        origenDatos=m["origen_datos"],
        particion=m["particion"],
        metricasValidacion=m["metricas_validacion"],
        metricasPorProducto=m["metricas_por_producto"],
        importanciaVariables=m["importancia_variables"],
        features=m["features"],
        catalogo=catalogo.como_lista(),
        limitacion=LIMITACION,
    )


@app.post("/predecir", response_model=esquemas.RespuestaPrediccion, tags=["predicción"])
def predecir(peticion: esquemas.PeticionPrediccion) -> esquemas.RespuestaPrediccion:
    """Predice la demanda diaria de un producto en una tienda.

    Acepta una `fecha` o una lista de `fechas`. El campo opcional
    `contextoReciente` permite al backend enviar el historial REAL reciente
    del negocio para calibrar la predicción (ver README).
    """
    producto = catalogo.buscar(peticion.idTienda, peticion.idProducto)
    if producto is None:
        raise HTTPException(
            status_code=404,
            detail=(
                f"El par idTienda={peticion.idTienda} / "
                f"idProducto={peticion.idProducto} no está en el catálogo del "
                "modelo. Consulta GET /info-modelo para ver los pares válidos."
            ),
        )

    contexto = [(o.fecha, o.cantidad) for o in (peticion.contextoReciente or [])]

    try:
        filas, factor, observaciones, motivo = predictor.predecir(
            peticion.lista_de_fechas(),
            peticion.idTienda,
            peticion.idProducto,
            contexto,
        )
    except ModeloNoDisponible as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc

    return esquemas.RespuestaPrediccion(
        idTienda=producto.id_tienda,
        idProducto=producto.id_producto,
        nombreTienda=producto.nombre_tienda,
        nombreProducto=producto.nombre_producto,
        unidad=producto.unidad,
        versionModelo=predictor.version or "desconocida",
        nombreModelo=predictor.nombre or "desconocido",
        ajusteContexto=esquemas.AjusteContexto(
            aplicado=factor != 1.0,
            factor=round(factor, 4),
            observacionesUsadas=observaciones,
            motivo=motivo,
        ),
        predicciones=[esquemas.PrediccionDia(**f) for f in filas],
        advertencia=ADVERTENCIA,
    )
