-- =====================================================================
-- Pago por adelantado con Yape para los pedidos web de PANADERÍA
-- =====================================================================
--
-- Motivación. Hoy un pedido de pan hecho desde la página pública
-- (`crearPedidoPublico`) se registra sin ninguna barrera de pago: el
-- cliente "paga al recoger". El dueño quiere que, para Panadería (pan de
-- agua / pan francés, vendidos por unidad), el pedido nazca YA PAGADO por
-- Yape — y que lo único que se le pida al cliente sea escribir el CÓDIGO
-- DE OPERACIÓN real que Yape le da después de pagar.
--
-- No hay lectura de notificaciones ni pasarela de pago: eso se evaluó y se
-- descartó antes por costo y riesgo. La verificación real la hace una
-- persona del negocio, mirando su propio Yape y comparando el monto. Este
-- esquema solo guarda lo necesario para que esa verificación quede
-- registrada y sea auditable.
--
-- ---------------------------------------------------------------------
-- POR QUÉ COLUMNAS NUEVAS Y NO `Pedidos.EstadoPago`
--
-- `EstadoPago` ('PAGADO' | 'DEUDA', o NULL) ya significa otra cosa muy
-- concreta: el FIADO posterior a la entrega. Se escribe solo al momento de
-- entregar (`entregarPedido`) y 'DEUDA' siempre quiere decir "debe el
-- `Total` COMPLETO". De ahí cuelga todo el reporte de deudas del sistema:
--
--     SUM(CASE WHEN EstadoPago = 'DEUDA' THEN Total ELSE 0 END)
--
-- (clientesController.js, tiendasController.js, horneadosController.js,
-- pedidosController.js, solicitudesPagoController.js). Meter acá un
-- concepto de pago PARCIAL —"pagó S/ 48 de S/ 50"— haría que esa suma
-- cobrara S/ 50 de deuda donde solo faltan S/ 2. Corrompería en silencio
-- todos esos reportes. Por eso el adelanto vive en su propia columna,
-- `EstadoPagoAdelanto`, y las dos no se tocan nunca entre sí.
--
-- ---------------------------------------------------------------------
-- QUÉ SIGNIFICA CADA COSA DESPUÉS DE ESTA MIGRACIÓN
--
--   `TokenConfirmacionPago` → cadena opaca al azar que el servidor genera
--                             al crear el pedido y le devuelve a la página.
--                             El pedido web de Panadería se crea ANTES de
--                             que el cliente pague (ver más abajo el porqué)
--                             y el código de operación llega después, en una
--                             petición aparte: este token es lo que ata esa
--                             segunda petición al pedido correcto. NO es una
--                             credencial: solo evita que un desconocido
--                             adivine un `IdPedido` correlativo y le meta un
--                             código falso al pedido de otro. El candado de
--                             verdad lo pone la máquina de estados (solo se
--                             acepta un código si `EstadoPagoAdelanto` es
--                             'VERIFICANDO' y `CodigoOperacionYape` sigue
--                             NULL: una sola vez, y nunca después de que el
--                             personal verificó).
--   `CodigoOperacionYape`   → el código REAL que emitió Yape, tal como lo
--                             copió el cliente. **UNIQUE**: es el único
--                             mecanismo que de verdad impide que dos
--                             pedidos distintos reclamen el mismo pago.
--                             Un UNIQUE de base es atómico pase lo que
--                             pase — dos envíos simultáneos con el mismo
--                             código, uno entra y el otro rebota; un
--                             "consultar y después insertar" desde el
--                             backend no puede garantizar eso. En MySQL/
--                             MariaDB un UNIQUE que admite NULL deja pasar
--                             TODOS los NULL que haga falta y solo rechaza
--                             duplicados no nulos: los pedidos que no usan
--                             esta función (hamburguesa, personal,
--                             autoservicio) conviven sin problema.
--   `MontoDeclaradoCliente` → lo que el cliente DICE que pagó. Sirve para
--                             avisarle de un error obvio antes de enviar y
--                             como pista para el personal. NUNCA se hace
--                             cuenta de plata con esto.
--   `MontoConfirmadoStaff`  → lo que el personal VIO llegar de verdad en
--                             Yape. De acá —y solo de acá— sale el estado
--                             final y el monto de cualquier ajuste.
--   `EstadoPagoAdelanto`    → 'NO_APLICA'        pedido fuera de esta
--                                                función (hamburguesa,
--                                                personal, autoservicio).
--                             'VERIFICANDO'      el pedido web de Panadería
--                                                existe y espera su pago.
--                                                Cubre los dos momentos:
--                                                antes de que el cliente
--                                                mande el código (con
--                                                `CodigoOperacionYape` NULL)
--                                                y después de mandarlo,
--                                                mientras nadie lo revisó.
--                             'PAGADO'           el personal confirmó que
--                                                llegó exactamente `Total`.
--                             'DEUDA_PARCIAL'    llegó MENOS que `Total`.
--                             'VUELTO_PENDIENTE' llegó MÁS que `Total`.
--
-- `Pedidos.Estado` suma el valor `'CONFIRMADO'`: el escalón que faltaba
-- entre "recién pedido" (SOLICITADO) y "ya lo recogió" (ENTREGADO). Los
-- TRES resultados de la verificación (justo, de menos, de más) llevan al
-- pedido a CONFIRMADO: en los tres el pago existe y el pedido es real, lo
-- que cambia es si queda un saldo o un vuelto por resolver aparte.
--
-- `AjustesPago` es ese "aparte": una fila de verdad, con su estado y su
-- fecha de resolución, en vez de un campo suelto en el pedido que nadie
-- vuelve a mirar. La crea el sistema al confirmar un monto que no
-- coincide; el cliente nunca crea una. El personal la marca RESUELTO
-- cuando de verdad se saldó — normalmente al recoger, pero a propósito es
-- una acción INDEPENDIENTE de la entrega: el dueño puede devolver el
-- vuelto antes o cobrar el saldo después.
--
-- ---------------------------------------------------------------------
-- POR QUÉ EL PEDIDO SE CREA **ANTES** DE QUE EL CLIENTE PAGUE
--
-- Lo intuitivo sería juntar todo en una sola petición: formulario +
-- código, y recién ahí crear el pedido. No sirve. Para pagar, el cliente
-- TIENE que salir del navegador y abrir Yape — y en un celular, volver al
-- navegador después de cambiar de app muy a menudo encuentra la pestaña
-- recargada desde cero. Con el pedido sin crear, ese cliente pierde
-- producto, cantidad, fecha de recojo, documento y contacto, y tiene que
-- rehacer todo, cuando lo único que le faltaba era pegar un código.
--
-- Por eso son dos pasos: el pedido se crea completo apenas termina el
-- formulario (con `EstadoPagoAdelanto = 'VERIFICANDO'`, y
-- `CodigoOperacionYape`/`MontoDeclaradoCliente` todavía en NULL), y el
-- código llega después en su propia petición, atado al pedido por
-- `TokenConfirmacionPago`. Si la pestaña se muere, el pedido sigue ahí:
-- la página lo retoma desde `localStorage`, y desde otro dispositivo se
-- llega por el seguimiento por DNI que ya existe.
--
-- Consecuencia a tener presente: un pedido de Panadería puede quedarse en
-- 'VERIFICANDO' con `CodigoOperacionYape` NULL para siempre, si el cliente
-- nunca llegó a pagar. Es exactamente el mismo caso que un 'SOLICITADO'
-- que nadie confirma, y se resuelve igual: el personal lo cancela desde la
-- app. Un pedido sin código NUNCA cuenta como pagado — no tiene cómo: el
-- estado solo pasa a PAGADO/DEUDA_PARCIAL/VUELTO_PENDIENTE cuando una
-- persona verifica el movimiento real en Yape.
--
-- ---------------------------------------------------------------------
-- ⚠️ ORDEN DE DESPLIEGUE — LEER ANTES DE CORRER NADA
--
--      1º esta migración   →   2º desplegar el backend nuevo   →   3º
--      cargar el Yape de Panadería en Métodos de pago (ver abajo).
--
--   Este orden es OBLIGATORIO, por la misma razón que en
--   `2026_09_activacion_cuenta_web.sql`: el backend nuevo nombra
--   `EstadoPagoAdelanto` y las otras tres columnas en el INSERT del pedido
--   web y en `SELECT_PEDIDOS_BASE` (la consulta que alimenta TODAS las
--   listas de pedidos de la app). Desplegado antes de correr esto, cada
--   pantalla de pedidos del personal falla con "Unknown column
--   'EstadoPagoAdelanto'".
--
--   El orden inverso (migrar primero) no rompe nada en ningún momento
--   intermedio: la migración es 100% ADITIVA salvo el CHECK de `Estado`,
--   que solo se ENSANCHA (acepta un valor más, no deja de aceptar
--   ninguno). El backend VIEJO sigue funcionando igual con las columnas
--   nuevas puestas — ningún controlador hace `SELECT *` sobre `Pedidos`
--   (todos listan columnas explícitas, ver SELECT_PEDIDOS_BASE), así que
--   agregar columnas no altera ninguna respuesta de la API ni ningún
--   modelo de Flutter, y el DEFAULT 'NO_APLICA' deja a todo pedido ya
--   existente —y a todo INSERT que no mencione la columna: el personal en
--   la app, el autoservicio, Horneados, el pedido web de hamburguesa— en
--   "esto no me aplica", que es exactamente la verdad.
--
-- MariaDB (la base real, `corporacionRonceros`). `ADD COLUMN IF NOT
-- EXISTS` y `DROP CONSTRAINT IF EXISTS` son las mismas formas idempotentes
-- que ya usan `2026_09_descuento_clientes.sql` y
-- `2026_09_activacion_cuenta_web.sql` en este mismo directorio. Recordar
-- que `database_schema.sql` está escrito en sintaxis T-SQL aspiracional y
-- tiene drift conocido con la base real (ver el paso 0 de
-- `2026_09_pedido_items.sql`): de ahí el paso 0 de acá.
--
-- Sobre `DEFAULT CURRENT_TIMESTAMP` en `AjustesPago.FechaCreacion`: es la
-- ÚNICA forma de default de fecha que MariaDB acepta en un DDL —
-- `SYSUTCDATETIME()` es T-SQL y solo existe porque la capa de
-- compatibilidad de `config/db.js` lo traduce a `UTC_TIMESTAMP(3)` dentro
-- del TEXTO de cada consulta, cosa que no pasa con un DEFAULT de columna.
-- Igual el default es solo una red de seguridad: el backend escribe
-- `FechaCreacion` explícitamente con `SYSUTCDATETIME()`, como todas las
-- demás fechas del sistema, así que la fila queda en UTC como corresponde.
--
-- ⚠️ ESTADO: PREPARADA, **NO EJECUTADA** contra ninguna base de datos.
--    La corre el dueño a mano: el clasificador de seguridad de Claude Code
--    bloquea cualquier cambio de esquema contra la base de producción, sin
--    importar cuántas veces se reintente.
-- =====================================================================


-- ============ 0) VERIFICACIÓN PREVIA ============
-- Confirmar la forma real de `Pedidos` antes de tocarla: sobre todo cómo
-- se llama HOY la constraint del estado (el paso 2 la borra por nombre) y
-- que ninguna de las cuatro columnas nuevas exista ya. Si la constraint
-- tiene otro nombre que `CK_Pedidos_Estado`, corregirlo acá abajo ANTES
-- de correr el paso 2.

SHOW CREATE TABLE Pedidos;

-- Reparto actual de estados: sirve de foto previa. Después del paso 2 los
-- mismos pedidos deben seguir contando igual y aparecer, además, la
-- columna CONFIRMADO en 0 (nadie puede estar en un estado que recién
-- ahora es válido).
SELECT Estado, COUNT(*) AS Cantidad FROM Pedidos GROUP BY Estado ORDER BY Estado;


-- ============ 1) LAS CINCO COLUMNAS NUEVAS (aditivo) ============
-- Van pegadas a `EstadoPago` a propósito: son el otro lado de la moneda
-- del pago de un pedido y siempre se leen juntas al mirar la tabla a mano.
-- El orden entre ellas sigue el orden del flujo real: primero el token que
-- nace con el pedido, después lo que manda el cliente (código + monto
-- declarado) y al final lo que confirma el personal (estado + monto
-- confirmado).
--
-- ⚠️ `TokenConfirmacionPago` a propósito SIN índice y SIN UNIQUE: siempre
--    se consulta junto al `IdPedido` de la URL (`WHERE IdPedido = ? AND
--    TokenConfirmacionPago = ?`), o sea por la clave primaria, así que un
--    índice propio no aportaría nada. Y un UNIQUE convertiría una colisión
--    astronómicamente improbable en un pedido que no se puede registrar.

ALTER TABLE Pedidos
  ADD COLUMN IF NOT EXISTS TokenConfirmacionPago VARCHAR(40) NULL AFTER EstadoPago;

ALTER TABLE Pedidos
  ADD COLUMN IF NOT EXISTS CodigoOperacionYape VARCHAR(30) NULL AFTER TokenConfirmacionPago;

ALTER TABLE Pedidos
  ADD COLUMN IF NOT EXISTS MontoDeclaradoCliente DECIMAL(10,2) NULL AFTER CodigoOperacionYape;

ALTER TABLE Pedidos
  ADD COLUMN IF NOT EXISTS EstadoPagoAdelanto VARCHAR(20) NOT NULL DEFAULT 'NO_APLICA'
  AFTER MontoDeclaradoCliente;

ALTER TABLE Pedidos
  ADD COLUMN IF NOT EXISTS MontoConfirmadoStaff DECIMAL(10,2) NULL AFTER EstadoPagoAdelanto;

-- El UNIQUE es la pieza central de todo el mecanismo anti-doble-uso (ver
-- el encabezado). Va en un ALTER aparte porque, a diferencia de las
-- columnas, `ADD CONSTRAINT` no admite `IF NOT EXISTS` en MariaDB: si
-- esta migración se vuelve a correr, ESTA línea (y solo esta) va a fallar
-- con ER_DUP_KEYNAME — es esperable y no hay nada que arreglar, el índice
-- ya está puesto.
ALTER TABLE Pedidos
  ADD CONSTRAINT UQ_Pedidos_CodigoOperacionYape UNIQUE (CodigoOperacionYape);

-- Mismo caso que el UNIQUE: re-correrla falla con "Duplicate check
-- constraint name" y no pasa nada. Los 5 valores son los que escribe el
-- backend (utils/pagoAdelanto.js) — si alguna vez se agrega uno nuevo,
-- hay que ensanchar esta constraint igual que el paso 2 ensancha la de
-- `Estado`.
ALTER TABLE Pedidos
  ADD CONSTRAINT CK_Pedidos_EstadoPagoAdelanto CHECK (EstadoPagoAdelanto IN
    ('NO_APLICA','VERIFICANDO','PAGADO','DEUDA_PARCIAL','VUELTO_PENDIENTE'));


-- ============ 2) `Pedidos.Estado` SE ENSANCHA: + 'CONFIRMADO' ============
-- MariaDB no tiene `ALTER CONSTRAINT`: hay que borrar y volver a crear.
-- El DROP va con `IF EXISTS` para que sea idempotente. Los 5 valores
-- viejos quedan TODOS: esto solo agrega uno, no quita ninguno, así que
-- ningún pedido existente puede volverse inválido.
--
-- ⚠️ Si el paso 0 mostró otro nombre para esta constraint, cambiarlo en
--    el DROP de abajo (el ADD sí crea el nombre canónico).

ALTER TABLE Pedidos
  DROP CONSTRAINT IF EXISTS CK_Pedidos_Estado;

ALTER TABLE Pedidos
  ADD CONSTRAINT CK_Pedidos_Estado CHECK (Estado IN
    ('SOLICITADO','PENDIENTE','CONFIRMADO','RECHAZADO','ENTREGADO','CANCELADO'));


-- ============ 3) AjustesPago — reclamos y devoluciones rastreables ============
-- Una fila por saldo pendiente (el cliente pagó de menos) o por vuelto
-- pendiente (pagó de más). La crea el sistema al confirmar el pago, nunca
-- el cliente. `Monto` es SIEMPRE positivo y siempre la DIFERENCIA — quién
-- le debe a quién lo dice `Tipo`, no el signo: un monto negativo sería
-- ambiguo de leer en un reporte.
--
-- `IF NOT EXISTS` para que re-correr la migración no falle.

CREATE TABLE IF NOT EXISTS AjustesPago (
  IdAjuste          INT             NOT NULL AUTO_INCREMENT,
  IdPedido          INT             NOT NULL,
  Tipo              VARCHAR(10)     NOT NULL,   -- 'DEUDA' (nos debe) | 'VUELTO' (le debemos)
  Monto             DECIMAL(10,2)   NOT NULL,   -- siempre > 0, es la diferencia contra Total
  Estado            VARCHAR(20)     NOT NULL DEFAULT 'PENDIENTE',
  Notas             VARCHAR(300)    NULL,       -- cómo se resolvió, lo escribe el personal
  IdUsuarioResolvio INT             NULL,
  FechaCreacion     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FechaResolucion   DATETIME        NULL,
  PRIMARY KEY (IdAjuste),
  CONSTRAINT FK_AjustesPago_Pedido FOREIGN KEY (IdPedido) REFERENCES Pedidos(IdPedido),
  CONSTRAINT FK_AjustesPago_UsuarioResolvio FOREIGN KEY (IdUsuarioResolvio) REFERENCES Usuarios(IdUsuario),
  CONSTRAINT CK_AjustesPago_Tipo CHECK (Tipo IN ('DEUDA','VUELTO')),
  CONSTRAINT CK_AjustesPago_Estado CHECK (Estado IN ('PENDIENTE','RESUELTO')),
  CONSTRAINT CK_AjustesPago_Monto CHECK (Monto > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Siempre se consulta "los ajustes de estos pedidos" (la lista de pedidos
-- del personal los trae por lote, igual que PedidoItems).
CREATE INDEX IX_AjustesPago_Pedido ON AjustesPago(IdPedido);


-- ============ 4) VERIFICACIÓN POSTERIOR ============
-- Las cinco columnas deben existir; `EstadoPagoAdelanto` NOT NULL con
-- DEFAULT 'NO_APLICA'; el UNIQUE y los dos CHECK puestos; y el CHECK de
-- `Estado` con los 6 valores.

SHOW CREATE TABLE Pedidos;
SHOW CREATE TABLE AjustesPago;

-- TODOS los pedidos existentes deben haber quedado en 'NO_APLICA' (ninguno
-- nació con esta función) y sin código de operación. Un valor distinto acá
-- significaría que el DEFAULT no se aplicó.
SELECT
  COUNT(*)                                                            AS TotalPedidos,
  SUM(CASE WHEN EstadoPagoAdelanto = 'NO_APLICA' THEN 1 ELSE 0 END)   AS SinAdelanto,   -- debe igualar a TotalPedidos
  SUM(CASE WHEN EstadoPagoAdelanto <> 'NO_APLICA' THEN 1 ELSE 0 END)  AS ConAdelanto,   -- debe ser 0 recién migrado
  SUM(CASE WHEN CodigoOperacionYape IS NOT NULL THEN 1 ELSE 0 END)    AS ConCodigoYape  -- debe ser 0 recién migrado
FROM Pedidos;

-- Y la tabla nueva arranca vacía.
SELECT COUNT(*) AS AjustesExistentes FROM AjustesPago;


-- =====================================================================
-- DESPUÉS de correr esto:
--
--   1. Desplegar el backend nuevo (ver el aviso de orden de arriba).
--
--   2. ⚠️ CARGAR EL YAPE DE PANADERÍA. `MediosPagoTienda` está HOY VACÍA
--      (cero filas, para cualquier tienda). Mientras siga así, el
--      formulario web no tiene ningún número ni QR que mostrarle al
--      cliente: la caja de pago no aparece y el pedido de Panadería NO se
--      puede completar. Se carga desde la app, con la cuenta SUPERADMIN:
--      Menú → Panadería → Métodos de pago → Agregar método → tipo YAPE,
--      titular, número, y (muy recomendable) la imagen del QR real
--      descargada desde la propia app de Yape. La tienda que se elija ahí
--      tiene que ser Panadería.
--
--   3. Actualizar `database_schema.sql`: las 5 columnas nuevas de
--      `Pedidos`, el CHECK de `Estado` ensanchado y el CREATE TABLE de
--      `AjustesPago`.
--
-- Alcance por ahora: SOLO el pedido de PANADERÍA (pan por unidad) hecho
-- desde la página web pública. El pan de hamburguesa es, según el dueño,
-- otro negocio y queda fuera; los flujos internos (personal, autoservicio,
-- Horneados) tampoco entran y dejan `EstadoPagoAdelanto` en 'NO_APLICA'.
-- =====================================================================
