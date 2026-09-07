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

RUBRO DE TIENDA (`tipo_rubro`)
------------------------------
Cada tienda tiene un rubro, que se corresponde uno a uno con la columna
`Tiendas.TipoRubro` de `database_schema.sql` (ver la migración
`database_migrations/2026_09_tiendas_tipo_rubro.sql`). El rubro NO es el
nombre de la tienda: el nombre es una etiqueta comercial, el rubro describe
qué tipo de demanda tiene. Es el supuesto que se pone a prueba en el
experimento de `entrenar_modelo.py --experimento-rubro`.

Este módulo NO se conecta a ninguna base de datos. Es una tabla de constantes.
"""

from __future__ import annotations

from dataclasses import dataclass, asdict

# --- Rubros -----------------------------------------------------------------
# Mismo dominio que la constraint CK_Tiendas_TipoRubro de la base de producción.
# Si acá se agrega un valor, hay que agregarlo también allá (y al revés).

PAN_HAMBURGUESA = "PAN_HAMBURGUESA"
PANADERIA_CLASICA = "PANADERIA_CLASICA"
HORNEADOS = "HORNEADOS"
OTRO = "OTRO"

RUBROS_VALIDOS: tuple[str, ...] = (
    PAN_HAMBURGUESA,
    PANADERIA_CLASICA,
    HORNEADOS,
    OTRO,
)


@dataclass(frozen=True)
class Producto:
    """Un producto del catálogo sintético, con los parámetros que gobiernan
    la simulación de su demanda diaria."""

    id_producto: int
    id_tienda: int
    nombre_tienda: str
    nombre_producto: str
    unidad: str  # 'PAQUETES' | 'UNIDADES'
    # Rubro del negocio de la tienda. Uno de RUBROS_VALIDOS. Espeja
    # `Tiendas.TipoRubro` de la base de producción.
    tipo_rubro: str
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
    # Media y tope del tamaño de un pedido individual, para repartir el total
    # diario en filas con la misma granularidad que la tabla `Pedidos` real.
    tamano_pedido_medio: float = 10.0
    tamano_pedido_max: int = 60


CATALOGO: tuple[Producto, ...] = (
    Producto(
        id_producto=1,
        id_tienda=1,
        nombre_tienda="Hamburguesas",
        nombre_producto="Pan de Hamburguesa Clásico",
        unidad="PAQUETES",
        tipo_rubro=PAN_HAMBURGUESA,
        demanda_base=42.0,
        dispersion=0.22,
        crecimiento_anual=0.18,
        # Las parrillas/hamburgueserías compran más los fines de semana y en
        # fechas de reunión familiar: es el producto más estacional.
        sensibilidad_estacional=1.25,
        tamano_pedido_medio=2.5,
        tamano_pedido_max=8,
    ),
    Producto(
        id_producto=2,
        id_tienda=2,
        nombre_tienda="Horneados",
        nombre_producto="Producto Horneados General",
        unidad="UNIDADES",
        tipo_rubro=HORNEADOS,
        demanda_base=95.0,
        dispersion=0.30,
        crecimiento_anual=0.12,
        # Pastelería/horneados: fuerte en fechas celebratorias (Día de la
        # Madre, Navidad) pero plano entre semana.
        sensibilidad_estacional=1.40,
        tamano_pedido_medio=15.0,
        tamano_pedido_max=60,
    ),
    Producto(
        id_producto=3,
        id_tienda=3,
        nombre_tienda="Panadería",
        nombre_producto="Pan de Agua",
        unidad="UNIDADES",
        tipo_rubro=PANADERIA_CLASICA,
        demanda_base=310.0,
        dispersion=0.16,
        crecimiento_anual=0.10,
        # Pan de consumo diario: la demanda es la más estable de todas, la
        # gente compra pan todos los días llueva o truene.
        sensibilidad_estacional=0.70,
        tamano_pedido_medio=22.0,
        tamano_pedido_max=90,
    ),
    Producto(
        id_producto=4,
        id_tienda=3,
        nombre_tienda="Panadería",
        nombre_producto="Pan Francés",
        unidad="UNIDADES",
        tipo_rubro=PANADERIA_CLASICA,
        demanda_base=260.0,
        dispersion=0.18,
        crecimiento_anual=0.10,
        sensibilidad_estacional=0.75,
        tamano_pedido_medio=20.0,
        tamano_pedido_max=90,
    ),
)


# ---------------------------------------------------------------------------
# Catálogo AMPLIADO para el experimento de rubro
# ---------------------------------------------------------------------------
# Por qué hace falta un catálogo aparte:
#
# En el catálogo de producción de arriba hay exactamente UNA tienda por rubro.
# Con esa estructura, `tipo_rubro` es una función biyectiva de `id_tienda`: el
# one-hot de la tienda ya codifica el rubro sin pérdida de información, así que
# agregar la variable de rubro no puede aportar NADA — la pregunta de si el
# rubro ayuda queda respondida por construcción, no por evidencia.
#
# Para que la pregunta tenga poder estadístico hacen falta VARIAS tiendas por
# rubro. Este catálogo simula ese escenario: tres sucursales por rubro que
# comparten la firma de demanda de su rubro (sensibilidad estacional,
# dispersión, crecimiento) pero difieren en NIVEL (`demanda_base`), que es
# exactamente lo que se observa entre sucursales de un mismo negocio.
#
# ⚠️ SUPUESTO DECLARADO, NO HALLAZGO. Que las tiendas de un mismo rubro
# compartan firma de demanda es algo que este generador INYECTA a propósito.
# El experimento mide si el modelo logra recuperar esa estructura y bajo qué
# condiciones le sirve — no prueba que la estructura exista en el negocio real.
#
# Los identificadores empiezan en 11/101 para que sea IMPOSIBLE confundirlos
# con los IdTienda/IdProducto de producción. Estas tiendas no existen, no se
# sirven por la API y no entran al modelo desplegado: viven solo dentro de
# `entrenar_modelo.py --experimento-rubro`.
#
# No se simula el rubro 'OTRO' (Mercadería, Pastelería) a propósito: esas
# tiendas no tienen catálogo ni operación en producción (`Disponible = 0`), así
# que no hay ningún supuesto de negocio con el que simular su demanda.
# Inventarles una serie sería fabricar evidencia.

# Firma de demanda compartida por todas las tiendas de un mismo rubro:
# (dispersion, crecimiento_anual, sensibilidad_estacional).
FIRMA_POR_RUBRO: dict[str, tuple[float, float, float]] = {
    PAN_HAMBURGUESA: (0.22, 0.18, 1.25),
    HORNEADOS: (0.30, 0.12, 1.40),
    PANADERIA_CLASICA: (0.17, 0.10, 0.72),
}

# (id_tienda, nombre, rubro, [(id_producto, nombre, unidad, demanda_base)])
_SUCURSALES: tuple[tuple[int, str, str, tuple[tuple[int, str, str, float], ...]], ...] = (
    (11, "Hamburguesas Centro", PAN_HAMBURGUESA,
     ((101, "Pan de Hamburguesa Clásico", "PAQUETES", 42.0),)),
    (12, "Hamburguesas Norte", PAN_HAMBURGUESA,
     ((101, "Pan de Hamburguesa Clásico", "PAQUETES", 66.0),)),
    (13, "Hamburguesas Sur", PAN_HAMBURGUESA,
     ((101, "Pan de Hamburguesa Clásico", "PAQUETES", 28.0),)),

    (21, "Panadería Centro", PANADERIA_CLASICA,
     ((201, "Pan de Agua", "UNIDADES", 310.0),
      (202, "Pan Francés", "UNIDADES", 260.0))),
    (22, "Panadería Norte", PANADERIA_CLASICA,
     ((201, "Pan de Agua", "UNIDADES", 190.0),
      (202, "Pan Francés", "UNIDADES", 160.0))),
    (23, "Panadería Sur", PANADERIA_CLASICA,
     ((201, "Pan de Agua", "UNIDADES", 420.0),
      (202, "Pan Francés", "UNIDADES", 350.0))),

    (31, "Horneados Centro", HORNEADOS,
     ((301, "Producto Horneados General", "UNIDADES", 95.0),)),
    (32, "Horneados Norte", HORNEADOS,
     ((301, "Producto Horneados General", "UNIDADES", 140.0),)),
    (33, "Horneados Sur", HORNEADOS,
     ((301, "Producto Horneados General", "UNIDADES", 62.0),)),
)


def _construir_catalogo_experimento() -> tuple[Producto, ...]:
    productos: list[Producto] = []
    for id_tienda, nombre_tienda, rubro, items in _SUCURSALES:
        dispersion, crecimiento, sensibilidad = FIRMA_POR_RUBRO[rubro]
        for id_producto, nombre_producto, unidad, base in items:
            productos.append(
                Producto(
                    id_producto=id_producto,
                    id_tienda=id_tienda,
                    nombre_tienda=nombre_tienda,
                    nombre_producto=nombre_producto,
                    unidad=unidad,
                    tipo_rubro=rubro,
                    demanda_base=base,
                    dispersion=dispersion,
                    crecimiento_anual=crecimiento,
                    sensibilidad_estacional=sensibilidad,
                    tamano_pedido_medio=max(2.5, base / 15.0),
                    tamano_pedido_max=90,
                )
            )
    return tuple(productos)


CATALOGO_EXPERIMENTO_RUBRO: tuple[Producto, ...] = _construir_catalogo_experimento()

# Sucursales que se dejan FUERA del entrenamiento en la evaluación de "tienda
# nueva sin historial": una por rubro, para que el hold-out no desbalancee
# ningún rubro. Es el escenario donde el rubro puede aportar de verdad, porque
# el one-hot de `id_tienda` no tiene ninguna columna que activar.
TIENDAS_HOLDOUT_EXPERIMENTO: tuple[int, ...] = (13, 23, 33)


# ---------------------------------------------------------------------------
# Índices y consultas
# ---------------------------------------------------------------------------

POR_ID: dict[int, Producto] = {p.id_producto: p for p in CATALOGO}

# Mapeo tienda -> rubro. Incluye las tiendas del experimento para que
# `caracteristicas.py` pueda resolver el rubro de cualquiera de las dos
# poblaciones sin ramificar. Los rangos de IdTienda no se solapan, así que no
# hay ambigüedad posible.
RUBRO_POR_TIENDA: dict[int, str] = {
    **{p.id_tienda: p.tipo_rubro for p in CATALOGO},
    **{p.id_tienda: p.tipo_rubro for p in CATALOGO_EXPERIMENTO_RUBRO},
}


def rubro_de_tienda(id_tienda: int) -> str:
    """Rubro de una tienda, o 'OTRO' si no está mapeada.

    El fallback a 'OTRO' es deliberado y tiene que ser consistente entre
    entrenamiento e inferencia: una tienda desconocida NO debe hacer explotar
    la predicción, pero tampoco debe heredar el rubro de otra. 'OTRO' es
    además un valor que el OneHotEncoder ya vio si hubo tiendas 'OTRO' en
    entrenamiento, y si no lo vio, `handle_unknown='ignore'` lo deja en
    todo-ceros, que es exactamente la semántica de "no sé el rubro".
    """
    return RUBRO_POR_TIENDA.get(int(id_tienda), OTRO)


def indice_por_par(
    catalogo: tuple[Producto, ...] = CATALOGO,
) -> dict[tuple[int, int], Producto]:
    """Índice (id_tienda, id_producto) -> Producto.

    Hace falta además de `POR_ID` porque en el catálogo del experimento el
    MISMO id_producto se vende en varias sucursales del mismo rubro (que es
    justamente lo que permite dejar una tienda fuera sin dejar fuera también
    su producto), así que el id de producto por sí solo ya no identifica una
    serie.
    """
    return {(p.id_tienda, p.id_producto): p for p in catalogo}


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
