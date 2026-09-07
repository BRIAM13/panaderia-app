# Reporte de validación — modelo de predicción de demanda

> Generado automáticamente por `entrenar_modelo.py`. No editar a mano.

- **Versión del modelo:** 1.0.0
- **Modelo seleccionado:** `random_forest` (menor MAE en el conjunto de validación temporal)
- **Entrenado:** 2026-09-06T04:57:43+00:00
- **Origen de los datos:** SINTÉTICO (data/entrenamiento.db) — no se usó la base de producción

## Partición temporal

- Tipo: temporal (cronológica, sin barajar)
- Entrenamiento: 2023-09-06 - 2026-01-29 (876 días, 3504 observaciones)
- Validación: 2026-01-29 - 2026-09-04 (219 días, 876 observaciones)

## Comparación de modelos (conjunto de validación)

| Modelo | MAE | RMSE | MAPE (%) | R² |
|---|---:|---:|---:|---:|
| `linea_base_estacional` | 48.859 | 73.068 | 20.245 | 0.7977 |
| `random_forest` **(seleccionado)** | 42.718 | 58.67 | 20.828 | 0.8696 |
| `gradient_boosting` | 46.055 | 61.228 | 24.716 | 0.858 |

## Desempeño por producto (modelo seleccionado)

| Tienda | Producto | Unidad | Demanda media/día | MAE | RMSE | MAPE (%) | R² |
|---|---|---|---:|---:|---:|---:|---:|
| Hamburguesas | Pan de Hamburguesa Clásico | PAQUETES | 73.33 | 15.906 | 20.287 | 24.16 | 0.3833 |
| Horneados | Producto Horneados General | UNIDADES | 147.79 | 36.006 | 48.36 | 26.636 | 0.4338 |
| Panadería | Pan de Agua | UNIDADES | 421.18 | 61.326 | 75.272 | 15.969 | 0.311 |
| Panadería | Pan Francés | UNIDADES | 367.27 | 57.633 | 73.16 | 16.546 | 0.3196 |

## Error del modelo vs. error irreducible

Un oráculo que conociera exactamente la demanda esperada del generador
seguiría equivocándose, porque la demanda observada es una realización
aleatoria. Ese es el piso teórico del problema. La razón de abajo separa
el error atribuible al modelo del azar irreducible del negocio.

| Producto | MAE modelo | MAE oráculo (piso) | Razón |
|---|---:|---:|---:|
| Pan de Hamburguesa Clásico | 15.906 | 14.416 | 1.103 |
| Producto Horneados General | 36.006 | 33.769 | 1.066 |
| Pan de Agua | 61.326 | 51.974 | 1.18 |
| Pan Francés | 57.633 | 51.434 | 1.121 |
| **Global** | **42.718** | **37.898** | **1.127** |

Es decir: el modelo comete un 12.7% más de error que el mejor predictor posible sobre estos datos. El resto del
error observado es ruido que ningún modelo puede eliminar.

Este diagnóstico solo puede calcularse porque los datos son sintéticos
(en datos reales la demanda esperada es desconocida). Valida la
METODOLOGÍA, no la exactitud futura en producción.

## Importancia de variables (modelo seleccionado)

| Variable | Importancia |
|---|---:|
| `id_tienda` | 0.7761 |
| `dias_desde_inicio` | 0.0397 |
| `id_producto` | 0.0362 |
| `es_fin_de_semana` | 0.0362 |
| `es_feriado` | 0.0241 |
| `dia_del_mes` | 0.0206 |
| `semana_anio` | 0.0177 |
| `es_vispera_feriado` | 0.0173 |
| `dia_semana` | 0.016 |
| `mes` | 0.0111 |
| `es_fin_de_mes` | 0.0022 |
| `es_quincena` | 0.0019 |
| `es_posterior_feriado` | 0.0009 |

## Comparación por rubro de tienda

¿Mejora la predicción si el modelo conoce el rubro de la tienda (pan de hamburguesa / panadería clásica / horneados), y conviene más un modelo único con esa variable o modelos especializados por rubro?

Resumen de tres configuraciones —(a) modelo único sin rubro, control; (b) modelo único con rubro; (c) modelos especializados por rubro— sobre la misma partición temporal. **El reporte completo, con el desglose por rubro, los intervalos de confianza y las limitaciones, está en `REPORTE_COMPARACION_RUBRO.md`.**

| Escenario | Δ MAE de (b) vs (a) | Δ MAE de (c) vs (a) | ¿Alguna diferencia distinguible de 0 al 95%? |
|---|---:|---:|---|
| 1. Producción (1 tienda por rubro) | 0.058% | 0.822% | **SÍ** |
| 2. Multi-sucursal, tiendas conocidas | -0.648% | -1.135% | **SÍ** |
| 3. Multi-sucursal, tienda NUEVA | 0.269% | 25.894% | **SÍ** |

Signo positivo = menos error que el control. Una diferencia cuyo intervalo de confianza contiene 0 NO es una mejora: es ruido, y así se reporta.

---

**Limitación declarada.** Estas métricas describen el desempeño del
modelo sobre un historial SINTÉTICO construido a partir de supuestos
declarados del negocio, no sobre ventas reales. Miden que la
metodología (features, partición temporal, elección de modelo)
recupera correctamente los patrones que se le inyectaron; no
constituyen una estimación del error que se obtendrá en producción.
El detalle de esta decisión de diseño está en el README del servicio.
