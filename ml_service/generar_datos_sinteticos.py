"""
Generador del historial de pedidos SINTÉTICO para entrenar el modelo.

Por qué sintético
-----------------
La base de datos de producción tiene ~131 pedidos reales repartidos en 24 días
distintos (Hamburguesas 114, Horneados 5, Panadería 12, y Panadería solo cubre
5 días consecutivos). Con ese volumen no se puede entrenar ni —sobre todo—
VALIDAR un modelo de series de tiempo: no hay ni un ciclo semanal completo por
tienda, mucho menos un ciclo anual con feriados. Entrenar ahí produciría
métricas sin sentido estadístico.

La decisión de diseño (tomada explícitamente por el dueño del negocio) es
entrenar y validar sobre un historial sintético construido a partir de
supuestos declarados del negocio, en una base SQLite LOCAL y separada, y
documentar abiertamente la limitación. Este script NUNCA se conecta a MariaDB
ni a ninguna base de producción: su única salida es `data/entrenamiento.db`.

Modelo generativo
-----------------
Para cada día `d` y producto `p` la demanda esperada es multiplicativa:

    λ(d,p) = base_p
             × (1 + crecimiento_p) ** (días_transcurridos / 365)     tendencia
             × dow[día_semana] ** sens_p                             ciclo semanal
             × mes[mes]                                              ciclo anual
             × intensidad_feriado(d) ** sens_p                       feriados
             × vispera / posterior                                   efecto borde
             × quincena / fin de mes                                 ciclo de pago

y la demanda observada se sortea de una Binomial Negativa de media λ, cuya
sobredispersión se calibra con el parámetro `dispersion` de cada producto.
La Binomial Negativa (y no una Normal) porque la demanda es un conteo entero
no negativo y con varianza mayor que la media, que es lo que se observa en el
comercio minorista.

Ese total diario se reparte luego en pedidos individuales de tamaño aleatorio,
para que la tabla resultante tenga la misma forma que la tabla `Pedidos` de
producción y no un agregado ya cocinado.
"""

from __future__ import annotations

import argparse
import json
import sqlite3
from datetime import date, timedelta
from pathlib import Path

import numpy as np

import feriados_peru
from catalogo import CATALOGO, Producto

RUTA_BD = Path(__file__).parent / "data" / "entrenamiento.db"

# --- Parámetros de la simulación (supuestos del negocio, ver README) --------

# Multiplicador por día de la semana (lunes = 0 … domingo = 6). Viernes,
# sábado y domingo concentran la demanda de una panadería de barrio.
FACTOR_DIA_SEMANA = {
    0: 0.92,  # lunes
    1: 0.90,  # martes
    2: 0.93,  # miércoles
    3: 0.98,  # jueves
    4: 1.12,  # viernes
    5: 1.30,  # sábado
    6: 1.22,  # domingo
}

# Multiplicador por mes: diciembre y julio (Fiestas Patrias + vacaciones
# escolares) son los meses altos; el otoño limeño es el valle.
FACTOR_MES = {
    1: 1.05, 2: 0.98, 3: 0.97, 4: 0.96, 5: 1.02, 6: 0.97,
    7: 1.08, 8: 0.98, 9: 0.97, 10: 1.00, 11: 1.00, 12: 1.15,
}

FACTOR_VISPERA_FERIADO = 1.18   # la gente se abastece el día antes
FACTOR_POSTERIOR_FERIADO = 0.88  # y compra menos el día después
FACTOR_QUINCENA = 1.06
FACTOR_FIN_DE_MES = 1.05

# Tamaño típico de un pedido por producto (media de la geométrica que reparte
# el total diario en pedidos individuales) y tope por pedido.
TAMANO_PEDIDO = {
    1: (2.5, 8),     # paquetes de pan de hamburguesa
    2: (15.0, 60),   # unidades de horneados
    3: (22.0, 90),   # unidades de pan de agua
    4: (20.0, 90),   # unidades de pan francés
}

# Reparto de los pedidos de Panadería entre los dos turnos de recojo
# (la hornada de la mañana sale ~4am y la de la tarde ~3pm).
PROBABILIDAD_TURNO_MANANA = 0.62


def factor_dia(fecha: date, producto: Producto) -> float:
    """Multiplicador determinista de demanda del día para ese producto (todo
    menos el ruido aleatorio)."""
    sens = producto.sensibilidad_estacional

    factor = FACTOR_DIA_SEMANA[fecha.weekday()] ** sens
    factor *= FACTOR_MES[fecha.month]
    factor *= feriados_peru.intensidad_feriado(fecha) ** sens

    if feriados_peru.es_vispera_feriado(fecha):
        factor *= FACTOR_VISPERA_FERIADO
    if feriados_peru.es_posterior_feriado(fecha):
        factor *= FACTOR_POSTERIOR_FERIADO
    if 14 <= fecha.day <= 16:
        factor *= FACTOR_QUINCENA
    if fecha.day >= 28 or fecha.day <= 2:
        factor *= FACTOR_FIN_DE_MES

    return factor


def sortear_demanda(rng: np.random.Generator, media: float, dispersion: float) -> int:
    """Sortea la demanda del día de una Binomial Negativa de media `media` y
    desviación relativa aproximada `dispersion`.

    Si la varianza pedida no supera a la media (posible cuando la media es muy
    baja), la Binomial Negativa no está definida y se cae a una Poisson, que es
    su caso límite equidisperso.
    """
    if media <= 0:
        return 0
    varianza = (dispersion * media) ** 2
    if varianza <= media:
        return int(rng.poisson(media))
    n = media**2 / (varianza - media)
    p = n / (n + media)
    return int(rng.negative_binomial(n, p))


def repartir_en_pedidos(
    rng: np.random.Generator, total: int, id_producto: int
) -> list[int]:
    """Reparte la demanda total de un día en pedidos individuales de tamaño
    aleatorio, para reproducir la granularidad de la tabla `Pedidos` real."""
    if total <= 0:
        return []
    media_tamano, tope = TAMANO_PEDIDO[id_producto]
    pedidos: list[int] = []
    restante = total
    while restante > 0:
        # Geométrica desplazada: pedidos chicos frecuentes, algunos grandes.
        tamano = 1 + int(rng.geometric(1.0 / max(media_tamano, 1.0)) - 1)
        tamano = max(1, min(tamano, tope, restante))
        pedidos.append(tamano)
        restante -= tamano
    return pedidos


def generar(
    anios: float = 3.0,
    semilla: int = 20260830,
    fecha_fin: date | None = None,
    ruta_bd: Path = RUTA_BD,
) -> dict:
    """Genera el historial y lo escribe en SQLite. Devuelve un resumen."""
    rng = np.random.default_rng(semilla)

    fecha_fin = fecha_fin or (date.today() - timedelta(days=1))
    total_dias = int(round(anios * 365))
    fecha_inicio = fecha_fin - timedelta(days=total_dias - 1)

    filas_pedidos: list[tuple] = []
    filas_demanda: list[tuple] = []

    for offset in range(total_dias):
        fecha = fecha_inicio + timedelta(days=offset)
        for producto in CATALOGO:
            crecimiento = (1 + producto.crecimiento_anual) ** (offset / 365.0)
            media = producto.demanda_base * crecimiento * factor_dia(fecha, producto)
            total = sortear_demanda(rng, media, producto.dispersion)

            filas_demanda.append(
                (fecha.isoformat(), producto.id_tienda, producto.id_producto, total)
            )

            for cantidad in repartir_en_pedidos(rng, total, producto.id_producto):
                if producto.id_tienda == 3:
                    turno = (
                        "MANANA"
                        if rng.random() < PROBABILIDAD_TURNO_MANANA
                        else "TARDE"
                    )
                else:
                    turno = None
                filas_pedidos.append(
                    (
                        producto.id_tienda,
                        producto.id_producto,
                        producto.unidad,
                        cantidad,
                        fecha.isoformat(),
                        turno,
                        "ENTREGADO",
                    )
                )

    ruta_bd.parent.mkdir(parents=True, exist_ok=True)
    if ruta_bd.exists():
        ruta_bd.unlink()

    con = sqlite3.connect(ruta_bd)
    try:
        con.executescript(
            """
            CREATE TABLE pedidos_sinteticos (
                id_pedido     INTEGER PRIMARY KEY AUTOINCREMENT,
                id_tienda     INTEGER NOT NULL,
                id_producto   INTEGER NOT NULL,
                tipo_pedido   TEXT    NOT NULL,
                cantidad      INTEGER NOT NULL,
                fecha_entrega TEXT    NOT NULL,
                turno         TEXT,
                estado        TEXT    NOT NULL
            );

            -- Agregado diario: es lo que consume el entrenamiento. Se guarda
            -- materializado (y no como vista) para que el script de
            -- entrenamiento sea una lectura simple y reproducible.
            CREATE TABLE demanda_diaria (
                fecha       TEXT    NOT NULL,
                id_tienda   INTEGER NOT NULL,
                id_producto INTEGER NOT NULL,
                cantidad    INTEGER NOT NULL,
                PRIMARY KEY (fecha, id_tienda, id_producto)
            );

            CREATE TABLE metadata_generacion (
                clave TEXT PRIMARY KEY,
                valor TEXT NOT NULL
            );

            CREATE INDEX ix_pedidos_fecha ON pedidos_sinteticos(fecha_entrega);
            """
        )
        con.executemany(
            "INSERT INTO pedidos_sinteticos "
            "(id_tienda, id_producto, tipo_pedido, cantidad, fecha_entrega, turno, estado) "
            "VALUES (?, ?, ?, ?, ?, ?, ?)",
            filas_pedidos,
        )
        con.executemany(
            "INSERT INTO demanda_diaria (fecha, id_tienda, id_producto, cantidad) "
            "VALUES (?, ?, ?, ?)",
            filas_demanda,
        )

        metadata = {
            "semilla": semilla,
            "anios_simulados": anios,
            "fecha_inicio": fecha_inicio.isoformat(),
            "fecha_fin": fecha_fin.isoformat(),
            "dias": total_dias,
            "productos": [p.id_producto for p in CATALOGO],
            "factor_dia_semana": FACTOR_DIA_SEMANA,
            "factor_mes": FACTOR_MES,
            "origen": "SINTETICO — no proviene de la base de datos de producción",
        }
        con.executemany(
            "INSERT INTO metadata_generacion (clave, valor) VALUES (?, ?)",
            [(k, json.dumps(v, ensure_ascii=False)) for k, v in metadata.items()],
        )
        con.commit()
    finally:
        con.close()

    return {
        "ruta_bd": str(ruta_bd),
        "dias": total_dias,
        "fecha_inicio": fecha_inicio.isoformat(),
        "fecha_fin": fecha_fin.isoformat(),
        "filas_demanda_diaria": len(filas_demanda),
        "pedidos_generados": len(filas_pedidos),
        "unidades_totales": sum(f[3] for f in filas_pedidos),
    }


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Genera el historial de pedidos sintético en SQLite local."
    )
    parser.add_argument("--anios", type=float, default=3.0,
                        help="Años de historial a simular (por defecto 3).")
    parser.add_argument("--semilla", type=int, default=20260830,
                        help="Semilla del generador aleatorio (reproducibilidad).")
    args = parser.parse_args()

    resumen = generar(anios=args.anios, semilla=args.semilla)

    # Nota: la consola de Windows usa cp1252, que no sabe imprimir "→". Todo
    # lo que va a stdout se mantiene dentro de ese juego de caracteres; los
    # archivos que sí llevan Unicode se escriben con encoding="utf-8".
    print("Historial sintético generado")
    print(f"  Base de datos    : {resumen['ruta_bd']}")
    print(f"  Rango            : {resumen['fecha_inicio']} - {resumen['fecha_fin']}"
          f" ({resumen['dias']} días)")
    print(f"  Filas demanda    : {resumen['filas_demanda_diaria']:,}")
    print(f"  Pedidos          : {resumen['pedidos_generados']:,}")
    print(f"  Unidades/paquetes: {resumen['unidades_totales']:,}")


if __name__ == "__main__":
    main()
