-- =====================================================================
-- Pedidos con múltiples productos (carrito) — normalización a PedidoItems
-- =====================================================================
--
-- Hoy un Pedido = un producto/cantidad/precio en la fila misma. Esta
-- migración mueve eso a una tabla nueva `PedidoItems` (una fila por línea
-- de carrito) y deja `Pedidos` como cabecera pura.
--
-- MariaDB (la base real). `database_schema.sql` está escrito en sintaxis
-- T-SQL aspiracional y tiene drift conocido con la base real — por ejemplo
-- `PedidosHorneadosDetalle` existe en la base pero falta del todo en ese
-- archivo. De ahí el paso 0 de verificación de abajo.
--
-- ⚠️ ORDEN DE DESPLIEGUE — LEER ANTES DE CORRER NADA
--
--   FASE 1 es ADITIVA: se puede correr en cualquier momento, con el
--   backend viejo todavía andando. No rompe nada.
--
--   FASE 2 es DESTRUCTIVA: borra las 4 columnas de producto de `Pedidos`.
--   SOLO se corre DESPUÉS de confirmar que el backend nuevo Y el APK nuevo
--   ya están en producción. `mapearFilaPedido` viejo devuelve
--   producto/cantidad/tipoPedido/precioUnitario como campos obligatorios y
--   el modelo Dart viejo los lee como no-nullable: si esas columnas
--   desaparecen antes del despliegue, la app truena al abrir cualquier
--   pantalla de pedidos en los dispositivos del personal.
--
-- =====================================================================


-- ============ 0) VERIFICACIÓN PREVIA ============
-- Correr esto ANTES de la Fase 2 y anotar los nombres REALES de las
-- constraints: pueden no coincidir con database_schema.sql por el drift
-- conocido.

SHOW CREATE TABLE PedidosHorneadosDetalle;
SHOW CREATE TABLE Pedidos;

-- ---------------------------------------------------------------------
-- YA EJECUTADO contra la base real (corporacionRonceros) el 2026-09-02,
-- junto con toda la Fase 1. Esto es lo que devolvió, y por eso la Fase 2
-- de más abajo NO es igual a la del plan original:
--
--   1. La FK vieja de PedidosHorneadosDetalle.IdPedido se llama
--      `FK_HorneadoDetalle_Pedido`, NO `FK_PedidosHorneadosDetalle_Pedido`.
--      La Fase 2 igual la busca dinámicamente, así que no hace falta
--      tocarla a mano.
--
--   2. ⚠️ `PedidosHorneadosDetalle.IdPedido` es la PRIMARY KEY de esa
--      tabla. Al borrarla, la tabla queda SIN clave primaria — hay que
--      promover IdPedidoItem a PK (ver la Fase 2). El plan no contemplaba
--      esto.
--
--   3. ⚠️ `Pedidos` NO tiene las constraints `CK_Pedidos_Cantidad` ni
--      `CK_Pedidos_TipoPedido` en la base real (existen solo en
--      database_schema.sql, drift conocido). Los DROP CONSTRAINT del plan
--      original fallarían con ER_CANT_DROP_FIELD_OR_KEY — se sacaron.
--      `FK_Pedidos_Producto` sí existe y sí hay que borrarla.
-- ---------------------------------------------------------------------


-- =====================================================================
-- FASE 1 — ADITIVA. Segura de correr en cualquier momento.
--
-- ✅ YA EJECUTADA contra la base real (corporacionRonceros) el 2026-09-02:
--    132 pedidos existentes copiados a PedidoItems (1 ítem cada uno),
--    5 filas de PedidosHorneadosDetalle enlazadas a su línea,
--    FilasSinMigrar = 0, y las constraints finales aplicadas.
--    Igual queda acá completa y es idempotente: volver a correrla no
--    duplica nada (CREATE TABLE IF NOT EXISTS + NOT EXISTS en el backfill).
-- =====================================================================

CREATE TABLE IF NOT EXISTS PedidoItems (
    IdPedidoItem        INT             NOT NULL AUTO_INCREMENT,
    IdPedido            INT             NOT NULL,
    IdProducto          INT             NOT NULL,
    TipoPedido          VARCHAR(20)     NOT NULL,
    Cantidad            INT             NOT NULL,
    PrecioUnitario      DECIMAL(10,2)   NOT NULL,
    Subtotal            DECIMAL(10,2)   NOT NULL,
    PRIMARY KEY (IdPedidoItem),
    CONSTRAINT FK_PedidoItems_Pedido FOREIGN KEY (IdPedido) REFERENCES Pedidos(IdPedido),
    CONSTRAINT FK_PedidoItems_Producto FOREIGN KEY (IdProducto) REFERENCES Productos(IdProducto),
    CONSTRAINT CK_PedidoItems_TipoPedido CHECK (TipoPedido IN ('UNIDADES','PAQUETES')),
    CONSTRAINT CK_PedidoItems_Cantidad CHECK (Cantidad > 0),
    CONSTRAINT CK_PedidoItems_PrecioUnitario CHECK (PrecioUnitario >= 0),
    CONSTRAINT CK_PedidoItems_Subtotal CHECK (Subtotal >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX IX_PedidoItems_Pedido ON PedidoItems(IdPedido);
CREATE INDEX IX_PedidoItems_Producto ON PedidoItems(IdProducto);

-- Backfill: cada Pedido existente tiene hoy exactamente un producto — se
-- copia como su único ítem. Subtotal = Total (antes de esta migración,
-- Total siempre era el total de un solo producto).
-- Idempotente vía NOT EXISTS: se puede volver a correr sin duplicar.
INSERT INTO PedidoItems (IdPedido, IdProducto, TipoPedido, Cantidad, PrecioUnitario, Subtotal)
SELECT p.IdPedido, p.IdProducto, p.TipoPedido, p.Cantidad, p.PrecioUnitario, p.Total
FROM Pedidos p
WHERE NOT EXISTS (SELECT 1 FROM PedidoItems pi WHERE pi.IdPedido = p.IdPedido);

-- PedidosHorneadosDetalle pasa a colgar de la LÍNEA, no del pedido — así
-- cada línea de Horneados tiene su propia Carne/Presentación/Aderezo. Acá
-- solo se agrega y puebla la columna nueva; la vieja (IdPedido) se borra
-- recién en la Fase 2.
ALTER TABLE PedidosHorneadosDetalle ADD COLUMN IdPedidoItem INT NULL AFTER IdPedido;

UPDATE PedidosHorneadosDetalle phd
INNER JOIN PedidoItems pi ON pi.IdPedido = phd.IdPedido
SET phd.IdPedidoItem = pi.IdPedidoItem
WHERE phd.IdPedidoItem IS NULL;

-- Debe devolver 0. Si no, DETENTE antes de seguir: hay detalle de
-- Horneados que no encontró su línea y las constraints de abajo fallarían.
SELECT COUNT(*) AS FilasSinMigrar FROM PedidosHorneadosDetalle WHERE IdPedidoItem IS NULL;

ALTER TABLE PedidosHorneadosDetalle
  ADD CONSTRAINT FK_PedidosHorneadosDetalle_PedidoItem FOREIGN KEY (IdPedidoItem) REFERENCES PedidoItems(IdPedidoItem),
  ADD CONSTRAINT UQ_PedidosHorneadosDetalle_PedidoItem UNIQUE (IdPedidoItem);

ALTER TABLE PedidosHorneadosDetalle MODIFY COLUMN IdPedidoItem INT NOT NULL;


-- =====================================================================
-- FASE 2 — DESTRUCTIVA.
-- ⚠️ Correr SOLO tras confirmar que el backend nuevo + el APK nuevo ya
--    están en producción (ver la advertencia del encabezado).
--
-- ✅ YA EJECUTADA contra la base real (corporacionRonceros) el 2026-09-03,
--    horas después de la Fase 1 — hacía falta con urgencia: el código
--    nuevo de los 4 controladores de creación de pedidos ya insertaba en
--    `Pedidos` sin las columnas viejas, pero como la Fase 2 todavía no
--    había corrido, esas columnas seguían siendo NOT NULL sin default en
--    la base real — todo pedido nuevo (personal, autoservicio, web
--    pública, Horneados) fallaba con "Field 'IdProducto' doesn't have a
--    default value". Confirmado tras correrla: `Pedidos.IdProducto` y
--    `PedidosHorneadosDetalle.IdPedido` ya no existen.
-- =====================================================================

-- Nombre real de la FK vieja de PedidosHorneadosDetalle.IdPedido: se busca
-- dinámicamente porque, por el drift conocido, puede no llamarse igual que
-- en database_schema.sql.
SET @fk_vieja = (
  SELECT CONSTRAINT_NAME FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'PedidosHorneadosDetalle'
    AND COLUMN_NAME = 'IdPedido' AND REFERENCED_TABLE_NAME = 'Pedidos'
  LIMIT 1
);
SET @sql_drop_fk = IF(@fk_vieja IS NOT NULL,
  CONCAT('ALTER TABLE PedidosHorneadosDetalle DROP FOREIGN KEY `', @fk_vieja, '`'),
  'SELECT 1');
PREPARE stmt FROM @sql_drop_fk; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- IdPedido es la PRIMARY KEY de esta tabla (confirmado en el paso 0), así
-- que al borrarla la tabla se queda sin PK: en el mismo ALTER se promueve
-- IdPedidoItem, que ya es UNIQUE NOT NULL desde la Fase 1. Se borra
-- primero ese UNIQUE porque la PK ya garantiza unicidad y dejar los dos
-- sería un índice duplicado.
ALTER TABLE PedidosHorneadosDetalle
  DROP PRIMARY KEY,
  DROP COLUMN IdPedido,
  DROP INDEX UQ_PedidosHorneadosDetalle_PedidoItem,
  ADD PRIMARY KEY (IdPedidoItem);

-- `Pedidos` en la base real NO tiene CK_Pedidos_Cantidad ni
-- CK_Pedidos_TipoPedido (solo existen en database_schema.sql — drift
-- conocido, ver paso 0): intentar borrarlas falla. Si en algún momento se
-- recrea la base desde el .sql, agregar acá sus DROP CONSTRAINT.
ALTER TABLE Pedidos DROP FOREIGN KEY FK_Pedidos_Producto;
ALTER TABLE Pedidos
  DROP COLUMN IdProducto,
  DROP COLUMN Cantidad,
  DROP COLUMN PrecioUnitario,
  DROP COLUMN TipoPedido;

-- Después de la Fase 2: actualizar database_schema.sql — quitar esas 4
-- columnas de Pedidos, agregar CREATE TABLE PedidoItems, y agregar
-- PedidosHorneadosDetalle completa (hoy falta del todo, drift conocido).
