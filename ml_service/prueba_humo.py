"""
Prueba de humo del servicio: verifica de punta a punta que un servidor ya
levantado responde correctamente los tres endpoints.

Uso (con el servidor corriendo en otra terminal):

    python prueba_humo.py
    python prueba_humo.py --url http://127.0.0.1:8100

No reemplaza a una suite de pruebas: comprueba que el servicio está vivo, que
el modelo cargó y que el contrato de `/predecir` responde lo esperado —
incluida la rama del `contextoReciente` opcional.
"""

from __future__ import annotations

import argparse
import sys
from datetime import date, timedelta

import httpx

URL_POR_DEFECTO = "http://127.0.0.1:8100"

fallos: list[str] = []


def revisar(condicion: bool, descripcion: str) -> None:
    marca = "OK  " if condicion else "FALLA"
    print(f"  [{marca}] {descripcion}")
    if not condicion:
        fallos.append(descripcion)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default=URL_POR_DEFECTO)
    args = parser.parse_args()
    base = args.url.rstrip("/")

    cliente = httpx.Client(base_url=base, timeout=30.0)

    print("\n1) GET /salud")
    r = cliente.get("/salud")
    revisar(r.status_code == 200, f"responde 200 (fue {r.status_code})")
    salud = r.json()
    revisar(salud.get("modeloCargado") is True, "el modelo está cargado en memoria")
    print(f"       version={salud.get('versionModelo')} "
          f"modelo={salud.get('nombreModelo')}")

    print("\n2) GET /info-modelo")
    r = cliente.get("/info-modelo")
    revisar(r.status_code == 200, f"responde 200 (fue {r.status_code})")
    info = r.json()
    revisar("metricasValidacion" in info, "expone las métricas de validación")
    revisar(len(info.get("catalogo", [])) > 0, "expone el catálogo de productos")
    mae = info["metricasValidacion"][info["nombreModelo"]]["mae"]
    print(f"       MAE del modelo en servicio = {mae}")

    print("\n3) POST /predecir (una sola fecha)")
    manana = date.today() + timedelta(days=1)
    r = cliente.post("/predecir", json={
        "idTienda": 3, "idProducto": 3, "fecha": manana.isoformat(),
    })
    revisar(r.status_code == 200, f"responde 200 (fue {r.status_code})")
    cuerpo = r.json()
    revisar(len(cuerpo["predicciones"]) == 1, "devuelve exactamente 1 predicción")
    revisar(cuerpo["predicciones"][0]["demandaPredicha"] > 0,
            "la demanda predicha es positiva")
    revisar(cuerpo["ajusteContexto"]["aplicado"] is False,
            "sin contexto, no se aplica ajuste")
    p = cuerpo["predicciones"][0]
    print(f"       {p['fecha']} ({p['diaSemana']}) -> {p['demandaPredicha']} "
          f"{cuerpo['unidad']}")

    print("\n4) POST /predecir (varias fechas)")
    fechas = [(date.today() + timedelta(days=d)).isoformat() for d in range(1, 8)]
    r = cliente.post("/predecir", json={
        "idTienda": 1, "idProducto": 1, "fechas": fechas,
    })
    revisar(r.status_code == 200, f"responde 200 (fue {r.status_code})")
    cuerpo = r.json()
    revisar(len(cuerpo["predicciones"]) == 7, "devuelve 7 predicciones")
    for p in cuerpo["predicciones"]:
        print(f"       {p['fecha']} ({p['diaSemana']:<10}) -> "
              f"{p['demandaPredicha']:>5} {cuerpo['unidad']}")

    print("\n5) POST /predecir con contextoReciente (integración futura)")
    # Contexto deliberadamente alto: el factor debe subir, pero amortiguado.
    contexto = [
        {"fecha": (date.today() - timedelta(days=d)).isoformat(), "cantidad": 600}
        for d in range(1, 8)
    ]
    r = cliente.post("/predecir", json={
        "idTienda": 3, "idProducto": 3,
        "fecha": manana.isoformat(),
        "contextoReciente": contexto,
    })
    revisar(r.status_code == 200, f"responde 200 (fue {r.status_code})")
    cuerpo = r.json()
    ajuste = cuerpo["ajusteContexto"]
    revisar(ajuste["aplicado"] is True, "el ajuste por contexto se aplicó")
    revisar(0.70 <= ajuste["factor"] <= 1.30, "el factor está dentro del recorte")
    revisar(ajuste["observacionesUsadas"] == 7, "usó las 7 observaciones enviadas")
    print(f"       factor={ajuste['factor']} -> "
          f"{cuerpo['predicciones'][0]['demandaPredicha']} {cuerpo['unidad']} "
          f"(bruta {cuerpo['predicciones'][0]['demandaPredichaBruta']})")

    print("\n6) POST /predecir con un par tienda/producto inexistente")
    r = cliente.post("/predecir", json={
        "idTienda": 99, "idProducto": 99, "fecha": manana.isoformat(),
    })
    revisar(r.status_code == 404, f"responde 404 (fue {r.status_code})")

    print("\n7) POST /predecir sin fecha ni fechas")
    r = cliente.post("/predecir", json={"idTienda": 1, "idProducto": 1})
    revisar(r.status_code == 422, f"responde 422 (fue {r.status_code})")

    cliente.close()

    print()
    if fallos:
        print(f"RESULTADO: {len(fallos)} verificación(es) fallaron")
        for f in fallos:
            print(f"  - {f}")
        return 1
    print("RESULTADO: todas las verificaciones pasaron")
    return 0


if __name__ == "__main__":
    sys.exit(main())
