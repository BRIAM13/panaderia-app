"""
Calendario de fechas especiales del Perú.

Combina dos cosas distintas que al negocio le afectan igual:

1. Los feriados OFICIALES (los que trae la librería `holidays` para PE:
   Año Nuevo, Jueves/Viernes Santo, Día del Trabajo, San Pedro y San Pablo,
   Fiestas Patrias 28-29 de julio, Santa Rosa de Lima, Combate de Angamos,
   Todos los Santos, Inmaculada Concepción, Navidad, etc.).

2. Fechas COMERCIALES que no son feriado pero mueven la demanda de una
   panadería tanto o más que uno: Día de la Madre, Día del Padre, Nochebuena,
   Noche de Año Nuevo y el Día del Pollo a la Brasa (tercer domingo de julio,
   fecha de alto consumo de pan de acompañamiento en Lima).

Cada fecha lleva una `intensidad`: un multiplicador de demanda relativo que
usa ÚNICAMENTE el generador de datos sintéticos. El modelo de ML no recibe la
intensidad ni el nombre del feriado — solo ve las banderas booleanas
`es_feriado` / `es_vispera_feriado` / `es_posterior_feriado`. Esto es
deliberado: con ~3 años simulados cada feriado concreto aparece 3 veces, muy
poco para estimar un efecto propio por feriado sin sobreajustar. El modelo
tiene que inferir el efecto agregado a partir de esas banderas más el mes,
igual que tendrá que hacerlo con datos reales.
"""

from __future__ import annotations

from datetime import date, timedelta
from functools import lru_cache

import holidays

# Intensidad por defecto de un feriado oficial que no esté en la tabla de
# abajo: sube la demanda un 25%.
INTENSIDAD_POR_DEFECTO = 1.25

# Multiplicadores de demanda por fecha señalada. Son supuestos del negocio
# (panadería familiar en Lima), no cifras medidas: están documentados en el
# README para que la tesis pueda citarlos como parámetros de la simulación.
INTENSIDAD: dict[str, float] = {
    "Nochebuena": 2.10,          # el pico más alto del año
    "Navidad": 1.55,
    "Noche de Año Nuevo": 1.85,
    "Año Nuevo": 1.40,
    "Día de la Madre": 1.75,
    "Día del Padre": 1.45,
    "Fiestas Patrias": 1.70,     # 28 y 29 de julio
    "Día del Pollo a la Brasa": 1.35,
    "Jueves Santo": 1.30,
    "Viernes Santo": 1.30,
    "Día del Trabajo": 1.20,
    "Todos los Santos": 1.20,
}


def _domingo_n(anio: int, mes: int, n: int) -> date:
    """N-ésimo domingo de un mes (n=1 → el primero)."""
    d = date(anio, mes, 1)
    # weekday(): lunes=0 … domingo=6
    dias_hasta_domingo = (6 - d.weekday()) % 7
    return d + timedelta(days=dias_hasta_domingo + 7 * (n - 1))


def _fechas_comerciales(anio: int) -> dict[date, str]:
    return {
        _domingo_n(anio, 5, 2): "Día de la Madre",
        _domingo_n(anio, 6, 3): "Día del Padre",
        _domingo_n(anio, 7, 3): "Día del Pollo a la Brasa",
        date(anio, 12, 24): "Nochebuena",
        date(anio, 12, 31): "Noche de Año Nuevo",
    }


@lru_cache(maxsize=8)
def calendario(anio_inicio: int, anio_fin: int) -> dict[date, str]:
    """Mapa {fecha: nombre} de feriados oficiales + fechas comerciales para el
    rango de años pedido (ambos extremos incluidos)."""
    anios = list(range(anio_inicio, anio_fin + 1))
    oficiales = holidays.country_holidays("PE", years=anios)

    mapa: dict[date, str] = {}
    for fecha, nombre in oficiales.items():
        # `holidays` puede devolver el 28 y 29 de julio con nombres largos;
        # los normalizamos para poder asignarles una intensidad conjunta.
        if fecha.month == 7 and fecha.day in (28, 29):
            nombre = "Fiestas Patrias"
        mapa[fecha] = nombre

    for anio in anios:
        # Las fechas comerciales se agregan después para que, si coinciden con
        # un feriado oficial, gane el nombre comercial (más específico para el
        # negocio: p. ej. Nochebuena pesa más que cualquier otra cosa).
        mapa.update(_fechas_comerciales(anio))

    return mapa


def _cal_para(fecha: date) -> dict[date, str]:
    # Un año de margen a cada lado para que víspera/posterior funcionen en los
    # bordes (31 de diciembre ↔ 1 de enero del año siguiente).
    return calendario(fecha.year - 1, fecha.year + 1)


def es_feriado(fecha: date) -> bool:
    return fecha in _cal_para(fecha)


def nombre_feriado(fecha: date) -> str | None:
    return _cal_para(fecha).get(fecha)


def intensidad_feriado(fecha: date) -> float:
    """Multiplicador de demanda de la fecha (1.0 = día normal). Solo lo usa el
    generador sintético."""
    nombre = nombre_feriado(fecha)
    if nombre is None:
        return 1.0
    return INTENSIDAD.get(nombre, INTENSIDAD_POR_DEFECTO)


def es_vispera_feriado(fecha: date) -> bool:
    """El día ANTES de un feriado suele ser el de mayor demanda real: la gente
    compra el pan la víspera porque el feriado abre menos horas."""
    return es_feriado(fecha + timedelta(days=1))


def es_posterior_feriado(fecha: date) -> bool:
    """El día DESPUÉS de un feriado tiende a caer: la despensa ya está llena."""
    return es_feriado(fecha - timedelta(days=1))
