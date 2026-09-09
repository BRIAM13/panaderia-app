-- =====================================================================
-- Activación de cuenta por correo para el registro desde la página web
-- =====================================================================
--
-- Motivación. Hasta hoy, un DNI nuevo que pedía pan desde la página
-- pública (`crearPedidoPublico`) terminaba con una cuenta de acceso cuya
-- contraseña era EL PROPIO DNI (ver `intentarClonarUsuarioCliente`). En
-- Perú el DNI no es un secreto: aparece en boletas, en recibos y en
-- cualquier trámite. Cualquiera que conozca el DNI de una persona podía
-- entrar a su cuenta en `app.panaderiaronceros.com` — y esa persona ni
-- siquiera se enteró de que tenía una cuenta, porque nunca la pidió.
--
-- El flujo nuevo: si el visitante dejó su correo, se le crea la cuenta
-- SIN contraseña usable y SIN activar, y se le manda un correo con un
-- link para que él mismo defina su contraseña. Si no dejó correo, no se
-- le crea ninguna cuenta (la Persona y el Cliente sí, para que el pedido
-- quede asociado).
--
-- Esta migración agrega las dos piezas de base de datos que ese flujo
-- necesita:
--   1. `Usuarios.Activado` — bandera propia, SEPARADA de `Usuarios.Estado`.
--   2. `'ACTIVAR_CUENTA'` como propósito válido de `CodigosVerificacion`.
--
-- Por qué una columna NUEVA y no reusar `Usuarios.Estado`: `Estado` ya
-- significa "habilitada/deshabilitada por el personal" y el login lo
-- reporta como «La cuenta está deshabilitada» (authController.js). Un
-- cliente que solo no abrió su correo todavía no está "deshabilitado":
-- necesita un mensaje distinto («Activa tu cuenta desde el correo…») y
-- una acción distinta. Mezclar los dos estados en la misma columna haría
-- imposible distinguirlos.
--
-- ---------------------------------------------------------------------
-- ⚠️ A DIFERENCIA DE LAS MIGRACIONES ANTERIORES DE ESTE DIRECTORIO, ESTA
--    SÍ TIENE ORDEN DE DESPLIEGUE OBLIGATORIO:
--
--      1º correr esta migración   →   2º desplegar el backend nuevo.
--
--    La migración es aditiva y el backend VIEJO sigue funcionando igual
--    con la columna nueva puesta (ningún controlador hace `SELECT *`
--    sobre `Usuarios`; todos listan columnas explícitas — verificado).
--    Pero el backend NUEVO sí nombra `u.Activado` en el SELECT del login
--    y en el INSERT de la cuenta pendiente: si se despliega antes de
--    correr esto, el login falla con "Unknown column 'Activado'".
--
--    El orden inverso (migrar primero) no rompe nada en ningún momento.
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
-- Confirmar la forma real de las dos tablas antes de tocarlas: en
-- particular, cómo se llama hoy la constraint de `Proposito` (el paso 3
-- la borra por nombre) y que `Activado` no exista ya.

SHOW CREATE TABLE Usuarios;
SHOW CREATE TABLE CodigosVerificacion;

-- Cuántas cuentas hay hoy: TODAS deben quedar activadas (Activado = 1)
-- después del paso 1, porque todas nacieron por caminos que no exigen
-- activación (registro manual del personal, trabajadores, propietario).
SELECT COUNT(*) AS CuentasExistentes FROM Usuarios;


-- ============ 1) Usuarios.Activado (aditivo) ============
-- DEFAULT 1 a propósito: es lo que hace que esta migración sea segura de
-- correr con el sistema en producción. Toda cuenta que ya existe, y toda
-- cuenta creada por cualquier otro camino que no mencione la columna
-- (registro manual de clientes, alta de trabajadores, /auth/register),
-- nace activada y sigue entrando como siempre.
--
-- El ÚNICO camino que la pone en 0 es el registro desde la página web
-- pública, que la escribe de forma explícita (`publicoController.js` →
-- `crearUsuarioPendienteActivacion`).
--
-- `IF NOT EXISTS` la hace idempotente: volver a correrla no falla.

ALTER TABLE Usuarios
  ADD COLUMN IF NOT EXISTS Activado BIT NOT NULL DEFAULT 1
  AFTER Estado;


-- ============ 2) CodigosVerificacion.Proposito: + 'ACTIVAR_CUENTA' ============
-- El token de activación se guarda en la MISMA tabla que los códigos de
-- 6 dígitos (hash con bcrypt, un solo uso, expiración, tope de intentos)
-- — es exactamente el mismo mecanismo, solo cambia el largo del secreto
-- y el tiempo de vida. Lo único que hace falta es que el CHECK acepte el
-- propósito nuevo.
--
-- MariaDB no tiene `ALTER CONSTRAINT`: hay que borrar y volver a crear.
-- El DROP va con `IF EXISTS` para que sea idempotente; si la constraint
-- tiene otro nombre en la base real (ver paso 0), corregirlo acá antes
-- de correr.

ALTER TABLE CodigosVerificacion
  DROP CONSTRAINT IF EXISTS CK_CodigosVerificacion_Proposito;

ALTER TABLE CodigosVerificacion
  ADD CONSTRAINT CK_CodigosVerificacion_Proposito CHECK (Proposito IN
    ('VERIFICAR_TELEFONO','VERIFICAR_EMAIL','AUTORIZAR_CAMBIO','ACTIVAR_CUENTA'));


-- ============ 3) VERIFICACIÓN POSTERIOR ============
-- La columna debe existir, ser NOT NULL con DEFAULT 1, y NINGUNA cuenta
-- existente debe haber quedado en 0: si alguna quedó, el DEFAULT no se
-- aplicó y esas personas no podrían entrar más.

SHOW CREATE TABLE Usuarios;

SELECT
  SUM(CASE WHEN Activado = 1 THEN 1 ELSE 0 END) AS Activadas,
  SUM(CASE WHEN Activado = 0 THEN 1 ELSE 0 END) AS PendientesDeActivar,  -- debe ser 0 recién migrado
  COUNT(*)                                       AS Total
FROM Usuarios;

-- Y que el propósito nuevo de verdad entre (esta fila se borra sola en
-- el mismo bloque; es solo la prueba de que el CHECK lo acepta).
SHOW CREATE TABLE CodigosVerificacion;


-- =====================================================================
-- DESPUÉS de correr esto:
--   * `database_schema.sql` ya está actualizado (columna + CHECK).
--   * Recién ahí se puede desplegar el backend nuevo (ver el aviso de
--     orden de despliegue arriba).
--   * Las cuentas viejas creadas con contraseña = DNI siguen existiendo
--     con esa contraseña: esta migración NO las toca. Cambiar eso es una
--     decisión aparte (forzar recuperación de contraseña a ese grupo),
--     fuera del alcance de este cambio.
-- =====================================================================
