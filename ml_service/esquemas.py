"""
Contrato de entrada/salida de la API (modelos Pydantic).

Los campos van en camelCase (y no en snake_case como el resto del código
Python) porque el consumidor de esta API es el backend Node de producción y
el resto de la plataforma —app Flutter y página web— ya habla camelCase. El
contrato manda sobre la convención del lenguaje.
"""

from __future__ import annotations

from datetime import date
from typing import Any

from pydantic import BaseModel, Field, model_validator

# Tope de fechas por petición: suficiente para planificar un trimestre de
# producción y evita que una petición mal formada pida años enteros.
MAX_FECHAS = 90


class ObservacionReciente(BaseModel):
    """Un día del historial REAL reciente del negocio.

    Este es el gancho previsto para la integración futura: el backend Node
    podrá enviar los últimos días de demanda real observada y el servicio
    calibrará la predicción con ellos (ver `predictor.factor_de_contexto`).
    Mientras esa integración no exista, el campo simplemente no se envía y el
    modelo responde con su predicción base.
    """

    fecha: date
    cantidad: float = Field(ge=0, description="Demanda real observada ese día.")


class PeticionPrediccion(BaseModel):
    idTienda: int = Field(ge=1)
    idProducto: int = Field(ge=1)
    fecha: date | None = Field(
        default=None, description="Fecha única a predecir. Alternativa a `fechas`."
    )
    fechas: list[date] | None = Field(
        default=None,
        description=f"Lista de fechas a predecir (máximo {MAX_FECHAS}).",
    )
    contextoReciente: list[ObservacionReciente] | None = Field(
        default=None,
        description=(
            "OPCIONAL. Historial real reciente de esa tienda+producto. Si se "
            "envían al menos 3 observaciones, el servicio ajusta la predicción "
            "con un factor de calibración amortiguado. Ver README."
        ),
    )

    @model_validator(mode="after")
    def _validar_fechas(self) -> "PeticionPrediccion":
        if self.fecha is None and not self.fechas:
            raise ValueError("Debes enviar `fecha` o `fechas`.")
        if self.fecha is not None and self.fechas:
            raise ValueError("Envía `fecha` o `fechas`, no ambos.")
        if self.fechas and len(self.fechas) > MAX_FECHAS:
            raise ValueError(f"Máximo {MAX_FECHAS} fechas por petición.")
        return self

    def lista_de_fechas(self) -> list[date]:
        return [self.fecha] if self.fecha is not None else list(self.fechas or [])

    model_config = {
        "json_schema_extra": {
            "examples": [
                {
                    "idTienda": 3,
                    "idProducto": 3,
                    "fechas": ["2026-09-05", "2026-09-06", "2026-09-07"],
                }
            ]
        }
    }


class PrediccionDia(BaseModel):
    fecha: date
    diaSemana: str
    esFeriado: bool
    nombreFeriado: str | None
    demandaPredicha: int = Field(
        description="Predicción final redondeada, en la unidad del producto."
    )
    demandaPredichaBruta: float = Field(
        description="Predicción del modelo antes de redondear y de aplicar el "
        "ajuste por contexto reciente."
    )


class AjusteContexto(BaseModel):
    aplicado: bool
    factor: float = Field(description="Multiplicador aplicado a la predicción base.")
    observacionesUsadas: int
    motivo: str


class RespuestaPrediccion(BaseModel):
    idTienda: int
    idProducto: int
    nombreTienda: str
    nombreProducto: str
    unidad: str
    versionModelo: str
    nombreModelo: str
    ajusteContexto: AjusteContexto
    predicciones: list[PrediccionDia]
    advertencia: str


class RespuestaSalud(BaseModel):
    estado: str
    modeloCargado: bool
    versionModelo: str | None
    nombreModelo: str | None
    entrenadoEn: str | None


class RespuestaInfoModelo(BaseModel):
    versionModelo: str
    nombreModelo: str
    entrenadoEn: str
    origenDatos: str
    particion: dict[str, Any]
    metricasValidacion: dict[str, Any]
    metricasPorProducto: list[dict[str, Any]]
    importanciaVariables: list[dict[str, Any]]
    features: list[str]
    catalogo: list[dict[str, Any]]
    limitacion: str
