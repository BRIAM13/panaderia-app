-- =====================================================================
-- Tiendas.TipoRubro — rubro del negocio como variable del modelo de ML
-- =====================================================================
--
-- Motivación. El microservicio de predicción de demanda (`ml_service/`)
-- necesita saber QUÉ TIPO de negocio es cada tienda, no solo cómo se
-- llama. Hoy `Tiendas` solo tiene `Nombre` y `Slug`, que son etiquetas
-- comerciales: no le dicen nada al modelo. Dos tiendas del mismo rubro
-- comparten la forma de su demanda (ciclo semanal, sensibilidad a
-- feriados y quincenas) aunque vendan a escalas muy distintas, y esa es
-- la única información que permite predecir para una sucursal NUEVA que
-- todavía no tiene historial propio.
--
-- Valores permitidos:
--   'PAN_HAMBURGUESA'    pan de hamburguesa, se vende por paquete
--   'PANADERIA_CLASICA'  pan de consumo diario (pan de agua, francés)
--   'HORNEADOS'          horneados/pastelería salada, fechas celebratorias
--   'OTRO'               rubro no definido todavía (valor por defecto)
--
-- Mercadería y Pastelería quedan en 'OTRO' a propósito: no tienen
-- catálogo ni operación (Disponible = 0). Inventarles un rubro sería
-- meterle al modelo un supuesto sin respaldo. Cuando arranquen, se
-- corrige su fila con el UPDATE del paso 2 y se reentrena el modelo.
--
-- ---------------------------------------------------------------------
-- ✅ ESTA MIGRACIÓN ES 100% ADITIVA Y SEGURA DE CORRER EN CUALQUIER
--    MOMENTO, con el backend viejo y el APK viejo todavía en producción.
--
--    No borra ni renombra nada. Solo agrega una columna con DEFAULT, de
--    modo que todo INSERT existente que no la mencione sigue funcionando
--    igual (cae en 'OTRO'). Ningún controlador de `backend_server/` hace
--    `SELECT *` sobre `Tiendas` — todos listan sus columnas de forma
--    explícita (`SELECT IdTienda, Nombre, Slug, Disponible ...`), así que
--    agregar una columna al final no altera ninguna respuesta de la API
--    ni ningún modelo de Flutter. Verificado antes de escribir esto.
--
--    No hay fase destructiva. No hay orden de despliegue que respetar.
-- ---------------------------------------------------------------------
--
-- MariaDB (la base real, `corporacionRonceros`). Recordar que
-- `database_schema.sql` está escrito en sintaxis T-SQL aspiracional y
-- tiene drift conocido con la base real; de ahí el paso 0.
--
-- ⚠️ ESTADO: PREPARADA, **NO EJECUTADA** contra ninguna base de datos.
--    Correrla es una decisión del dueño del negocio.
-- =====================================================================


-- ============ 0) VERIFICACIÓN PREVIA ============
-- Confirmar el estado actual de la tabla y qué tiendas existen de verdad
-- (los Slug son la clave estable para el backfill del paso 2, no los
-- IdTienda ni los Nombre).

SHOW CREATE TABLE Tiendas;
SELECT IdTienda, Nombre, Slug, Disponible, Estado FROM Tiendas ORDER BY IdTienda;


-- ============ 1) AGREGAR LA COLUMNA (aditivo) ============
-- Con DEFAULT 'OTRO' para que las filas existentes queden en un valor
-- válido y honesto de inmediato, sin ventana en la que la columna esté
-- NULL. `IF NOT EXISTS` la hace idempotente: volver a correrla no falla.

ALTER TABLE Tiendas
  ADD COLUMN IF NOT EXISTS TipoRubro VARCHAR(30) NOT NULL DEFAULT 'OTRO'
  AFTER Disponible;


-- ============ 2) BACKFILL POR SLUG ============
-- Se usa `Slug` y no `IdTienda` ni `Nombre`: el Slug es UNIQUE y estable,
-- mientras que los IdTienda pueden diferir de los del seed si la base se
-- recreó, y el Nombre es texto libre que el negocio puede cambiar.
-- Las tiendas que no aparezcan acá se quedan en 'OTRO'.

UPDATE Tiendas SET TipoRubro = 'PAN_HAMBURGUESA'   WHERE Slug = 'hamburguesas';
UPDATE Tiendas SET TipoRubro = 'HORNEADOS'         WHERE Slug = 'horneados';
UPDATE Tiendas SET TipoRubro = 'PANADERIA_CLASICA' WHERE Slug = 'panaderia';
UPDATE Tiendas SET TipoRubro = 'OTRO'              WHERE Slug IN ('mercaderia', 'pasteleria');


-- ============ 3) CONSTRAINT DE DOMINIO ============
-- Impide que entre un rubro escrito a mano que el modelo no sabría
-- interpretar (un typo silencioso degradaría la predicción sin lanzar
-- ningún error).
--
-- Va DESPUÉS del backfill: si se aplicara antes, cualquier fila que ya
-- tuviera un valor fuera del dominio abortaría el ALTER.
--
-- Nota MariaDB: `ADD CONSTRAINT` no admite `IF NOT EXISTS`. Si esta
-- migración se vuelve a correr sobre una base donde la constraint ya
-- existe, este statement falla con ER_CONSTRAINT_ALREADY_EXISTS — es
-- inofensivo y se puede ignorar (los pasos 1 y 2 sí son idempotentes).

ALTER TABLE Tiendas
  ADD CONSTRAINT CK_Tiendas_TipoRubro CHECK (TipoRubro IN
    ('PAN_HAMBURGUESA','PANADERIA_CLASICA','HORNEADOS','OTRO'));


-- ============ 4) VERIFICACIÓN POSTERIOR ============
-- Debe mostrar las 5 tiendas con su rubro. Ninguna de las tres tiendas
-- operativas o previstas (hamburguesas, horneados, panaderia) debería
-- quedar en 'OTRO': si alguna quedó, su Slug no coincide con lo que
-- asume el paso 2 y hay que corregirlo a mano antes de reentrenar.

SELECT IdTienda, Nombre, Slug, Disponible, TipoRubro FROM Tiendas ORDER BY IdTienda;

SELECT TipoRubro, COUNT(*) AS Tiendas FROM Tiendas GROUP BY TipoRubro;


-- =====================================================================
-- DESPUÉS de correr esto:
--   * `database_schema.sql` ya está actualizado (columna + CHECK + seed).
--   * `ml_service/catalogo.py` mantiene su propia copia del mapeo
--     tienda → rubro, porque el microservicio NUNCA se conecta a esta
--     base. Si acá se cambia el rubro de una tienda, hay que reflejarlo
--     en ese archivo y reentrenar: es el único lugar del servicio donde
--     viven los identificadores de producción, a propósito.
-- =====================================================================
