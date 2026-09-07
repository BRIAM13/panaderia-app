# Comparación por rubro de tienda — ¿le sirve al modelo saber el rubro?

> Generado automáticamente por `experimento_rubro.py` (`python entrenar_modelo.py --experimento-rubro`). No editar a mano.

- **Generado:** 2026-09-06T04:57:41+00:00
- **Origen de los datos:** SINTÉTICO — no se usó la base de producción
- **Regresor de referencia:** `random_forest`
- **Semillas:** 42, 7, 101, 2024, 31337

## Pregunta

> ¿Mejora la predicción de demanda si el modelo conoce el rubro de la tienda, y conviene más un modelo único con esa variable o modelos especializados por rubro?

## Configuraciones comparadas

Las tres se evalúan sobre **exactamente la misma partición temporal**, con el mismo regresor, los mismos hiperparámetros y la misma semilla. Lo único que cambia es lo que se pregunta.

- **`a_unico_sin_rubro`** — (a) Modelo único SIN rubro
- **`b_unico_con_rubro`** — (b) Modelo único CON rubro
- **`c_especializado_por_rubro`** — (c) Modelos especializados por rubro

Los hiperparámetros NO se re-tunean por configuración a propósito: si cada una se optimizara por separado, la comparación mediría el esfuerzo de tuneo en vez del efecto de la variable de rubro.

---

## Por qué hay tres escenarios y no uno

La respuesta a la pregunta **no es la misma** en los tres, y quedarse con cualquiera de ellos por separado llevaría a una conclusión equivocada. El orden va de menos a más exigente.

---

## Escenario 1 — Catálogo de producción (1 tienda por rubro)

Las 3 tiendas del catálogo de producción (una por rubro). El rubro es una función biyectiva de `id_tienda`, así que es redundante por construcción: este escenario cuantifica esa redundancia.

- Entrenamiento: 3,504 obs., tiendas [1, 2, 3]
- Validación: 876 obs. desde 2026-01-29, tiendas [1, 2, 3]
- Rubros presentes: `HORNEADOS`, `PANADERIA_CLASICA`, `PAN_HAMBURGUESA`

### ¿Es redundante la variable de rubro en este escenario?

- Tiendas por rubro: `HORNEADOS`: 1, `PANADERIA_CLASICA`: 1, `PAN_HAMBURGUESA`: 1
- ¿El rubro se deduce de `id_tienda`? sí (y hay una sola tienda por rubro)
- ¿El rubro se deduce de `id_producto`? sí
- **¿Redundante? ⚠️ SÍ** — el one-hot de `id_tienda` codifica el rubro sin pérdida (hay una sola tienda por rubro).

### Resultados

| Configuración | Modelo | MAE (media ± desv. entre semillas) | RMSE | MAPE (%) | R² |
|---|---|---:|---:|---:|---:|
| (a) Modelo único SIN rubro | línea base (tienda+producto+día de la semana) | 48.859 | 73.068 | 20.245 | 0.7977 |
| (a) Modelo único SIN rubro | `random_forest` | 42.5036 ± 0.1728 | 58.67 | 20.828 | 0.8696 |
| (a) Modelo único SIN rubro | `gradient_boosting` | 46.1408 ± 0.647 | 61.228 | 24.716 | 0.858 |
| (b) Modelo único CON rubro | línea base (rubro+producto+día de la semana) | 48.859 | 73.068 | 20.245 | 0.7977 |
| (b) Modelo único CON rubro | `random_forest` | 42.4886 ± 0.1939 | 58.642 | 20.784 | 0.8697 |
| (b) Modelo único CON rubro | `gradient_boosting` | 46.089 ± 1.8338 | 63.305 | 24.2 | 0.8482 |
| (c) Modelos especializados por rubro | línea base (rubro+producto+día de la semana) | 48.859 | 73.068 | 20.245 | 0.7977 |
| (c) Modelos especializados por rubro | `random_forest` | 42.5296 ± 0.1819 | 58.174 | 20.675 | 0.8718 |
| (c) Modelos especializados por rubro | `gradient_boosting` | 45.2866 ± 1.8393 | 60.374 | 22.59 | 0.8619 |

### Desglose por rubro (regresor `random_forest`, semilla base; columnas a/b/c = las tres configuraciones)

| Rubro | Obs. | Demanda media/día | MAE a | MAE b | MAE c |
|---|---:|---:|---:|---:|---:|
| `HORNEADOS` | 219 | 147.79 | 36.006 | 35.993 | 35.936 |
| `PANADERIA_CLASICA` | 438 | 394.23 | 59.48 | 59.451 | 58.815 |
| `PAN_HAMBURGUESA` | 219 | 73.33 | 15.906 | 15.877 | 15.903 |

**Significancia** (bootstrap pareado, 2000 remuestreos). Signo positivo = la configuración comparada tiene MENOS error que el control (a). Se reportan los dos regresores: si la conclusión dependiera de cuál se mira, no sería una conclusión.

Un resultado cuenta como MEJORA solo si pasa las tres pruebas: distinguible de 0 al 95%, mayor que la variación entre semillas, y por encima del umbral de relevancia práctica (1.0% del MAE).

| Comparación | Regresor | Δ MAE | Δ % | IC 95% | ¿Dist. de 0? | Veredicto |
|---|---|---:|---:|---|---|---|
| (b) con rubro vs (a) control | `random_forest` | 0.0249 | 0.058% | [-0.0209, 0.0698] | no | **sin efecto** |
| (b) con rubro vs (a) control | `gradient_boosting` | -0.9918 | -2.154% | [-1.7395, -0.2465] | sí | **EMPEORA** |
| (c) especializados vs (a) control | `random_forest` | 0.3511 | 0.822% | [0.1516, 0.5505] | sí | **irrelevante** |
| (c) especializados vs (a) control | `gradient_boosting` | 1.5544 | 3.375% | [0.1895, 2.9715] | sí | **MEJORA** |
| (c) especializados vs (b) con rubro | `random_forest` | 0.3261 | 0.764% | [0.1251, 0.5242] | sí | **irrelevante** |
| (c) especializados vs (b) con rubro | `gradient_boosting` | 2.5463 | 5.412% | [1.029, 4.0424] | sí | **MEJORA** |

**Configuración (c):** se entrenaron 3 modelos especializados.
- Todos los rubros presentes alcanzaron el mínimo de 400 observaciones para justificar un modelo propio.

**Lectura** (regresor de referencia `random_forest`).

- (b) modelo único con rubro → **sin efecto**: el IC 95% contiene 0: no hay evidencia de diferencia (Δ MAE 0.0249 = 0.058%, IC 95% [-0.0209, 0.0698] en unidades de demanda).
- (c) modelos especializados por rubro → **irrelevante**: distinguible de 0 pero solo 0.822% del MAE, por debajo del umbral de relevancia práctica (1.0%): es real y no sirve para nada (Δ MAE 0.3511 = 0.822%, IC 95% [0.1516, 0.5505] en unidades de demanda).
- Vara de comparación: cambiar solo la semilla del regresor mueve el MAE del control en ±0.1728 (sobre 42.5036). Cualquier diferencia entre configuraciones menor que eso es indistinguible del azar del propio ajuste.
- La mejor línea base sin ML queda en MAE 48.859, por encima del control (42.5036): el modelo sí aporta sobre la heurística.
- Piso irreducible del escenario: MAE 37.898 (oráculo que conoce la λ del generador) frente a 42.718 del control, razón 1.127. Ese es todo el margen que cualquier configuración podría llegar a recuperar.

---

## Escenario 2 — Multi-sucursal, tiendas ya conocidas

9 sucursales (3 por rubro), partición temporal estándar: todas las tiendas de validación ya se vieron en entrenamiento.

- Entrenamiento: 10,512 obs., tiendas [11, 12, 13, 21, 22, 23, 31, 32, 33]
- Validación: 2,628 obs. desde 2026-01-29, tiendas [11, 12, 13, 21, 22, 23, 31, 32, 33]
- Rubros presentes: `HORNEADOS`, `PANADERIA_CLASICA`, `PAN_HAMBURGUESA`

### ¿Es redundante la variable de rubro en este escenario?

- Tiendas por rubro: `HORNEADOS`: 3, `PANADERIA_CLASICA`: 3, `PAN_HAMBURGUESA`: 3
- ¿El rubro se deduce de `id_tienda`? sí
- ¿El rubro se deduce de `id_producto`? sí
- **¿Redundante? ⚠️ SÍ** — el one-hot de `id_producto` codifica el rubro sin pérdida (cada producto se vende en un solo rubro), así que el modelo SIN la variable de rubro igual sabe de qué rubro se trata, por la puerta de atrás.

### Resultados

| Configuración | Modelo | MAE (media ± desv. entre semillas) | RMSE | MAPE (%) | R² |
|---|---|---:|---:|---:|---:|
| (a) Modelo único SIN rubro | línea base (tienda+producto+día de la semana) | 48.233 | 73.722 | 20.25 | 0.8373 |
| (a) Modelo único SIN rubro | `random_forest` | 45.0208 ± 0.0734 | 64.245 | 21.563 | 0.8764 |
| (a) Modelo único SIN rubro | `gradient_boosting` | 42.6438 ± 0.7545 | 60.36 | 21.227 | 0.8909 |
| (b) Modelo único CON rubro | línea base (rubro+producto+día de la semana) | 82.657 | 115.94 | 35.974 | 0.5975 |
| (b) Modelo único CON rubro | `random_forest` | 45.3386 ± 0.0946 | 64.622 | 21.665 | 0.875 |
| (b) Modelo único CON rubro | `gradient_boosting` | 42.2124 ± 0.3008 | 59.836 | 21.203 | 0.8928 |
| (c) Modelos especializados por rubro | línea base (rubro+producto+día de la semana) | 82.657 | 115.94 | 35.974 | 0.5975 |
| (c) Modelos especializados por rubro | `random_forest` | 45.3472 ± 0.178 | 65.096 | 21.751 | 0.8731 |
| (c) Modelos especializados por rubro | `gradient_boosting` | 44.2942 ± 1.3262 | 60.016 | 20.997 | 0.8922 |

### Desglose por rubro (regresor `random_forest`, semilla base; columnas a/b/c = las tres configuraciones)

| Rubro | Obs. | Demanda media/día | MAE a | MAE b | MAE c |
|---|---:|---:|---:|---:|---:|
| `HORNEADOS` | 657 | 154.19 | 38.803 | 39.082 | 39.216 |
| `PANADERIA_CLASICA` | 1314 | 388.54 | 61.963 | 62.412 | 62.8 |
| `PAN_HAMBURGUESA` | 657 | 80.51 | 16.936 | 16.924 | 16.889 |

**Significancia** (bootstrap pareado, 2000 remuestreos). Signo positivo = la configuración comparada tiene MENOS error que el control (a). Se reportan los dos regresores: si la conclusión dependiera de cuál se mira, no sería una conclusión.

Un resultado cuenta como MEJORA solo si pasa las tres pruebas: distinguible de 0 al 95%, mayor que la variación entre semillas, y por encima del umbral de relevancia práctica (1.0% del MAE).

| Comparación | Regresor | Δ MAE | Δ % | IC 95% | ¿Dist. de 0? | Veredicto |
|---|---|---:|---:|---|---|---|
| (b) con rubro vs (a) control | `random_forest` | -0.2912 | -0.648% | [-0.4108, -0.1693] | sí | **irrelevante** |
| (b) con rubro vs (a) control | `gradient_boosting` | 0.5158 | 1.213% | [0.1617, 0.8666] | sí | **dentro del ruido de semilla** |
| (c) especializados vs (a) control | `random_forest` | -0.5098 | -1.135% | [-0.6951, -0.3318] | sí | **EMPEORA** |
| (c) especializados vs (a) control | `gradient_boosting` | -0.1462 | -0.344% | [-0.7927, 0.4572] | no | **sin efecto** |
| (c) especializados vs (b) con rubro | `random_forest` | -0.2186 | -0.483% | [-0.372, -0.0729] | sí | **irrelevante** |
| (c) especializados vs (b) con rubro | `gradient_boosting` | -0.662 | -1.576% | [-1.2692, -0.0902] | sí | **dentro del ruido de semilla** |

**Configuración (c):** se entrenaron 3 modelos especializados.
- Todos los rubros presentes alcanzaron el mínimo de 400 observaciones para justificar un modelo propio.

**Lectura** (regresor de referencia `random_forest`).

- (b) modelo único con rubro → **irrelevante**: distinguible de 0 pero solo 0.648% del MAE, por debajo del umbral de relevancia práctica (1.0%): es real y no sirve para nada (Δ MAE -0.2912 = -0.648%, IC 95% [-0.4108, -0.1693] en unidades de demanda).
- (c) modelos especializados por rubro → **EMPEORA**: aumenta el MAE un 1.135%, por encima del umbral de relevancia y del ruido de semilla (Δ MAE -0.5098 = -1.135%, IC 95% [-0.6951, -0.3318] en unidades de demanda).
- Vara de comparación: cambiar solo la semilla del regresor mueve el MAE del control en ±0.0734 (sobre 45.0208). Cualquier diferencia entre configuraciones menor que eso es indistinguible del azar del propio ajuste.
- La mejor línea base sin ML queda en MAE 48.233, por encima del control (45.0208): el modelo sí aporta sobre la heurística.
- Piso irreducible del escenario: MAE 37.968 (oráculo que conoce la λ del generador) frente a 44.916 del control, razón 1.183. Ese es todo el margen que cualquier configuración podría llegar a recuperar.

---

## Escenario 3 — Multi-sucursal, tienda NUEVA sin historial

Mismo catálogo, pero las sucursales [13, 23, 33] se excluyen por completo del entrenamiento y son las únicas que se evalúan. Simula abrir un local nuevo y tener que planificar producción sin historial propio.

- Entrenamiento: 7,008 obs., tiendas [11, 12, 21, 22, 31, 32]
- Validación: 876 obs. desde 2026-01-29, tiendas [13, 23, 33]
- Rubros presentes: `HORNEADOS`, `PANADERIA_CLASICA`, `PAN_HAMBURGUESA`

### ¿Es redundante la variable de rubro en este escenario?

- Tiendas por rubro: `HORNEADOS`: 2, `PANADERIA_CLASICA`: 2, `PAN_HAMBURGUESA`: 2
- ¿El rubro se deduce de `id_tienda`? sí
- ¿El rubro se deduce de `id_producto`? sí
- **¿Redundante? ⚠️ SÍ** — el one-hot de `id_producto` codifica el rubro sin pérdida (cada producto se vende en un solo rubro), así que el modelo SIN la variable de rubro igual sabe de qué rubro se trata, por la puerta de atrás.

### Resultados

| Configuración | Modelo | MAE (media ± desv. entre semillas) | RMSE | MAPE (%) | R² |
|---|---|---:|---:|---:|---:|
| (a) Modelo único SIN rubro | línea base (tienda+producto+día de la semana) | 148.628 | 200.688 | 64.473 | 0.3515 |
| (a) Modelo único SIN rubro | `random_forest` | 185.5992 ± 0.3804 | 227.704 | 88.999 | 0.1651 |
| (a) Modelo único SIN rubro | `gradient_boosting` | 191.5596 ± 1.3016 | 241.339 | 82.557 | 0.0621 |
| (b) Modelo único CON rubro | línea base (rubro+producto+día de la semana) | 148.134 | 197.057 | 61.657 | 0.3747 |
| (b) Modelo único CON rubro | `random_forest` | 185.61 ± 0.5041 | 227.597 | 88.046 | 0.1659 |
| (b) Modelo único CON rubro | `gradient_boosting` | 166.1654 ± 1.813 | 206.916 | 82.151 | 0.3106 |
| (c) Modelos especializados por rubro | línea base (rubro+producto+día de la semana) | 148.134 | 197.057 | 61.657 | 0.3747 |
| (c) Modelos especializados por rubro | `random_forest` | 134.6672 ± 1.9864 | 174.77 | 69.594 | 0.5081 |
| (c) Modelos especializados por rubro | `gradient_boosting` | 146.1312 ± 7.3156 | 196.929 | 76.173 | 0.3755 |

### Desglose por rubro (regresor `random_forest`, semilla base; columnas a/b/c = las tres configuraciones)

| Rubro | Obs. | Demanda media/día | MAE a | MAE b | MAE c |
|---|---:|---:|---:|---:|---:|
| `HORNEADOS` | 219 | 93.8 | 125.807 | 125.489 | 90.473 |
| `PANADERIA_CLASICA` | 438 | 530.82 | 288.365 | 288.231 | 211.568 |
| `PAN_HAMBURGUESA` | 219 | 49.16 | 40.277 | 38.861 | 36.857 |

**Significancia** (bootstrap pareado, 2000 remuestreos). Signo positivo = la configuración comparada tiene MENOS error que el control (a). Se reportan los dos regresores: si la conclusión dependiera de cuál se mira, no sería una conclusión.

Un resultado cuenta como MEJORA solo si pasa las tres pruebas: distinguible de 0 al 95%, mayor que la variación entre semillas, y por encima del umbral de relevancia práctica (1.0% del MAE).

| Comparación | Regresor | Δ MAE | Δ % | IC 95% | ¿Dist. de 0? | Veredicto |
|---|---|---:|---:|---|---|---|
| (b) con rubro vs (a) control | `random_forest` | 0.5003 | 0.269% | [0.3432, 0.6559] | sí | **irrelevante** |
| (b) con rubro vs (a) control | `gradient_boosting` | 25.2264 | 13.177% | [23.4281, 27.1718] | sí | **MEJORA** |
| (c) especializados vs (a) control | `random_forest` | 48.0867 | 25.894% | [45.8701, 50.3673] | sí | **MEJORA** |
| (c) especializados vs (a) control | `gradient_boosting` | 33.1051 | 17.292% | [30.3918, 35.9902] | sí | **MEJORA** |
| (c) especializados vs (b) con rubro | `random_forest` | 47.5865 | 25.694% | [45.342, 49.9073] | sí | **MEJORA** |
| (c) especializados vs (b) con rubro | `gradient_boosting` | 7.8787 | 4.74% | [6.0811, 9.5756] | sí | **MEJORA** |

**Configuración (c):** se entrenaron 3 modelos especializados.
- Todos los rubros presentes alcanzaron el mínimo de 400 observaciones para justificar un modelo propio.

**Lectura** (regresor de referencia `random_forest`).

- (b) modelo único con rubro → **irrelevante**: distinguible de 0 pero solo 0.269% del MAE, por debajo del umbral de relevancia práctica (1.0%): es real y no sirve para nada (Δ MAE 0.5003 = 0.269%, IC 95% [0.3432, 0.6559] en unidades de demanda).
- (c) modelos especializados por rubro → **MEJORA**: reduce el MAE un 25.894%, por encima del umbral de relevancia y del ruido de semilla (Δ MAE 48.0867 = 25.894%, IC 95% [45.8701, 50.3673] en unidades de demanda).
- Vara de comparación: cambiar solo la semilla del regresor mueve el MAE del control en ±0.3804 (sobre 185.5992). Cualquier diferencia entre configuraciones menor que eso es indistinguible del azar del propio ajuste.
- ⚠️ **La línea base sin ML (MAE 148.134) le gana al modelo de control (MAE 185.5992).** En este escenario la heurística de medias históricas es más robusta que el modelo entrenado, y cualquier configuración que no la supere no justifica su complejidad.
- Piso irreducible del escenario: MAE 42.333 (oráculo que conoce la λ del generador) frente a 185.703 del control, razón 4.387. Ese es todo el margen que cualquier configuración podría llegar a recuperar.

---

## Conclusión

Los números citados abajo son los del regresor de referencia (`random_forest`, el que gana el entrenamiento de producción). La tabla de significancia de cada escenario trae los dos regresores.

**1. Con el catálogo de producción actual, el rubro no puede aportar nada, y eso es una propiedad estructural, no un resultado empírico.** Hay una sola tienda por rubro, así que `tipo_rubro` es una función biyectiva de `id_tienda` y el one-hot de la tienda ya lo codifica sin pérdida. El experimento no descubre esto, lo confirma: (b) frente al control queda en Δ MAE 0.0249 (0.058%), IC 95% [-0.0209, 0.0698], veredicto **sin efecto**. Presentar eso como una mejora sería fabricar una conclusión.

**2. Con varias tiendas por rubro pero todas ya vistas, el rubro sigue sin aportar.** Y hay una segunda razón, más interesante que la primera: en este catálogo cada rubro tiene sus propios productos (una hamburguesería y una panadería no venden lo mismo), así que el one-hot de `id_producto` ya identifica el rubro sin pérdida. **El modelo «sin rubro» conoce el rubro igual, por la puerta de atrás.** Ver el diagnóstico de redundancia de cada escenario. Diferencia de (b) frente al control: Δ MAE -0.2912 (-0.648%), IC 95% [-0.4108, -0.1693], veredicto **irrelevante**.

**3. En una tienda nueva sin historial, lo que cambia el resultado no es declarar el rubro sino PARTIR el problema por rubro.** Ahí el one-hot de `id_tienda` no tiene ninguna columna que activar, y las tres configuraciones se comportan de forma muy distinta. (b) frente al control: Δ MAE 0.5003 (0.269%), IC 95% [0.3432, 0.6559], veredicto **irrelevante**. (c) frente al control: Δ MAE 48.0867 (25.894%), IC 95% [45.8701, 50.3673], veredicto **MEJORA**. Es decir: agregar la variable de rubro a un modelo que ya podía deducirlo del producto no cambia nada; entrenar un modelo POR rubro sí, porque deja de tener que repartir su capacidad entre series de escalas muy distintas (decenas de paquetes frente a cientos de unidades).

**4. Único vs. especializado.** Comparación directa (c) contra (b) en el escenario de tienda nueva: Δ MAE 47.5865 (25.694%), IC 95% [45.342, 49.9073], veredicto **MEJORA**. Los modelos especializados ganan de forma real y relevante para una tienda nueva, y ese es el caso de uso que motivó la pregunta. El precio es de ingeniería y hay que declararlo: un artefacto por rubro que entrenar, versionar y servir, más la decisión explícita de qué hacer con un rubro que no llega al mínimo de datos (acá: caer al modelo global). Con tres rubros es asumible; no escalaría a decenas.

**5. Robustez al regresor.** ⚠️ Los dos regresores NO coinciden en todos los veredictos de significancia (ver las tablas por escenario). Donde discrepan, la evidencia es débil y no debe presentarse como un resultado: un efecto que aparece con un regresor y desaparece con el otro es un efecto que estos datos no sostienen.

### Qué se decidió para el servicio

El modelo desplegado **no** incorpora la variable de rubro. Con el catálogo de producción actual sería complejidad sin beneficio medible (punto 1). La variable ya está implementada de punta a punta —columna `Tiendas.TipoRubro` en la base, `tipo_rubro` en el catálogo y en el pipeline de features— así que activarla el día que el negocio abra una segunda tienda de un rubro existente es cambiar una bandera y reentrenar, no rehacer el modelo.

### Limitaciones

- **El escenario multi-sucursal es simulado.** Las 9 sucursales no existen: se generaron inyectando a propósito una firma de demanda compartida por rubro (`catalogo.FIRMA_POR_RUBRO`). El experimento mide si la metodología RECUPERA esa estructura, no que la estructura exista en el negocio real. Si en la realidad dos tiendas del mismo rubro no se parecieran entre sí, el punto 3 no se sostendría.
- **No se simula el rubro `OTRO`** (Mercadería, Pastelería). Esas tiendas no tienen catálogo ni operación en producción (`Disponible = 0`), así que no hay supuesto de negocio con el que simular su demanda; inventarles una serie sería fabricar evidencia. Cuando arranquen y acumulen historial, entran al experimento sin cambios de código.
- **Un solo hold-out por rubro.** El escenario 3 deja fuera una sucursal por rubro. Con más sucursales por rubro correspondería un leave-one-store-out completo, promediando sobre todas las tiendas dejadas fuera, para no depender de cuál tocó excluir.
- **El rubro y el producto están confundidos.** En este catálogo cada rubro tiene productos propios, así que `id_producto` determina el rubro y el efecto de la variable de rubro no puede separarse limpiamente del que ya aporta el producto. Es realista (los negocios de rubros distintos venden cosas distintas), pero significa que el experimento NO puede atribuir al rubro un efecto propio en (b). Aislarlo requeriría un producto que se venda en dos rubros distintos, que en este negocio no existe.
- **La comparación de (c) mezcla dos efectos.** Un modelo por rubro no solo «sabe el rubro»: además deja de repartir su capacidad entre series de escalas muy distintas. Parte de su ventaja es especialización de escala, no información de rubro. Separar ambas cosas pediría un control adicional (por ejemplo, modelos especializados por particiones aleatorias del mismo tamaño).

### Cómo comprobar esto con datos reales

El experimento queda listo para repetirse sin cambios de código en cuanto el negocio tenga dos tiendas operativas del mismo rubro con historial digital suficiente: basta poblar `Tiendas.TipoRubro` (la migración `2026_09_tiendas_tipo_rubro.sql` ya lo hace), volcar la demanda diaria real al mismo formato que `demanda_diaria`, y correr `python entrenar_modelo.py --experimento-rubro`.

La conclusión defendible en la tesis **no** es «el rubro mejora la predicción». Es más específica y más útil:

> Declarar el rubro como una variable más no mejora nada mientras el
> modelo pueda deducirlo de la tienda o del producto —que es el caso
> en este negocio—. Lo que sí cambia el resultado, y sólo para una
> tienda nueva sin historial, es **usar el rubro para partir el
> problema**: entrenar un modelo por rubro. La variable de rubro vale
> como criterio de segmentación, no como feature.
