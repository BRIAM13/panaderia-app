-- =====================================================================
-- Pedidos.DescuentoPorcentaje — descuento por fidelidad del cliente
-- =====================================================================
--
-- Motivación. Desde ahora, un pedido hecho desde la página web pública
-- puede llevar un descuento automático según el SEGMENTO del CRM al que
-- pertenece quien lo hace (NUEVO / EN_RIESGO / REGULAR / FRECUENTE / VIP,
-- ver `calcularSegmento` en controllers/clientesController.js). Los cinco
-- porcentajes y la lista de tiendas donde el descuento está activo viven
-- en `Configuraciones` —los edita el dueño desde la app, sin redeploy— y
-- los siembra `backend_server/scripts/seed_descuentos_clientes.js`:
--
--   DESCUENTO_SEGMENTO_NUEVO         5
--   DESCUENTO_SEGMENTO_REGULAR       5
--   DESCUENTO_SEGMENTO_EN_RIESGO     5
--   DESCUENTO_SEGMENTO_FRECUENTE    10
--   DESCUENTO_SEGMENTO_VIP          15
--   DESCUENTOS_TIENDAS_HABILITADAS  panaderia
--
-- Lo único que falta en la base es DÓNDE dejar constancia de qué
-- descuento se aplicó, y eso es esta columna.
--
-- Qué significa cada columna después de esta migración:
--
--   `Total`                → NO cambia de significado. Sigue siendo "lo
--                            que el cliente debe pagar", es decir el monto
--                            YA DESCONTADO. Todo lo que hoy lee `pd.Total`
--                            (deudas, resúmenes de tienda, historial del
--                            CRM, avisos push) sigue leyendo exactamente
--                            lo mismo que antes y no necesita ni un
--                            cambio.
--   `DescuentoPorcentaje`  → SOLO un registro de auditoría: qué porcentaje
--                            regía en el momento en que se creó el pedido.
--                            Nunca se recalcula ni se re-interpreta
--                            después; si mañana el dueño sube VIP de 15 a
--                            20, los pedidos viejos conservan su 15.
--
-- Por eso `DECIMAL(5,2)`: admite de 0.00 a 999.99, con dos decimales por
-- si algún día el dueño quiere un 7.5%. El DEFAULT 0 es lo que hace que
-- esta migración sea segura con el sistema en producción: todo pedido ya
-- existente, y todo INSERT que no mencione la columna (el personal en la
-- app, el autoservicio, Horneados — ninguno entra en el alcance de este
-- cambio), queda en "sin descuento", que es justamente la verdad.
--
-- ---------------------------------------------------------------------
-- ✅ ESTA MIGRACIÓN ES 100% ADITIVA Y SEGURA DE CORRER EN CUALQUIER
--    MOMENTO, con el backend viejo y el APK viejo todavía en producción.
--
--    No borra ni renombra nada. Ningún controlador hace `SELECT *` sobre
--    `Pedidos` (todos listan columnas explícitas, ver SELECT_PEDIDOS_BASE
--    en controllers/pedidosController.js), así que agregar una columna no
--    altera ninguna respuesta de la API ni ningún modelo de Flutter.
--
--    No hay fase destructiva. El único orden recomendado es:
--      1º esta migración  →  2º el seed de las claves  →  3º desplegar el
--    backend nuevo. Correr los tres en ese orden no rompe nada en ningún
--    momento intermedio: sin la columna, el backend nuevo fallaría al
--    insertar un pedido web ("Unknown column 'DescuentoPorcentaje'").
-- ---------------------------------------------------------------------
--
-- MariaDB (la base real, `corporacionRonceros`). `ADD COLUMN IF NOT
-- EXISTS` es la misma forma idempotente que ya usan
-- `2026_09_tiendas_tipo_rubro.sql` y `2026_09_activacion_cuenta_web.sql`
-- en este mismo directorio. Recordar que `database_schema.sql` está
-- escrito en sintaxis T-SQL aspiracional y tiene drift conocido con la
-- base real; de ahí el paso 0.
--
-- ⚠️ ESTADO: PREPARADA, **NO EJECUTADA** contra ninguna base de datos.
--    Correrla es una decisión del dueño del negocio.
-- =====================================================================


-- ============ 0) VERIFICACIÓN PREVIA ============
-- Confirmar la forma real de la tabla y, sobre todo, que `Total` exista
-- (la columna nueva se coloca justo después) y que `DescuentoPorcentaje`
-- no exista ya.

SHOW CREATE TABLE Pedidos;


-- ============ 1) AGREGAR LA COLUMNA (aditivo) ============
-- `AFTER Total` a propósito: las dos se leen juntas siempre (cuánto se
-- cobró y con qué descuento), así que conviene que estén pegadas al mirar
-- la tabla a mano. `IF NOT EXISTS` la hace idempotente: volver a correrla
-- no falla.

ALTER TABLE Pedidos
  ADD COLUMN IF NOT EXISTS DescuentoPorcentaje DECIMAL(5,2) NOT NULL DEFAULT 0
  AFTER Total;


-- ============ 2) VERIFICACIÓN POSTERIOR ============
-- La columna debe existir, ser NOT NULL con DEFAULT 0, y TODOS los
-- pedidos existentes deben haber quedado en 0.00: ninguno de ellos nació
-- con descuento, y un valor distinto de 0 acá significaría que el DEFAULT
-- no se aplicó.

SHOW CREATE TABLE Pedidos;

SELECT
  COUNT(*)                                                   AS TotalPedidos,
  SUM(CASE WHEN DescuentoPorcentaje = 0 THEN 1 ELSE 0 END)   AS SinDescuento,   -- debe igualar a TotalPedidos
  SUM(CASE WHEN DescuentoPorcentaje <> 0 THEN 1 ELSE 0 END)  AS ConDescuento    -- debe ser 0 recién migrado
FROM Pedidos;


-- =====================================================================
-- DESPUÉS de correr esto:
--   1. Sembrar las 6 claves de Configuraciones:
--        cd backend_server && node scripts/seed_descuentos_clientes.js
--      (idempotente: una clave que ya exista no se pisa).
--   2. Recién ahí desplegar el backend nuevo.
--   3. Actualizar `database_schema.sql` con la columna nueva.
--
-- Alcance del descuento por ahora: SOLO el pedido desde la página web
-- pública (`controllers/publicoController.js`). Los flujos internos del
-- personal (`pedidosController.js`, `crearMiPedido`, Horneados) siguen
-- cobrando el precio completo y dejan esta columna en 0.
-- =====================================================================
