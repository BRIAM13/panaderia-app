-- =====================================================================
-- Interruptor del cobro por adelantado + excepción por cliente
-- (pedido web de PANADERÍA, pasarela CULQI)
-- =====================================================================
--
-- Motivación. Palabras del dueño (2026-09-26):
--
--   "un apartado en configuración donde pueda activar y desactivar una
--    opción, el cual me permitirá registrar pedidos sin primero cancelar
--    [pagar], o de tal caso que los pedidos no se registran hasta confirmar
--    el pago con la pasarela de culqi, igual que pueda gestionar si un
--    usuario ya sea dni o ruc solo ese usuario o usuarios específicos puedan
--    registrar sus pedidos sin primero cancelar, ya que algunos pagan sus
--    pedidos semanalmente y otros toda su deuda mensual"
--
-- O sea DOS controles, y son distintos a propósito:
--
--   1. UN INTERRUPTOR GLOBAL, que el dueño prende y apaga desde la app según
--      cómo le vaya el negocio. Encendido, el pedido web de pan no se
--      confirma hasta que Culqi cobre; apagado, se registra como siempre y
--      se paga al recoger. Vive en `Configuraciones`, no en una columna: es
--      un ajuste operativo que puede cambiar de un día para otro, igual que
--      `DESCUENTOS_TIENDAS_HABILITADAS` o `PRECIO_PAQUETE`, y el backend lo
--      relee EN CADA PEDIDO (sin caché) para que el cambio aplique en el
--      pedido siguiente sin redeploy y sin reiniciar el servidor.
--
--   2. UNA EXCEPCIÓN POR CLIENTE, que gana siempre contra el interruptor.
--      Es para los clientes de toda la vida —bodegas, puestos de mercado—
--      que le pagan la semana o el mes COMPLETOS de una vez. Exigirles una
--      tarjeta pedido por pedido les rompería la forma de trabajar que ya
--      tenían acordada, y probablemente los haría dejar de pedir. Esta va
--      SÍ como columna de `Clientes`: es un atributo del cliente, no un
--      ajuste del día, y tiene que poder consultarse junto al resto de su
--      ficha en una sola consulta.
--
-- ---------------------------------------------------------------------
-- QUÉ SIGNIFICA CADA COSA DESPUÉS DE ESTA MIGRACIÓN
--
--   `Configuraciones.EXIGE_PAGO_ADELANTADO_PANADERIA`
--        '1' → el pedido web de Panadería (pan por unidad) nace en
--              `EstadoPagoAdelanto = 'VERIFICANDO'` y solo pasa a
--              'CONFIRMADO' cuando Culqi cobra de verdad.
--        '0' → (y cualquier otro valor, y la clave ausente) se registra
--              como siempre, se paga al recoger.
--        Se siembra en '0' — ver "POR QUÉ NACE APAGADA" más abajo.
--
--   `Clientes.PideSinPagarAdelanto`
--        0 → normal: le aplica lo que diga el interruptor global.
--        1 → excepción: SIEMPRE puede pedir sin pagar primero, aunque el
--            interruptor esté encendido. Su pedido nace 'SOLICITADO' con
--            `EstadoPagoAdelanto = 'NO_APLICA'`, exactamente como antes de
--            que todo esto existiera, y su deuda se cobra como siempre al
--            entregar (`Pedidos.EstadoPago`).
--        DEFAULT 0: todo cliente que ya existe, y todo INSERT que no
--        mencione la columna, queda "sin excepción", que es la verdad.
--
-- Las tres condiciones que el backend exige juntas para cobrar por
-- adelantado están en `utils/pagoAdelanto.js` (`requierePagoAdelanto`):
-- tienda candidata (Panadería, pan por unidad) + interruptor en '1' +
-- cliente SIN la excepción.
--
-- ---------------------------------------------------------------------
-- POR QUÉ LA EXCEPCIÓN VA EN `Clientes` Y NO EN `Personas`
--
-- El dueño habló de "un usuario ya sea dni o ruc", y `Personas` es la tabla
-- que guarda el documento (DNI y RUC por igual, misma columna `DNI`, ver la
-- convención del resto del backend). Aun así la marca va en `Clientes`:
--
--   * Es una condición COMERCIAL, no de identidad. "A esta persona le fío"
--     es una relación con el negocio, y esa relación es justamente lo que
--     `Clientes` modela (ahí viven `PuntosFidelidad`, `DescripcionNegocio`,
--     `Estado`). En `Personas` conviven además trabajadores y usuarios del
--     sistema, a quienes esto no les significa nada.
--   * Es lo que ya consulta el flujo del pedido. `crearPedidoPublico`
--     resuelve el `IdCliente` antes de decidir si exige pago (ver el
--     `requierePagoAdelanto` de ese controlador), así que la marca se lee
--     donde ya se está mirando — sin un JOIN de más.
--   * Un RUC y un DNI del mismo dueño de bodega son dos Clientes distintos
--     hoy, y eso está bien acá: puede querer fiado en la cuenta del negocio
--     y no en la personal.
--
-- ---------------------------------------------------------------------
-- POR QUÉ LA CLAVE NACE APAGADA ('0')
--
-- No es indecisión: es lo único seguro. La cuenta Culqi del dueño todavía
-- está en trámite (RUC/tarjeta a nombre de su padre), así que
-- `CULQI_SECRET_KEY` está vacía y el endpoint de cobro responde 503
-- ("los pagos con tarjeta no están configurados todavía"). Con la clave
-- sembrada en '1', TODO pedido de pan de la web exigiría una tarjeta que el
-- backend no puede cobrar: nadie podría pedir pan. El backend además falla
-- apagado por su cuenta si la clave no existe (ver
-- `EXIGE_PAGO_ADELANTADO_POR_DEFECTO`), así que hay dos redes.
--
-- El dueño la prende cuando tenga su cuenta lista, desde la app:
-- Menú → Descuentos por cliente → tarjeta "Pago por adelantado con tarjeta".
--
-- ---------------------------------------------------------------------
-- ⚠️ ORDEN DE DESPLIEGUE — LEER ANTES DE CORRER NADA
--
--      1º esta migración   →   2º desplegar el backend nuevo
--
--   Este orden es OBLIGATORIO por la misma razón que en
--   `2026_09_pago_adelanto_panaderia.sql`: el backend nuevo nombra
--   `c.PideSinPagarAdelanto` en el SELECT de `listarClientes` y en el de
--   `obtenerPerfilCliente`. Desplegado antes de correr esto, la lista de
--   Clientes y la ficha de cada cliente fallan con "Unknown column
--   'PideSinPagarAdelanto'".
--
--   El orden inverso (migrar primero) no rompe nada en ningún momento
--   intermedio: la migración es 100% ADITIVA — una columna con DEFAULT y una
--   fila de configuración. No borra, no ensancha ni angosta ninguna
--   constraint, y no toca ninguna columna existente. El backend VIEJO sigue
--   funcionando igual con las dos cosas puestas: ningún controlador hace
--   `SELECT *` sobre `Clientes` (todos listan columnas explícitas), así que
--   agregar una columna no altera ninguna respuesta de la API ni ningún
--   modelo de Flutter.
--
--   Vale la pena notar que el backend nuevo tampoco se cae si esta migración
--   NO se corrió: `clientePideSinPagarAdelanto` atrapa el "Unknown column" y
--   asume "sin excepción" (ver utils/pagoAdelanto.js). Pero las pantallas de
--   Clientes sí fallarían, así que el orden de arriba igual es el bueno.
--
-- MariaDB (la base real, `corporacionRonceros`). `ADD COLUMN IF NOT EXISTS`
-- es la misma forma idempotente que ya usan las otras migraciones de este
-- directorio, y en el servidor real funciona (incluido con `AFTER otra_col`).
--
-- ⚠️ OJO CON `DROP CONSTRAINT IF EXISTS`: en el servidor real NO funciona,
--    da error de sintaxis, aunque aparezca en migraciones anteriores de esta
--    carpeta. Si algún día hay que borrar un CHECK, va `DROP CHECK nombre`
--    (sin `IF EXISTS`: no hay forma idempotente confirmada todavía). Esta
--    migración no borra ninguna constraint, así que no se topa con eso.
--
-- ⚠️ ESTADO: PREPARADA, **NO EJECUTADA** contra ninguna base de datos.
--    La corre el dueño a mano en MySQL Workbench: el clasificador de
--    seguridad de Claude Code bloquea cualquier cambio de esquema contra la
--    base de producción, sin importar cuántas veces se reintente. Las
--    sentencias están escritas UNA POR LÍNEA, sin statements multilínea
--    complicados, justamente para poder copiarlas y pegarlas de a una.
-- =====================================================================


-- ============ 0) VERIFICACIÓN PREVIA ============
-- Confirmar la forma real de `Clientes` antes de tocarla (que la columna no
-- exista ya, y cómo se llama la columna después de la cual va a quedar), y
-- ver si la clave de configuración ya está sembrada.

SHOW CREATE TABLE Clientes;

-- Debe devolver 0 filas. Si devuelve 1, el paso 2 ya se corrió antes y el
-- INSERT de abajo no va a duplicar nada (tiene su propia guarda).
SELECT Clave, Valor FROM Configuraciones WHERE Clave = 'EXIGE_PAGO_ADELANTADO_PANADERIA';

-- Foto previa: cuántos clientes hay. Después del paso 1, TODOS deben quedar
-- en PideSinPagarAdelanto = 0 (nadie nace con la excepción).
SELECT COUNT(*) AS TotalClientes FROM Clientes;


-- ============ 1) LA COLUMNA DE LA EXCEPCIÓN (aditivo) ============
-- Va pegada a `PuntosFidelidad` a propósito: las dos son condiciones
-- comerciales del cliente (lo que se le premia y lo que se le fía) y se leen
-- juntas al mirar la tabla a mano.
--
-- `BIT NOT NULL DEFAULT 0`, no NULL-able: "no sé si le fío" no es un estado
-- que tenga sentido. O tiene la excepción o no la tiene, y por defecto no.
-- (En MariaDB `BIT` es un alias de `BIT(1)`; el backend lee el valor con
-- `Boolean()` y escribe con `sql.Bit`, que la capa de compatibilidad manda
-- como 0/1 — ver config/db.js.)

ALTER TABLE Clientes ADD COLUMN IF NOT EXISTS PideSinPagarAdelanto BIT NOT NULL DEFAULT 0 AFTER PuntosFidelidad;


-- ============ 2) LA CLAVE DEL INTERRUPTOR GLOBAL ============
-- Sembrada en '0' (apagada) — ver "POR QUÉ NACE APAGADA" en el encabezado.
--
-- Va con `WHERE NOT EXISTS` y no con `INSERT IGNORE` ni `ON DUPLICATE KEY`:
-- así, si la clave ya estaba puesta (porque esta migración se vuelve a
-- correr, o porque el dueño ya la creó a mano), NO se le pisa el valor. Sería
-- muy fácil apagarle el cobro sin querer justo después de que lo encendió.
--
-- ⚠️ Si `Configuraciones` en la base real tiene más columnas NOT NULL sin
--    DEFAULT que estas tres, agregarlas acá — el paso 0 (`SHOW CREATE TABLE`
--    de Clientes) no las muestra, así que conviene mirar también
--    `SHOW CREATE TABLE Configuraciones` antes de correr esto.

INSERT INTO Configuraciones (Clave, Valor, Descripcion) SELECT 'EXIGE_PAGO_ADELANTADO_PANADERIA', '0', 'Si es 1, el pedido web de Panaderia (pan por unidad) debe pagarse con tarjeta (Culqi) antes de confirmarse. Si es 0, se paga al recoger. Los clientes con PideSinPagarAdelanto = 1 quedan exentos igual.' FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM Configuraciones WHERE Clave = 'EXIGE_PAGO_ADELANTADO_PANADERIA');


-- ============ 3) VERIFICACIÓN POSTERIOR ============
-- La columna debe existir, NOT NULL con DEFAULT 0; y la clave debe estar
-- sembrada con el valor '0'.

SHOW CREATE TABLE Clientes;

-- Debe devolver exactamente 1 fila, con Valor = '0' (o con el valor que el
-- dueño ya hubiera puesto antes, si la clave preexistía).
SELECT Clave, Valor, Descripcion FROM Configuraciones WHERE Clave = 'EXIGE_PAGO_ADELANTADO_PANADERIA';

-- TODOS los clientes existentes deben haber quedado sin la excepción. Un
-- valor distinto acá significaría que el DEFAULT no se aplicó.
SELECT COUNT(*) AS TotalClientes, SUM(CASE WHEN PideSinPagarAdelanto = 0 THEN 1 ELSE 0 END) AS SinExcepcion, SUM(CASE WHEN PideSinPagarAdelanto = 1 THEN 1 ELSE 0 END) AS ConExcepcion FROM Clientes;


-- =====================================================================
-- DESPUÉS de correr esto:
--
--   1. Desplegar el backend nuevo (ver el aviso de orden de arriba).
--
--   2. ⚠️ LLENAR `CULQI_SECRET_KEY` en el `.env` del backend (Render) y
--      `VITE_CULQI_PUBLIC_KEY` en las variables de entorno de `pagina-web`
--      (Vercel). Mientras la secreta esté vacía, el endpoint de cobro
--      responde 503 con un mensaje claro y el interruptor global NO se debe
--      encender: ningún pedido de pan se podría completar.
--
--   3. Recién entonces, encender el interruptor desde la app (cuenta
--      SUPERADMIN): Menú → Descuentos por cliente → tarjeta "Pago por
--      adelantado con tarjeta" → guardar.
--
--   4. La excepción por cliente se marca en la ficha de cada cliente
--      (SUPERADMIN): Clientes → buscar por DNI/RUC → abrir su perfil →
--      switch "Puede pedir sin pagar primero".
--
--   5. Actualizar `database_schema.sql`: la columna nueva de `Clientes`.
--
-- Alcance: SOLO el pedido de PANADERÍA (pan por unidad) hecho desde la
-- página web pública. El pan de hamburguesa es, según el dueño, otro negocio
-- y queda fuera pase lo que pase con estas dos configuraciones; los flujos
-- internos (personal, autoservicio, Horneados) tampoco entran y siguen
-- dejando `EstadoPagoAdelanto` en 'NO_APLICA'.
-- =====================================================================
