# Reporte de validación — modelo de predicción de demanda

> Generado automáticamente por `entrenar_modelo.py`. No editar a mano.

- **Versión del modelo:** 1.0.0
- **Modelo seleccionado:** `gradient_boosting` (menor MAE en el conjunto de validación temporal)
- **Entrenado:** 2026-08-30T05:48:53+00:00
- **Origen de los datos:** SINTÉTICO (data/entrenamiento.db) — no se usó la base de producción

## Partición temporal

- Tipo: temporal (cronológica, sin barajar)
- Entrenamiento: 2023-08-31 - 2026-01-23 (876 días, 3504 observaciones)
- Validación: 2026-01-23 - 2026-08-29 (219 días, 876 observaciones)

## Comparación de modelos (conjunto de validación)

| Modelo | MAE | RMSE | MAPE (%) | R² |
|---|---:|---:|---:|---:|
| `linea_base_estacional` | 47.999 | 72.304 | 19.676 | 0.8104 |
| `random_forest` | 41.816 | 58.164 | 19.808 | 0.8773 |
| `gradient_boosting` **(seleccionado)** | 41.708 | 57.015 | 20.228 | 0.8821 |

## Desempeño por producto (modelo seleccionado)

| Tienda | Producto | Unidad | Demanda media/día | MAE | RMSE | MAPE (%) | R² |
|---|---|---|---:|---:|---:|---:|---:|
| Hamburguesas | Pan de Hamburguesa Clásico | PAQUETES | 73.08 | 14.316 | 18.815 | 20.52 | 0.4258 |
| Horneados | Producto Horneados General | UNIDADES | 142.64 | 35.655 | 44.652 | 28.955 | 0.3112 |
| Panadería | Pan de Agua | UNIDADES | 429.7 | 58.793 | 72.815 | 14.27 | 0.4153 |
| Panadería | Pan Francés | UNIDADES | 366.8 | 58.069 | 73.164 | 17.166 | 0.4045 |

## Error del modelo vs. error irreducible

Un oráculo que conociera exactamente la demanda esperada del generador
seguiría equivocándose, porque la demanda observada es una realización
aleatoria. Ese es el piso teórico del problema. La razón de abajo separa
el error atribuible al modelo del azar irreducible del negocio.

| Producto | MAE modelo | MAE oráculo (piso) | Razón |
|---|---:|---:|---:|
| Pan de Hamburguesa Clásico | 14.316 | 12.294 | 1.164 |
| Producto Horneados General | 35.655 | 33.556 | 1.063 |
| Pan de Agua | 58.793 | 56.613 | 1.039 |
| Pan Francés | 58.069 | 52.737 | 1.101 |
| **Global** | **41.708** | **38.8** | **1.075** |

Es decir: el modelo comete un 7.5% más de error que el mejor predictor posible sobre estos datos. El resto del
error observado es ruido que ningún modelo puede eliminar.

Este diagnóstico solo puede calcularse porque los datos son sintéticos
(en datos reales la demanda esperada es desconocida). Valida la
METODOLOGÍA, no la exactitud futura en producción.

## Importancia de variables (modelo seleccionado)

| Variable | Importancia |
|---|---:|
| `id_tienda` | 0.7818 |
| `id_producto` | 0.0507 |
| `dias_desde_inicio` | 0.0377 |
| `es_fin_de_semana` | 0.0369 |
| `es_feriado` | 0.0259 |
| `es_vispera_feriado` | 0.0231 |
| `semana_anio` | 0.0113 |
| `dia_semana` | 0.0111 |
| `mes` | 0.0104 |
| `dia_del_mes` | 0.0071 |
| `es_posterior_feriado` | 0.0024 |
| `es_quincena` | 0.0009 |
| `es_fin_de_mes` | 0.0006 |

---

**Limitación declarada.** Estas métricas describen el desempeño del
modelo sobre un historial SINTÉTICO construido a partir de supuestos
declarados del negocio, no sobre ventas reales. Miden que la
metodología (features, partición temporal, elección de modelo)
recupera correctamente los patrones que se le inyectaron; no
constituyen una estimación del error que se obtendrá en producción.
El detalle de esta decisión de diseño está en el README del servicio.
