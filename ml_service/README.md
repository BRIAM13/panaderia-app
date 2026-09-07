# Microservicio de predicción de demanda — Panadería Ronceros

Servicio de Machine Learning que estima **cuántas unidades o paquetes de cada
producto se van a pedir en un día determinado**, por tienda. Su propósito
operativo es ayudar a dimensionar la hornada: cuánto pan de agua y pan francés
sacar en el turno de la mañana y en el de la tarde, cuántos paquetes de pan de
hamburguesa tener listos el fin de semana, y anticipar los picos de fechas como
Nochebuena o Fiestas Patrias.

Es la **Fase 2** del plan de tres fases del proyecto (Fase 1: CRM, ya
desplegado; Fase 3: pruebas y seguridad, en curso en paralelo).

> **Aviso metodológico, declarado por adelantado.** El modelo está entrenado y
> validado con datos **sintéticos**, no con las ventas reales del negocio. Esto
> no es un atajo ni un defecto oculto: es una decisión de diseño tomada
> explícitamente, y la sección [«Por qué datos
> sintéticos»](#por-qué-datos-sintéticos-el-hallazgo-de-los-131-pedidos) explica
> el hallazgo que la motivó y qué se puede y qué no se puede concluir de las
> métricas de este documento.

---

## Índice

1. [Arquitectura del servicio](#arquitectura-del-servicio)
2. [Por qué datos sintéticos: el hallazgo de los 131 pedidos](#por-qué-datos-sintéticos-el-hallazgo-de-los-131-pedidos)
3. [Cómo se generaron los datos sintéticos](#cómo-se-generaron-los-datos-sintéticos)
4. [Metodología de entrenamiento y validación](#metodología-de-entrenamiento-y-validación)
5. [Resultados obtenidos](#resultados-obtenidos)
6. [Experimento: ¿le sirve al modelo saber el rubro de la tienda?](#experimento-le-sirve-al-modelo-saber-el-rubro-de-la-tienda)
7. [Limitaciones declaradas](#limitaciones-declaradas)
8. [Contrato de la API](#contrato-de-la-api)
9. [Cómo correr todo localmente](#cómo-correr-todo-localmente)
10. [Estructura de archivos](#estructura-de-archivos)

---

## Arquitectura del servicio

El microservicio es un proceso Python independiente que expone una API HTTP.
Está **totalmente desacoplado** del resto de la plataforma: no comparte proceso,
ni base de datos, ni credenciales con el backend Node.

```
                    ┌───────────────────────────────────────────┐
   App Flutter ───▶ │  backend_server (Node + Express, MariaDB) │
   Página web  ───▶ │  ── datos REALES de producción ──         │
                    └────────────────────┬──────────────────────┘
                                         │  HTTP  POST /predecir
                                         │  (integración de la Fase 2b,
                                         │   fuera del alcance de este módulo)
                                         ▼
                    ┌───────────────────────────────────────────┐
                    │  ml_service (Python + FastAPI)            │
                    │                                           │
                    │   api.py ──▶ predictor.py ──▶ modelo      │
                    │                              .joblib      │
                    └───────────────────────────────────────────┘
                                         ▲
                                         │  (solo en tiempo de entrenamiento)
                    ┌────────────────────┴──────────────────────┐
                    │  data/entrenamiento.db (SQLite LOCAL)     │
                    │  ── datos SINTÉTICOS ──                   │
                    └───────────────────────────────────────────┘
```

Dos decisiones de arquitectura que conviene señalar:

**El servicio nunca toca la base de datos de producción.** Ni al entrenar ni al
predecir. Su única fuente de datos de entrenamiento es un archivo SQLite local
que él mismo genera. No hay cadena de conexión a MariaDB en ningún archivo de
este directorio, ni credenciales de ningún tipo. Esto es intencional: aísla por
completo el riesgo de que un experimento de ML afecte los datos del negocio.

**El modelo se carga una vez, al arrancar el proceso.** Cada petición a
`/predecir` solo ejecuta una inferencia sobre el modelo ya en memoria; nunca
reentrena ni vuelve a leer el disco. Reentrenar es un paso manual y explícito
(`python entrenar_modelo.py`), no un efecto secundario de recibir tráfico.

---

## Por qué datos sintéticos: el hallazgo de los 131 pedidos

Al preparar esta fase se auditó el volumen real disponible en la base de datos
de producción. El resultado:

| Tienda | Pedidos reales | Días distintos con actividad |
|---|---:|---|
| Hamburguesas | 114 | reparto disperso |
| Horneados | 5 | — |
| Panadería | 12 | **5 días consecutivos** |
| **Total** | **131** | **24 días distintos** |

Ese volumen **no permite entrenar ni, sobre todo, validar** un modelo de series
de tiempo. Las razones son concretas, no una precaución genérica:

- **No hay ni un ciclo semanal completo por tienda.** Con 24 días repartidos
  entre tres tiendas, hay combinaciones de tienda + día de la semana que
  aparecen cero veces. El día de la semana es justamente el factor más fuerte
  en la demanda de una panadería.
- **No hay ningún ciclo anual.** Ningún feriado, ninguna estación. El efecto de
  Navidad o Fiestas Patrias no puede estimarse a partir de datos que no
  contienen ninguna Navidad.
- **No queda conjunto de validación posible.** Reservar el 20% final de 24 días
  deja ~5 días para validar. Cualquier métrica calculada sobre 5 días está
  dominada por el azar: bastaría un día atípico para moverla entera. Reportar
  un MAE calculado así sería reportar ruido con apariencia de resultado.
- **Panadería solo cubre 5 días consecutivos**, lo que impide siquiera separar
  entrenamiento de validación en el tiempo para esa tienda.

Ante esto se plantearon tres caminos y se optó por el tercero:

| Opción | Por qué se descartó / eligió |
|---|---|
| Entrenar con los 131 pedidos reales | Produciría métricas sin sentido estadístico. Presentarlas como validación sería, en la práctica, un resultado inventado. |
| Esperar a acumular datos reales | El negocio recién migró al canal digital; acumular un año de historial con estacionalidad completa retrasaría la tesis sin aportar nada al diseño del sistema. |
| **Entrenar y validar con datos sintéticos, y declararlo** | **Elegida.** Permite validar que la *metodología* es correcta, dejar el sistema construido y operativo, y documentar con precisión qué falta para que sea preciso en producción. |

**Qué demuestra y qué no demuestra este trabajo.** Lo que se valida aquí es la
**metodología**: que las variables elegidas capturan los patrones de demanda de
una panadería, que la partición temporal es correcta, que el modelo
seleccionado supera a la heurística que hoy usa el negocio, y que el sistema
completo funciona de punta a punta. Lo que **no** se demuestra es la exactitud
del modelo sobre la operación real: para eso hacen falta datos reales que
todavía no existen. Ambas cosas se afirman explícitamente en el reporte de
métricas, en la respuesta de la API (campo `advertencia`) y en la sección de
[limitaciones](#limitaciones-declaradas).

En producción, el sistema se alimentaría de los datos reales del negocio. La
precisión mejorará de forma natural conforme más clientes migren al sistema
digital y el historial crezca; el endpoint ya está preparado para incorporar
ese historial real como contexto (ver [`contextoReciente`](#contexto-reciente-opcional)).

---

## Cómo se generaron los datos sintéticos

Los datos no son números al azar: son la realización de un **modelo generativo
explícito**, con todos sus supuestos declarados y parametrizados en el código
(`generar_datos_sinteticos.py` y `catalogo.py`). Cualquiera puede leer los
supuestos, discutirlos, cambiarlos y regenerar.

### El modelo generativo

Para cada día `d` y producto `p`, la demanda **esperada** es multiplicativa:

```
λ(d,p) = base_p
       × (1 + crecimiento_p) ^ (días_transcurridos / 365)   ← tendencia
       × dow[día_semana] ^ sens_p                           ← ciclo semanal
       × mes[mes]                                           ← ciclo anual
       × intensidad_feriado(d) ^ sens_p                     ← feriados
       × víspera / posterior                                ← efecto borde
       × quincena / fin de mes                              ← ciclo de pago
```

y la demanda **observada** se sortea de una **Binomial Negativa** de media `λ`.
Se eligió esa distribución y no una Normal porque la demanda es un conteo
entero no negativo con varianza mayor que la media (sobredispersión), que es lo
que se observa en el comercio minorista. El parámetro `dispersion` de cada
producto calibra cuánta.

El total diario se reparte después en **pedidos individuales** de tamaño
aleatorio, de modo que la tabla resultante tenga la misma granularidad que la
tabla `Pedidos` de producción, y no un agregado ya cocinado.

### Supuestos de estacionalidad

**Ciclo semanal** (multiplicador por día de la semana):

| lun | mar | mié | jue | vie | sáb | dom |
|---:|---:|---:|---:|---:|---:|---:|
| 0.92 | 0.90 | 0.93 | 0.98 | 1.12 | **1.30** | **1.22** |

**Ciclo anual** (multiplicador por mes): diciembre (1.15) y julio (1.08) son
los meses altos —Navidad, Fiestas Patrias, vacaciones escolares—; el otoño
limeño es el valle (abril 0.96).

**Feriados y fechas comerciales** (`feriados_peru.py`). Se combinan los
feriados oficiales del Perú (vía la librería `holidays`: Año Nuevo, Jueves y
Viernes Santo, Día del Trabajo, San Pedro y San Pablo, Fiestas Patrias, Santa
Rosa de Lima, Combate de Angamos, Todos los Santos, Inmaculada Concepción,
Navidad) con fechas **comerciales** que no son feriado pero mueven igual o más
la demanda de una panadería:

| Fecha | Multiplicador |
|---|---:|
| Nochebuena (24 dic) | 2.10 |
| Noche de Año Nuevo (31 dic) | 1.85 |
| Día de la Madre (2.º domingo de mayo) | 1.75 |
| Fiestas Patrias (28-29 jul) | 1.70 |
| Navidad (25 dic) | 1.55 |
| Día del Padre (3.er domingo de junio) | 1.45 |
| Año Nuevo (1 ene) | 1.40 |
| Día del Pollo a la Brasa (3.er domingo de julio) | 1.35 |
| Jueves / Viernes Santo | 1.30 |
| Otros feriados oficiales | 1.25 |

Además: la **víspera** de un feriado sube un 18% (la gente se abastece el día
antes, porque el feriado se atiende menos horas) y el día **posterior** baja un
12% (la despensa ya está llena).

**Ciclo de pago.** En Perú buena parte de los sueldos se paga el 15 y el último
día del mes. Se modela con un +6% alrededor de la quincena (días 14-16) y un
+5% en el cambio de mes (días ≥28 y ≤2).

**Tendencia de crecimiento.** Entre +10% y +18% anual compuesto según el
producto, que representa la migración progresiva de clientes al canal digital.

### Diferenciación por producto

Cada producto tiene su propio nivel base, volatilidad y sensibilidad
estacional, según cómo se comporta en la realidad del negocio:

| Producto | Tienda | Rubro | Unidad | Base/día | Dispersión | Sensib. estacional |
|---|---|---|---|---:|---:|---:|
| Pan de Hamburguesa Clásico | Hamburguesas | `PAN_HAMBURGUESA` | PAQUETES | 42 | 0.22 | 1.25 |
| Producto Horneados General | Horneados | `HORNEADOS` | UNIDADES | 95 | 0.30 | 1.40 |
| Pan de Agua | Panadería | `PANADERIA_CLASICA` | UNIDADES | 310 | 0.16 | 0.70 |
| Pan Francés | Panadería | `PANADERIA_CLASICA` | UNIDADES | 260 | 0.18 | 0.75 |

El razonamiento: el **pan de consumo diario** (agua y francés) es el más
estable —la gente compra pan todos los días, llueva o truene—, por eso baja
dispersión y sensibilidad estacional por debajo de 1. El **pan de
hamburguesa** se compra para parrilladas y reuniones, así que amplifica los
fines de semana y feriados. Los **horneados** (pastelería) son los más
estacionales de todos: fuertes en fechas celebratorias, planos entre semana.

La columna **Rubro** espeja `Tiendas.TipoRubro` de la base de producción. En el
catálogo de producción hay exactamente una tienda por rubro, lo que tiene una
consecuencia que conviene tener presente al leer los resultados: el rubro es
deducible del `id_tienda`, así que no puede aportarle información nueva al
modelo. Esa es justamente la pregunta que se mide en el
[experimento de rubro](#experimento-le-sirve-al-modelo-saber-el-rubro-de-la-tienda).

Los pedidos de Panadería además se reparten entre los dos **turnos de recojo**
(62% mañana, 38% tarde), reflejando que la hornada de la mañana sale ~4am y la
de la tarde ~3pm. El turno se guarda en la base pero no se usa todavía como
variable del modelo: la predicción actual es del total diario. Modelar cada
turno por separado es la extensión natural del trabajo.

### Reproducibilidad

El generador usa una **semilla fija** (`20260830`), así que el azar está
completamente determinado: correrlo dos veces **el mismo día** produce
exactamente la misma base de datos. Se puede cambiar con `--semilla`.

> ⚠️ **La semilla fija no basta para reproducir un número exacto meses
> después.** La ventana simulada termina en *ayer* (`date.today() - 1`), de
> modo que correr el generador en otra fecha desplaza los tres años completos:
> caen otros feriados en el tramo de validación, cambia el punto de corte y
> cambian las métricas. Es una decisión deliberada —el historial sintético
> tiene que llegar hasta hoy para que las predicciones que sirve la API sean
> sobre fechas futuras reales— pero hay que declararla: **lo reproducible con
> exactitud es la metodología, no la cifra**. Para congelar una ventana y
> reproducir una tabla al decimal, pasar una `fecha_fin` explícita a
> `generar_datos_sinteticos.generar()`.

Salida con los parámetros por defecto (corrida del 2026-09-06): **3 años
simulados (1.095 días), 4.380 observaciones de demanda diaria, 78.696 pedidos
individuales, ~995.585 unidades/paquetes**, guardado en `data/entrenamiento.db`.

> ⚠️ Sobre los identificadores: `catalogo.py` replica los `IdTienda`/`IdProducto`
> del seed de `database_schema.sql` (1 = Hamburguesas, 2 = Horneados,
> 3 = Panadería). Panadería aún no tiene catálogo sembrado en producción, así
> que los productos 3 (Pan de Agua) y 4 (Pan Francés) son un **supuesto** del
> entorno sintético. Cuando existan sus IdProducto reales hay que mapearlos en
> `catalogo.py` —el único archivo que hay que tocar— y reentrenar.

---

## Metodología de entrenamiento y validación

### Partición temporal, no aleatoria

Se elige una fecha de corte: **todo lo anterior es entrenamiento, todo lo
posterior es validación**. El corte se hace por *fecha* y no por *fila*, para
que ningún día quede partido entre ambos conjuntos.

Esto es deliberado y es el punto metodológico más importante del capítulo. Un
`train_test_split` aleatorio —lo habitual en problemas tabulares— sería
**incorrecto** en una serie de tiempo: filtraría información del futuro hacia el
entrenamiento (el modelo vería el martes y el jueves para «predecir» el
miércoles) y produciría métricas optimistas que no se sostienen en producción,
donde el futuro es, por definición, desconocido. La partición cronológica
reproduce la condición real de uso: predecir hacia adelante con lo aprendido
hacia atrás.

### Variables (features)

Trece variables (4 categóricas + 9 numéricas), todas derivables de la fecha
—sin necesidad de conocer nada del futuro salvo el calendario, que sí se
conoce:

| Variable | Tipo | Qué captura |
|---|---|---|
| `id_tienda`, `id_producto` | categórica | nivel base de cada producto |
| `dia_semana` | categórica | ciclo semanal |
| `mes` | categórica | ciclo anual |
| `dia_del_mes`, `semana_anio` | numérica | posición fina en el ciclo |
| `es_fin_de_semana` | binaria | efecto sábado/domingo |
| `es_feriado`, `es_vispera_feriado`, `es_posterior_feriado` | binaria | efecto de fechas especiales |
| `es_quincena`, `es_fin_de_mes` | binaria | ciclo de pago de sueldos |
| `dias_desde_inicio` | numérica | tendencia de crecimiento |

`dia_semana` y `mes` se tratan como **categóricas y no numéricas** a propósito:
la distancia entre «lunes» (0) y «domingo» (6) no es 6, y diciembre no es «11
más» que enero — son ciclos, no escalas. Se codifican con one-hot.

Nótese que el modelo recibe solo **banderas booleanas** de feriado, no el nombre
ni la intensidad de cada uno. Con 3 años simulados cada feriado concreto aparece
3 veces: muy poco para estimarle un efecto propio sin sobreajustar. El modelo
tiene que inferir el efecto agregado, igual que tendrá que hacerlo con datos
reales.

La construcción de features vive en **un solo módulo**
(`caracteristicas.py`) que usan tanto el entrenamiento como la inferencia. Si
cada lado construyera sus columnas por separado, bastaría un cambio en uno para
introducir un desalineamiento silencioso (*training/serving skew*) que degrada
las predicciones sin lanzar ningún error.

### Modelos comparados

Se entrenan tres y se reportan los tres sobre exactamente la misma validación:

1. **Línea base estacional** — la media histórica por tienda + producto + día de
   la semana. No es machine learning: es, esencialmente, lo que un panadero con
   experiencia hace mentalmente. Sirve de piso — *un modelo que no la supere no
   justifica su complejidad*.
2. **RandomForestRegressor** — *bagging* de árboles.
3. **GradientBoostingRegressor** — *boosting* de árboles.

Se selecciona automáticamente el de **menor MAE** en validación.

**Por qué árboles y no deep learning.** Con ~4.400 observaciones y 13 variables
tabulares, un ensamble de árboles es el estándar defendible: es lo que mejor
funciona en ese régimen de datos. Una red neuronal no tendría datos suficientes
para justificar su capacidad, sería más difícil de interpretar y no habría forma
honesta de defender su elección en una tesis. Los árboles, además, entregan
importancias de variables, que sirven como evidencia auditable de que el modelo
aprendió los patrones del negocio y no ruido.

### Métricas

- **MAE** — error medio en unidades o paquetes. Es la que el negocio entiende
  directamente: «me equivoco en promedio por N panes».
- **RMSE** — penaliza los errores grandes, que son los que dejan al negocio sin
  stock o con merma.
- **MAPE** — error relativo, comparable entre productos de escalas muy
  distintas (Panadería vende cientos de unidades/día; Hamburguesas, decenas de
  paquetes).
- **R²** — proporción de la varianza explicada.

---

## Resultados obtenidos

Reporte completo y siempre actualizado en
[`modelos/REPORTE_METRICAS.md`](modelos/REPORTE_METRICAS.md) y
[`modelos/metricas.json`](modelos/metricas.json), regenerados en cada
entrenamiento. Los números de abajo corresponden a la corrida con los
parámetros por defecto.

> **Sobre reproducir estos números.** El generador simula hasta *ayer*
> (`date.today() - 1`), así que la ventana de tres años se desliza con la fecha
> en que se corre. Regenerar los datos en otro día produce un historial
> distinto y, por tanto, métricas distintas — e incluso puede cambiar cuál de
> los dos modelos gana, porque Random Forest y Gradient Boosting quedan a
> pocas décimas de MAE uno del otro. Lo reproducible con exactitud es la
> *metodología*, no la cifra concreta; la tabla de abajo corresponde a la
> corrida del 2026-09-06. Para fijar la ventana y reproducir un número exacto
> hay que pasar una `fecha_fin` explícita a `generar_datos_sinteticos.generar`.

### Comparación de modelos

| Modelo | MAE | RMSE | MAPE (%) | R² |
|---|---:|---:|---:|---:|
| Línea base estacional | 48.859 | 73.068 | 20.25 | 0.7977 |
| **Random Forest** *(seleccionado)* | **42.718** | **58.670** | 20.83 | **0.8696** |
| Gradient Boosting | 46.055 | 61.228 | 24.72 | 0.8580 |

**Partición:** entrenamiento 2023-09-06 → 2026-01-29 (876 días, 3.504
observaciones); validación 2026-01-29 → 2026-09-04 (219 días, 876
observaciones).

Random Forest mejora el MAE de la línea base en un **13%** y el RMSE en un
**20%**. Que la mejora en RMSE sea mayor que en MAE es informativo: el modelo
gana sobre todo en los días *difíciles* —feriados, vísperas, picos— que son
precisamente los que la heurística del día de la semana no puede anticipar y
los que más cuestan al negocio.

### Desempeño por producto

| Tienda | Producto | Unidad | Demanda media/día | MAE | RMSE | MAPE (%) | R² |
|---|---|---|---:|---:|---:|---:|---:|
| Hamburguesas | Pan de Hamburguesa Clásico | PAQUETES | 73.33 | 15.906 | 20.287 | 24.16 | 0.3833 |
| Horneados | Producto Horneados General | UNIDADES | 147.79 | 36.006 | 48.360 | 26.64 | 0.4338 |
| Panadería | Pan de Agua | UNIDADES | 421.18 | 61.326 | 75.272 | 15.97 | 0.3110 |
| Panadería | Pan Francés | UNIDADES | 367.27 | 57.633 | 73.160 | 16.55 | 0.3196 |

El desglose importa porque el MAE global está dominado por Panadería (cientos
de unidades/día) y escondería el desempeño en Hamburguesas (decenas de
paquetes/día).

### Error del modelo frente al error irreducible

Un **R² por producto de ~0.35** podría parecer bajo si se lee sin contexto. No
lo es, y el servicio calcula el diagnóstico que lo demuestra.

La demanda observada es una realización aleatoria alrededor de su valor
esperado. Un **oráculo** que conociera exactamente la demanda esperada `λ` que
usó el generador *seguiría equivocándose*, porque el azar del día a día es
irreducible. Ese error del oráculo es el **piso teórico** del problema: ningún
modelo, por bueno que sea, puede bajar de ahí. Como los datos son sintéticos,
`λ` se conoce, y por tanto el piso se puede calcular exactamente:

| Producto | MAE modelo | MAE oráculo (piso) | Razón |
|---|---:|---:|---:|
| Pan de Hamburguesa Clásico | 15.906 | 14.416 | 1.103 |
| Producto Horneados General | 36.006 | 33.769 | 1.066 |
| Pan de Agua | 61.326 | 51.974 | 1.180 |
| Pan Francés | 57.633 | 51.434 | 1.121 |
| **Global** | **42.718** | **37.898** | **1.127** |

**El modelo comete un 12,7% más de error que el mejor predictor teóricamente
posible.** Dicho de otro modo: de todo el error observado, la mayor parte es
ruido irreducible del negocio y solo una fracción es atribuible al modelo. El
R² de ~0.35 por producto no mide un modelo mediocre; mide un negocio con alta
variabilidad diaria, que es exactamente lo que se simuló.

Este diagnóstico **solo puede calcularse en el entorno sintético** (en datos
reales `λ` es desconocida). Valida la metodología —las variables y el modelo
capturan prácticamente toda la señal disponible—, no la exactitud futura en
producción.

### Importancia de variables

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
| `dia_semana` | 0.0160 |
| `mes` | 0.0111 |
| `es_fin_de_mes` | 0.0022 |
| `es_quincena` | 0.0019 |
| `es_posterior_feriado` | 0.0009 |

La lectura correcta: `id_tienda` domina porque separa escalas muy distintas
(Panadería ~400 unidades/día vs. Hamburguesas ~73 paquetes/día) — es el
«cuánto» base. Lo relevante es qué viene después: **tendencia
(`dias_desde_inicio`), fin de semana, feriado y víspera de feriado** encabezan
las variables de calendario. Es decir, el modelo aprendió exactamente los
patrones que se le inyectaron, lo que confirma que las variables elegidas son
las correctas. Que `es_quincena` y `es_fin_de_mes` pesen poco también es
coherente: se simularon como efectos deliberadamente débiles (+6% y +5%).

El orden exacto de las variables de calendario varía algo entre corridas (ver
la nota sobre la ventana deslizante más arriba); lo que se mantiene estable, y
es lo que sostiene el argumento, son los dos bloques: `id_tienda` domina, y
después vienen tendencia y las banderas de calendario fuerte, muy por encima de
las de ciclo de pago.

---

## Experimento: ¿le sirve al modelo saber el rubro de la tienda?

**Pregunta:** ¿mejora la predicción si el modelo conoce el rubro de la tienda
(pan de hamburguesa / panadería clásica / horneados), y conviene más un modelo
único con esa variable o modelos especializados por rubro?

Reporte completo en
[`modelos/REPORTE_COMPARACION_RUBRO.md`](modelos/REPORTE_COMPARACION_RUBRO.md)
y datos crudos en `modelos/comparacion_rubro.json`. Se regeneran con
`python entrenar_modelo.py --experimento-rubro`. El código vive en
`experimento_rubro.py`.

### Qué se comparó

Tres configuraciones, sobre **exactamente la misma partición temporal**, con el
mismo regresor, los mismos hiperparámetros y las mismas semillas. Lo único que
cambia es lo que se pregunta:

| Configuración | Qué es |
|---|---|
| **(a)** `unico_sin_rubro` | El pipeline actual. Control. |
| **(b)** `unico_con_rubro` | Igual, más `tipo_rubro` como variable categórica. |
| **(c)** `especializado_por_rubro` | Un modelo entrenado solo con los datos de cada rubro. |

Y sobre **tres escenarios**, porque la respuesta no es la misma en los tres y
quedarse con uno solo llevaría a una conclusión equivocada:

1. **Producción (1 tienda por rubro)** — las 3 tiendas reales.
2. **Multi-sucursal, tiendas conocidas** — 9 sucursales sintéticas (3 por
   rubro), partición temporal estándar.
3. **Multi-sucursal, tienda NUEVA** — se deja una sucursal por rubro
   (`13`, `23`, `33`) *totalmente fuera* del entrenamiento y solo se evalúa
   sobre ellas. Simula abrir un local y tener que planificar producción sin
   historial propio.

> El escenario multi-sucursal usa un catálogo ampliado
> (`catalogo.CATALOGO_EXPERIMENTO_RUBRO`) y su propia base
> `data/entrenamiento_rubros.db`. **No** entra al modelo desplegado: esas
> tiendas no existen en producción.

### Cómo se decide si una diferencia es real

Una diferencia de MAE de unas décimas de porcentaje **no es un ganador, es
ruido**. Un resultado solo cuenta como MEJORA si pasa las tres pruebas:

1. **Bootstrap pareado** (2.000 remuestreos) cuyo IC 95% no contiene 0.
2. **Supera la dispersión entre semillas** — cada configuración se reentrena
   con 5 semillas; si la diferencia es menor que lo que mueve cambiar la
   semilla, no hay nada que concluir.
3. **Supera el 1% del MAE** (relevancia práctica). Con ~900 observaciones
   pareadas el bootstrap declara «significativa» una diferencia de 0,2%, que es
   cierta y a la vez inútil: sobre cientos de unidades de pan al día no cambia
   ninguna decisión de producción.

Además todo se calcula con **los dos regresores**: si la conclusión dependiera
de cuál se mira, no sería una conclusión.

### Resultados (MAE, media ± desv. entre 5 semillas)

| Escenario | Regresor | (a) sin rubro | (b) con rubro | (c) especializados | Línea base |
|---|---|---:|---:|---:|---:|
| 1. Producción | Random Forest | 42.504 ± 0.173 | 42.489 ± 0.194 | 42.530 ± 0.182 | 48.859 |
| 1. Producción | Gradient Boosting | 46.141 ± 0.647 | 46.089 ± 1.834 | 45.287 ± 1.839 | 48.859 |
| 2. Multi-sucursal conocidas | Random Forest | 45.021 ± 0.073 | 45.339 ± 0.095 | 45.347 ± 0.178 | 48.233 |
| 2. Multi-sucursal conocidas | Gradient Boosting | 42.644 ± 0.754 | 42.212 ± 0.301 | 44.294 ± 1.326 | 48.233 |
| **3. Tienda NUEVA** | Random Forest | 185.599 ± 0.380 | 185.610 ± 0.504 | **134.667 ± 1.986** | 148.628 |
| **3. Tienda NUEVA** | Gradient Boosting | 191.560 ± 1.302 | 166.165 ± 1.813 | **146.131 ± 7.316** | 148.628 |

Veredictos frente al control (a), regresor de referencia `random_forest`:

| Escenario | (b) con rubro | (c) especializados |
|---|---|---|
| 1. Producción | +0.06% → **sin efecto** | +0.82% → **irrelevante** |
| 2. Multi-sucursal conocidas | −0.65% → **irrelevante** | −1.14% → **empeora** |
| 3. Tienda NUEVA | +0.27% → **irrelevante** | **+25.9% → MEJORA** |

### Conclusión honesta

**1. Con el catálogo de producción, el rubro no puede aportar nada — y eso es
estructural, no empírico.** Hay una sola tienda por rubro, así que `tipo_rubro`
es una función biyectiva de `id_tienda` y el one-hot de la tienda ya lo
codifica sin pérdida. El experimento no lo descubre: lo confirma.

**2. Hay una segunda vía de redundancia, y es la más interesante.** En este
negocio cada rubro tiene sus propios productos —una hamburguesería y una
panadería no venden lo mismo—, así que **`id_producto` ya identifica el rubro**.
El modelo «sin rubro» conoce el rubro igual, por la puerta de atrás. Por eso
(b) no mejora tampoco en el escenario multi-sucursal. El servicio calcula este
diagnóstico automáticamente y lo imprime en el reporte.

**3. Lo que sí cambia el resultado no es *declarar* el rubro sino *partir* el
problema por rubro, y solo para una tienda nueva.** Ahí el one-hot de
`id_tienda` no tiene ninguna columna que activar. (c) baja el MAE un **25,9%**
frente al control con Random Forest y un **17,3%** con Gradient Boosting: los
dos regresores coinciden, el efecto es grande y sobrevive a las tres pruebas.
Parte de esa ventaja, hay que decirlo, no es «saber el rubro» sino dejar de
repartir la capacidad del modelo entre series de escalas muy distintas.

**4. Resultado incómodo que no se esconde:** en el escenario de tienda nueva,
la **línea base sin ML (MAE 148.6) le gana a los modelos (a) y (b)** (185.6).
Solo (c) la supera. Un modelo que no supera la heurística no justifica su
complejidad, y en ese escenario (a) y (b) no la superan.

**5. Los dos regresores no coinciden en todos los veredictos** de los
escenarios 1 y 2. Donde discrepan, la evidencia es débil y no se presenta como
resultado: un efecto que aparece con un regresor y desaparece con el otro es un
efecto que estos datos no sostienen.

> **La conclusión defendible no es «el rubro mejora la predicción».** Es:
> declarar el rubro como una variable más no mejora nada mientras el modelo
> pueda deducirlo de la tienda o del producto —que es el caso en este negocio—.
> Lo que sí cambia el resultado, y sólo para una tienda nueva sin historial, es
> **usar el rubro para partir el problema**. El rubro vale como criterio de
> segmentación, no como feature.

### Qué se decidió para el servicio

El modelo desplegado **no** incorpora la variable de rubro: con el catálogo
actual sería complejidad sin beneficio medible. Pero la variable ya está
implementada de punta a punta —columna `Tiendas.TipoRubro` en la base,
`tipo_rubro` en `catalogo.py` y en el pipeline de `caracteristicas.py`, y el
contrato de features se guarda en el propio artefacto (`usa_rubro`) para que
inferencia use siempre las mismas columnas del entrenamiento—. Activarla el día
que el negocio abra una segunda tienda de un rubro existente es cambiar una
bandera y reentrenar, no rehacer el modelo.

**Limitación principal del experimento:** el escenario multi-sucursal es
simulado. Que las tiendas de un mismo rubro compartan la forma de su demanda es
un supuesto que el generador **inyecta a propósito**
(`catalogo.FIRMA_POR_RUBRO`). El experimento mide si la metodología recupera esa
estructura, no que la estructura exista en la realidad. Se comprueba con datos
reales en cuanto haya dos tiendas operativas del mismo rubro con historial
suficiente, sin cambios de código.

---

## Limitaciones declaradas

Estas limitaciones se declaran aquí, en el reporte de métricas y en la propia
respuesta de la API (campo `advertencia`). Ninguna está oculta.

1. **Las métricas no son una estimación del error en producción.** Miden que la
   metodología recupera correctamente los patrones inyectados en un historial
   simulado. El error real dependerá de cuánto se parezca la demanda real a los
   supuestos declarados — algo que solo podrá medirse cuando haya historial real
   suficiente.

2. **La precisión mejorará con el tiempo, y ese es el plan.** Conforme más
   clientes migren al canal digital y el historial real crezca, el camino es:
   (a) usar `contextoReciente` para calibrar el modelo actual con datos reales
   —ya implementado—; (b) al alcanzar ~12 meses de historial con al menos un
   ciclo anual completo, reentrenar sobre datos reales usando esta misma
   metodología, que queda validada por este trabajo; (c) comparar contra la
   línea base estacional, igual que aquí, para verificar que el modelo sigue
   justificando su complejidad.

3. **Los modelos de árboles no extrapolan.** `dias_desde_inicio` permite
   capturar la tendencia dentro del rango visto en entrenamiento, pero para
   fechas futuras lejanas la predicción se aplana en el último nivel aprendido.
   El efecto medido en la validación es un sesgo conservador de entre −1% y −4%
   según el producto (el modelo predice ligeramente por debajo de lo que
   ocurre). Es un sesgo pequeño y en la dirección segura para planificar
   producción, pero está presente. Eliminarlo requeriría desestacionalizar la
   tendencia antes de modelar, o usar un modelo con componente lineal explícita.

4. **La predicción es del total diario, no por turno.** El generador ya asigna
   turno de mañana/tarde a los pedidos de Panadería, pero el modelo actual no lo
   usa como variable. Predecir cada turno por separado —que es lo que más
   ayudaría a decidir el tamaño de cada hornada— es la extensión natural.

5. **Los identificadores de Panadería son un supuesto.** Ver la nota al final de
   [«Cómo se generaron los datos sintéticos»](#reproducibilidad).

6. **No se modelan variables exógenas** (clima, promociones, competencia,
   quiebres de stock). En particular, la demanda observada en producción está
   *censurada*: si el pan se acaba, los pedidos no atendidos no quedan
   registrados, así que el historial real subestimará la demanda verdadera. Es
   un problema conocido de la literatura de *demand forecasting* que habrá que
   tratar cuando se entrene con datos reales.

---

## Contrato de la API

Documentación interactiva autogenerada en `http://127.0.0.1:8100/docs` con el
servidor levantado.

### `GET /salud`

Healthcheck. Devuelve 200 **aunque el modelo no esté entrenado todavía**; el
campo a mirar es `modeloCargado`.

```json
{
  "estado": "ok",
  "modeloCargado": true,
  "versionModelo": "1.0.0",
  "nombreModelo": "gradient_boosting",
  "entrenadoEn": "2026-08-30T05:44:41+00:00"
}
```

### `GET /info-modelo`

Métricas de validación completas, metadata del entrenamiento, importancia de
variables, catálogo de pares tienda/producto válidos y el texto de la
limitación. Es el endpoint que permite auditar en caliente qué modelo está
sirviendo. Devuelve **503** si no hay modelo entrenado.

### `POST /predecir`

**Petición** — acepta una `fecha` o una lista de `fechas` (máximo 90):

```json
{
  "idTienda": 3,
  "idProducto": 3,
  "fechas": ["2026-09-05", "2026-09-06", "2026-12-24"]
}
```

**Respuesta:**

```json
{
  "idTienda": 3,
  "idProducto": 3,
  "nombreTienda": "Panadería",
  "nombreProducto": "Pan de Agua",
  "unidad": "UNIDADES",
  "versionModelo": "1.0.0",
  "nombreModelo": "gradient_boosting",
  "ajusteContexto": {
    "aplicado": false,
    "factor": 1.0,
    "observacionesUsadas": 0,
    "motivo": "sin contexto reciente: se usa la predicción base"
  },
  "predicciones": [
    {"fecha": "2026-09-05", "diaSemana": "sábado",  "esFeriado": false, "nombreFeriado": null,         "demandaPredicha": 482, "demandaPredichaBruta": 481.78},
    {"fecha": "2026-09-06", "diaSemana": "domingo", "esFeriado": false, "nombreFeriado": null,         "demandaPredicha": 505, "demandaPredichaBruta": 505.36},
    {"fecha": "2026-12-24", "diaSemana": "jueves",  "esFeriado": true,  "nombreFeriado": "Nochebuena", "demandaPredicha": 715, "demandaPredichaBruta": 715.43}
  ],
  "advertencia": "Predicción emitida por un modelo entrenado con datos SINTÉTICOS..."
}
```

Códigos de error: **404** si el par `idTienda`/`idProducto` no está en el
catálogo del modelo; **422** si el cuerpo no cumple el contrato (sin fecha, más
de 90 fechas, etc.); **503** si no hay modelo entrenado.

Los campos van en **camelCase** —y no en snake_case como el resto del código
Python— porque el consumidor es el backend Node y toda la plataforma (app
Flutter, página web) ya habla camelCase. El contrato manda sobre la convención
del lenguaje.

### Contexto reciente (opcional)

Campo previsto para la **integración futura desde `backend_server/`**, fuera del
alcance de este módulo pero ya soportado por el contrato. El backend Node puede
enviar el historial **real** reciente de esa tienda + producto:

```json
{
  "idTienda": 3,
  "idProducto": 3,
  "fecha": "2026-09-05",
  "contextoReciente": [
    {"fecha": "2026-08-29", "cantidad": 512},
    {"fecha": "2026-08-30", "cantidad": 498},
    {"fecha": "2026-08-31", "cantidad": 455}
  ]
}
```

El servicio compara lo que el modelo *habría* predicho esos días con lo que
realmente pasó y aplica un **factor de corrección de sesgo de nivel**:

- Requiere al menos **3 observaciones**; con menos, se ignora y se devuelve la
  predicción base (indicándolo en `ajusteContexto.motivo`).
- El factor se **amortigua al 50%**: solo se aplica la mitad de la desviación
  observada. Con pocos días de historial real, buena parte de la diferencia es
  ruido y no señal; la amortiguación evita que una semana atípica desvíe todas
  las predicciones.
- Y se **recorta a [0.70, 1.30]**: por muy raro que sea el contexto, la
  predicción no se mueve más de un 30% respecto de lo que dice el modelo.
- La respuesta siempre reporta el factor aplicado, cuántas observaciones se
  usaron y el motivo, de modo que el ajuste es auditable y nunca silencioso.
- `demandaPredichaBruta` conserva siempre la predicción **antes** del ajuste.

Deliberadamente simple: con pocos datos reales, un ajuste más sofisticado
—reentrenar en caliente, o un modelo jerárquico— no tendría soporte estadístico
y sería mucho más difícil de auditar. Es un puente hacia el reentrenamiento con
datos reales, no un sustituto.

---

## Cómo correr todo localmente

Requiere **Python 3.11 o 3.12** (verificado con 3.12 en Windows). Todos los
comandos se ejecutan **dentro del directorio `ml_service/`**.

### 1. Entorno virtual e instalación

```bash
cd ml_service

# Windows (PowerShell)
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1

# Linux / macOS
python3.12 -m venv .venv
source .venv/bin/activate

pip install -r requirements.txt
```

### 2. Generar los datos sintéticos

```bash
python generar_datos_sinteticos.py
# Opcional: python generar_datos_sinteticos.py --anios 5 --semilla 123
```

Crea `data/entrenamiento.db` (SQLite local). **No se conecta a ninguna base de
datos de producción.**

### 3. Entrenar y validar el modelo

```bash
python entrenar_modelo.py
```

Entrena los tres modelos, imprime la comparación, selecciona el mejor y escribe:

- `modelos/modelo_demanda.joblib` — el modelo entrenado
- `modelos/metricas.json` — métricas completas en JSON
- `modelos/REPORTE_METRICAS.md` — el mismo reporte en formato legible

### 3b. (Opcional) Correr el experimento de rubro

```bash
python generar_datos_sinteticos.py --experimento-rubro   # una sola vez
python entrenar_modelo.py --experimento-rubro
```

El primer comando crea `data/entrenamiento_rubros.db`, el historial
multi-sucursal que el experimento necesita. El segundo corre las tres
configuraciones sobre los tres escenarios y luego el entrenamiento normal;
tarda varios minutos porque entrena decenas de modelos. Escribe
`modelos/REPORTE_COMPARACION_RUBRO.md` y `modelos/comparacion_rubro.json`.
No toca el modelo desplegado. Ver la sección
[Experimento: ¿le sirve al modelo saber el rubro de la tienda?](#experimento-le-sirve-al-modelo-saber-el-rubro-de-la-tienda).

### 4. Levantar el servidor

```bash
uvicorn api:app --host 127.0.0.1 --port 8100
# Durante el desarrollo, agregar --reload
```

Documentación interactiva en `http://127.0.0.1:8100/docs`.

### 5. Verificar que funciona

Con el servidor levantado, en otra terminal:

```bash
python prueba_humo.py
```

Comprueba los tres endpoints, la rama de `contextoReciente` y el manejo de
errores (404 y 422). O manualmente con `curl`:

```bash
curl http://127.0.0.1:8100/salud

curl -X POST http://127.0.0.1:8100/predecir \
  -H "Content-Type: application/json" \
  -d '{"idTienda":3,"idProducto":3,"fechas":["2026-09-05","2026-09-06","2026-12-24"]}'
```

> **Nota sobre despliegue.** Este módulo es solo código funcional en local. No
> incluye Docker ni configuración de nube a propósito: la infraestructura de
> producción se está preparando por separado.

---

## Estructura de archivos

```
ml_service/
├── README.md                      Este documento
├── requirements.txt               Dependencias con versión fijada
├── .gitignore
│
├── catalogo.py                    Tiendas, rubros y productos + parámetros de simulación
├── feriados_peru.py               Feriados oficiales + fechas comerciales
├── caracteristicas.py             Ingeniería de features (única fuente de verdad)
│
├── generar_datos_sinteticos.py    Genera data/entrenamiento.db
├── entrenar_modelo.py             Entrena, valida, selecciona y reporta
├── experimento_rubro.py           Experimento de rubro (3 configuraciones)
│
├── api.py                         Aplicación FastAPI (endpoints)
├── esquemas.py                    Contrato de entrada/salida (Pydantic)
├── predictor.py                   Carga del modelo e inferencia
├── prueba_humo.py                 Verificación de punta a punta
│
├── data/
│   ├── entrenamiento.db           SQLite LOCAL con datos sintéticos (no versionado)
│   └── entrenamiento_rubros.db    Historial multi-sucursal del experimento (no versionado)
└── modelos/
    ├── modelo_demanda.joblib      Modelo entrenado
    ├── metricas.json              Métricas de validación (JSON)
    ├── REPORTE_METRICAS.md        Métricas de validación (legible)
    ├── comparacion_rubro.json     Resultados del experimento de rubro (JSON)
    └── REPORTE_COMPARACION_RUBRO.md   Experimento de rubro (legible)
```

Dependencias entre módulos: `api.py → predictor.py → caracteristicas.py`, y
`entrenar_modelo.py → caracteristicas.py`. Que ambos caminos pasen por
`caracteristicas.py` es la garantía estructural de que entrenamiento e
inferencia construyen las variables de la misma forma.
