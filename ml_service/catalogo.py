"""
Catálogo de tiendas y productos usado por el microservicio de predicción.

IMPORTANTE (supuesto documentado): los identificadores de abajo replican los
IdTienda/IdProducto de la base de datos de producción tal como quedan tras el
seed de `database_schema.sql`:

    Tiendas:   1 = Hamburguesas, 2 = Horneados, 3 = Panadería
    Productos: 1 = Pan de Hamburguesa Clásico   (tienda 1, se vende por PAQUETE)
               2 = Producto Horneados General   (tienda 2, por UNIDAD)

Panadería todavía no tiene catálogo sembrado en `database_schema.sql`
(`Disponible = 0` en el seed), así que los productos 3 y 4 (Pan de Agua y Pan
Francés) son un supuesto del entorno sintético. Cuando Panadería tenga su
catálogo real en producción habrá que mapear esos IdProducto reales aquí y
volver a entrenar. Esa dependencia está aislada en este archivo a propósito:
es el único lugar donde hay que tocar los identificadores.

Este módulo NO se conecta a ninguna base de datos. Es una tabla de constantes.
"""

from __future__ import annotations

from dataclasses import dataclass, asdict


@dataclass(frozen=True)
class Producto:
    """Un producto del catálogo sintético, con los parámetros que gobiernan
    la simulación de su demanda diaria."""

    id_producto: int
    id_tienda: int
    nombre_tienda: str
    nombre_producto: str
    unidad: str  # 'PAQUETES' | 'UNIDADES'
    # Demanda media diaria al inicio de la ventana simulada (antes de aplicar
    # estacionalidad, feriados, tendencia y ruido).
    demanda_base: float
    # Cuánta dispersión relativa tiene la demanda de este producto: 0.20 = el
    # ruido diario típico es ~20% de la media. El pan por unidad rota mucho y
    # es más volátil que el pan por paquete, que se pide más planificado.
    dispersion: float
    # Crecimiento anual compuesto del negocio para este producto (0.18 = +18%
    # al año). Modela la migración progresiva de clientes al canal digital.
    crecimiento_anual: float
    # Sensibilidad a feriados y fines de semana: 1.0 = sigue el patrón
    # estándar del negocio; >1 lo amplifica; <1 lo amortigua.
    sensibilidad_estacional: float


CATALOGO: tuple[Producto, ...] = (
    Producto(
        id_producto=1,
        id_tienda=1,
        nombre_tienda="Hamburguesas",
        nombre_producto="Pan de Hamburguesa Clásico",
        unidad="PAQUETES",
        demanda_base=42.0,
        dispersion=0.22,
        crecimiento_anual=0.18,
        # Las parrillas/hamburgueserías compran más los fines de semana y en
        # fechas de reunión familiar: es el producto más estacional.
        sensibilidad_estacional=1.25,
    ),
    Producto(
        id_producto=2,
        id_tienda=2,
        nombre_tienda="Horneados",
        nombre_producto="Producto Horneados General",
        unidad="UNIDADES",
        demanda_base=95.0,
        dispersion=0.30,
        crecimiento_anual=0.12,
        # Pastelería/horneados: fuerte en fechas celebratorias (Día de la
        # Madre, Navidad) pero plano entre semana.
        sensibilidad_estacional=1.40,
        ),
    Producto(
        id_producto=3,
        id_tienda=3,
        nombre_tienda="Panadería",
        nombre_producto="Pan de Agua",
        unidad="UNIDADES",
        demanda_base=310.0,
        dispersion=0.16,
        crecimiento_anual=0.10,
        # Pan de consumo diario: la demanda es la más estable de todas, la
        # gente compra pan todos los días llueva o truene.
        sensibilidad_estacional=0.70,
    ),
    Producto(
        id_producto=4,
        id_tienda=3,
        nombre_tienda="Panadería",
        nombre_producto="Pan Francés",
        unidad="UNIDADES",
        demanda_base=260.0,
        dispersion=0.18,
        crecimiento_anual=0.10,
        sensibilidad_estacional=0.75,
    ),
)


POR_ID: dict[int, Producto] = {p.id_producto: p for p in CATALOGO}


def buscar(id_tienda: int, id_producto: int) -> Producto | None:
    """Devuelve el producto del catálogo, o None si el par tienda/producto no
    existe. Se valida el par completo (no solo el IdProducto) para que un
    IdTienda equivocado no pase silenciosamente al modelo."""
    producto = POR_ID.get(id_producto)
    if producto is None or producto.id_tienda != id_tienda:
        return None
    return producto


def como_lista() -> list[dict]:
    """Catálogo serializable, para exponerlo en `GET /info-modelo`."""
    return [asdict(p) for p in CATALOGO]
