-- =====================================================================
-- Delivery del pedido web de PANADERÍA, solo dentro de Pisco
-- =====================================================================
--
-- Motivación. Palabras del dueño (2026-10-05):
--
--   "Quiero agregar el servicio de delivery solo para Pisco, por 4 soles."
--
-- Decisiones ya tomadas con él (no se reabren):
--
--   1. SOLO Panadería (pan de agua / pan francés, por unidad) — los mismos
--      productos que ya tienen pago por adelantado. El pan de hamburguesa
--      (por paquete) sigue siendo solo para recoger en tienda.
--   2. Si el pin del mapa cae FUERA del radio de Pisco, el delivery se
--      bloquea (400 con el motivo). La página le ofrece al cliente seguir
--      con recojo en tienda; el servidor NUNCA lo convierte solo.
--   3. Se pide pin en el mapa + dirección escrita + referencia: el GPS de
--      una laptop puede errar por cuadras, la dirección escrita es lo que
--      de verdad usa el repartidor.
--
-- ---------------------------------------------------------------------
-- QUÉ SIGNIFICA CADA COSA DESPUÉS DE ESTA MIGRACIÓN
--
--   `Pedidos.TipoEntrega`  VARCHAR(10) NOT NULL DEFAULT 'RECOJO'
--        'RECOJO'   → el cliente lo recoge en tienda (TODO lo que existía
--                     hasta hoy, y todo INSERT que no nombre la columna:
--                     hamburguesa, personal, autoservicio, Horneados).
--        'DELIVERY' → se lleva a `DireccionEntrega`. Solo lo escribe
--                     `crearPedidoPublico` para Panadería dentro de zona.
--        ⚠️ VARCHAR con lista cerrada y NO un `BIT EsDelivery`, a propósito:
--           el 2026-09-29 se encontró que mysql2 devuelve las columnas BIT
--           como `Buffer` (`<Buffer 00>`), y `Boolean(buffer)` es SIEMPRE
--           true. Rompió en silencio la excepción de pago por adelantado
--           durante días (ver `bitAVerdadero` en utils/pagoAdelanto.js).
--           Mismo patrón que `Pedidos.Estado` y `Pedidos.EstadoPagoAdelanto`.
--
--   `Pedidos.DireccionEntrega`  VARCHAR(300) NULL
--        Dirección escrita + referencia, tal como la escribió el cliente
--        (espacios colapsados). NULL en todo pedido de recojo.
--
--   `Pedidos.LatitudEntrega` / `Pedidos.LongitudEntrega`  DECIMAL(10,7) NULL
--        El pin que el cliente ajustó en el mapa. 7 decimales ≈ 1 cm, más
--        que suficiente. NULL en todo pedido de recojo.
--
--   `Pedidos.CostoEnvio`  DECIMAL(10,2) NOT NULL DEFAULT 0
--        Cuánto se cobró de envío EN ESTE PEDIDO. Queda grabado aunque la
--        tarifa configurada cambie después: no se reescribe la historia.
--        YA ESTÁ SUMADO DENTRO DE `Total` — `Total` sigue significando "lo
--        que el cliente paga" (no hay un segundo total). Por eso el cobro
--        por adelantado (Culqi, que lee `Pedidos.Total`) y todos los
--        reportes de deuda (`SUM(... THEN Total ...)`) cobran el envío sin
--        tocar una línea. El descuento por fidelidad aplica SOLO al pan:
--        Total = (subtotal con descuento) + CostoEnvio.
--
-- Las reglas de negocio editables (tarifa, centro y radio de la zona) NO
-- van en columnas: viven en `Configuraciones` y se siembran con
-- `backend_server/scripts/seed_delivery.js` (idempotente, no pisa una clave
-- que ya exista). El backend las relee EN CADA PEDIDO, sin caché, así un
-- cambio del dueño desde la app aplica en el pedido siguiente:
--
--   COSTO_DELIVERY_PANADERIA = '4'                     (soles)
--   DELIVERY_LATITUD_CENTRO  = '-13.706622640097475'   (la panadería)
--   DELIVERY_LONGITUD_CENTRO = '-76.20123704674447'    (la panadería)
--   DELIVERY_RADIO_KM        = '8'
--
--   Las coordenadas del centro son las de la PANADERÍA, confirmadas por el
--   dueño el 2026-10-05 (no un valor de ejemplo).
--
--   El radio de 8 km cubre Pisco urbano con holgura (San Andrés, Pisco
--   Playa, Túpac Amaru Inca). Es un punto de partida: si el dueño ve que se
--   rechazan direcciones que SÍ debería atender (o que se aceptan algunas
--   demasiado lejos), lo ajusta en `DELIVERY_RADIO_KM` sin redeploy. Ojo:
--   es distancia en LÍNEA RECTA desde la panadería, no por calles.
--
-- ---------------------------------------------------------------------
-- ⚠️ ORDEN DE DESPLIEGUE — LEER ANTES DE CORRER NADA
--
--      1º esta migración   →   2º seed_delivery.js   →   3º desplegar el backend nuevo
--
--   Este orden es OBLIGATORIO: el backend nuevo nombra las 5 columnas en
--   `SELECT_PEDIDOS_BASE` (pedidosController.js — la usan TODAS las listas
--   de pedidos del personal, Horneados, autoservicio y el seguimiento
--   público) y en el INSERT de `crearPedidoPublico`. Desplegado antes de
--   correr esto, fallarían con "Unknown column 'TipoEntrega'" todas las
--   pantallas de pedidos Y todo pedido web, incluso de recojo.
--
--   El orden inverso (migrar primero) no rompe nada en ningún momento: la
--   migración es 100% ADITIVA — columnas con DEFAULT o NULL y un CHECK
--   nuevo. No borra ni modifica ninguna constraint ni columna existente. El
--   backend VIEJO sigue funcionando igual (ningún controlador hace
--   `SELECT *` sobre `Pedidos` sin envolverlo en columnas explícitas, y
--   ningún INSERT existente nombra estas columnas, así que toman el DEFAULT).
--
--   Si el seed no se corre, el backend igual funciona con los mismos
--   valores por defecto (utils/delivery.js), pero entonces el dueño no tiene
--   las claves para editarlas desde la app. Correrlo igual.
--
-- ⚠️ SINTAXIS — el servidor real NO acepta `ADD COLUMN IF NOT EXISTS` ni
--    `DROP CONSTRAINT IF EXISTS` (error 1064, confirmado en vivo varias
--    veces). Por eso las sentencias van SIN esas cláusulas: es la primera
--    vez que se corre. Si hubiera que re-correrla, el paso 0 dice qué ya
--    existe; saltear a mano lo que ya esté (un ADD COLUMN repetido falla con
--    "Duplicate column name" y un CHECK repetido con "Duplicate check
--    constraint name" — ninguno rompe nada, solo hay que seguir con la
--    siguiente línea).
--
-- ⚠️ Las columnas van SIN `AFTER otra_col`, o sea al FINAL de la tabla: así
--    la migración no depende de cómo se llame la última columna real de
--    `Pedidos` (el esquema real tiene drift respecto a database_schema.sql).
--    El orden físico no importa: ningún código depende de él.
--
-- ⚠️ ESTADO: PREPARADA, **NO EJECUTADA** contra ninguna base de datos.
--    La corre el dueño a mano en MySQL Workbench: el clasificador de
--    seguridad de Claude Code bloquea cualquier cambio de esquema contra la
--    base de producción. Una sentencia por línea, para copiar y pegar de a
--    una.
-- =====================================================================


-- ============ 0) VERIFICACIÓN PREVIA ============
-- Confirmar la forma real de `Pedidos` antes de tocarla. NINGUNA de estas
-- 5 columnas debe aparecer: TipoEntrega, DireccionEntrega, LatitudEntrega,
-- LongitudEntrega, CostoEnvio. Si alguna ya aparece, esta migración (o
-- parte) ya se corrió: saltear en el paso 1 las que ya estén.

SHOW COLUMNS FROM Pedidos;

-- Y que no exista ya un CHECK con el mismo nombre (debe NO aparecer
-- `CK_Pedidos_TipoEntrega` ni `CK_Pedidos_CostoEnvio`).
SHOW CREATE TABLE Pedidos;

-- Foto previa: cuántos pedidos hay. Después del paso 1, TODOS deben quedar
-- en TipoEntrega = 'RECOJO' y CostoEnvio = 0.
SELECT COUNT(*) AS TotalPedidos FROM Pedidos;

-- Las claves de configuración todavía no deberían existir (0 filas). Si
-- existen, el seed las respeta y no las pisa.
SELECT Clave, Valor FROM Configuraciones WHERE Clave IN ('COSTO_DELIVERY_PANADERIA', 'DELIVERY_LATITUD_CENTRO', 'DELIVERY_LONGITUD_CENTRO', 'DELIVERY_RADIO_KM');


-- ============ 1) LAS CINCO COLUMNAS NUEVAS (aditivo) ============

ALTER TABLE Pedidos ADD COLUMN TipoEntrega VARCHAR(10) NOT NULL DEFAULT 'RECOJO';

ALTER TABLE Pedidos ADD COLUMN DireccionEntrega VARCHAR(300) NULL;

ALTER TABLE Pedidos ADD COLUMN LatitudEntrega DECIMAL(10,7) NULL;

ALTER TABLE Pedidos ADD COLUMN LongitudEntrega DECIMAL(10,7) NULL;

ALTER TABLE Pedidos ADD COLUMN CostoEnvio DECIMAL(10,2) NOT NULL DEFAULT 0;


-- ============ 2) CONSTRAINTS (aditivo) ============
-- La lista cerrada de TipoEntrega — los 2 valores que escribe el backend
-- (utils/delivery.js). Si algún día se agrega otro (ej. 'MOTO_EXTERNA'),
-- hay que borrar este CHECK con `DROP CHECK CK_Pedidos_TipoEntrega` (NO
-- `DROP CONSTRAINT IF EXISTS`, que da 1064 en el servidor real) y crearlo
-- de nuevo, más ancho.

ALTER TABLE Pedidos ADD CONSTRAINT CK_Pedidos_TipoEntrega CHECK (TipoEntrega IN ('RECOJO','DELIVERY'));

-- Un envío nunca es negativo (un costo negativo sería un descuento
-- escondido que ningún reporte vería).
ALTER TABLE Pedidos ADD CONSTRAINT CK_Pedidos_CostoEnvio CHECK (CostoEnvio >= 0);


-- ============ 3) VERIFICACIÓN POSTERIOR ============
-- Las 5 columnas deben aparecer al final, con sus DEFAULT:
--   TipoEntrega varchar(10) NO 'RECOJO'; CostoEnvio decimal(10,2) NO 0.00;
--   las otras tres NULL-ables.

SHOW COLUMNS FROM Pedidos;

-- Los dos CHECK nuevos deben aparecer.
SHOW CREATE TABLE Pedidos;

-- TODOS los pedidos existentes deben haber quedado en recojo y sin envío.
-- Cualquier número distinto de TotalPedidos en las dos columnas de la
-- derecha significaría que un DEFAULT no se aplicó.
SELECT COUNT(*) AS TotalPedidos, SUM(CASE WHEN TipoEntrega = 'RECOJO' THEN 1 ELSE 0 END) AS EnRecojo, SUM(CASE WHEN CostoEnvio = 0 THEN 1 ELSE 0 END) AS SinEnvio FROM Pedidos;


-- =====================================================================
-- DESPUÉS de correr esto:
--
--   1. Sembrar las 4 claves de Configuraciones, desde backend_server/:
--          node scripts/seed_delivery.js
--      (idempotente: si una clave ya existe, no la pisa).
--
--   2. Desplegar el backend nuevo (ver el aviso de orden de arriba).
--
--   3. Desplegar la página web con el selector "Recoger / Delivery" y el
--      mapa (lo arma el frontend en paralelo).
--
--   4. Actualizar `database_schema.sql`: las 5 columnas y los 2 CHECK.
--
--   5. (Pendiente, otro momento) Pantalla de personal en Flutter que muestre
--      tipo de entrega, dirección + referencia, el pin y el costo de envío.
--      Mientras tanto, la notificación push al personal ya dice "DELIVERY a:
--      <dirección>" y la API de pedidos ya devuelve los campos.
--
-- Alcance: SOLO el pedido de PANADERÍA (pan por unidad) hecho desde la
-- página web pública. Los flujos internos (personal, autoservicio,
-- Horneados) y el pan de hamburguesa no nombran estas columnas y siguen
-- naciendo en 'RECOJO' con CostoEnvio = 0 por el DEFAULT.
-- =====================================================================
