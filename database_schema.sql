/* ============================================================================
   PANADERIA APP - ESQUEMA DE BASE DE DATOS (SQL Server 2017+)
   ============================================================================
   Diseño clave: una Persona (identificada por DNI) es la entidad única e
   inmutable. Cliente y Trabajador son "perfiles" (1:1 opcionales) que
   cuelgan de Persona, y PersonaRoles guarda el historial de roles en el
   tiempo. Así, cuando un cliente pasa a ser trabajador:
     - No se borra ni se duplica su registro personal (Personas).
     - Su historial de compras (Ventas.IdCliente) se mantiene intacto,
       porque el IdCliente nunca cambia ni se elimina.
     - Simplemente se agrega una fila nueva en Trabajadores y en
       PersonaRoles, preservando cuándo empezó cada rol.
   ============================================================================ */

IF DB_ID('PanaderiaApp') IS NULL
BEGIN
    CREATE DATABASE PanaderiaApp;
END
GO

USE PanaderiaApp;
GO

/* ============================================================================
   1. ROLES - Catálogo de roles del sistema
   ============================================================================ */
CREATE TABLE Roles (
    IdRol           INT IDENTITY(1,1)   NOT NULL,
    NombreRol       VARCHAR(50)         NOT NULL,
    Descripcion     VARCHAR(200)        NULL,
    Estado          BIT                 NOT NULL DEFAULT 1,
    CONSTRAINT PK_Roles PRIMARY KEY (IdRol),
    CONSTRAINT UQ_Roles_Nombre UNIQUE (NombreRol)
);
GO

/* ============================================================================
   2. PERSONAS - Identidad única de toda persona en el sistema (DNI)
   ============================================================================ */
CREATE TABLE Personas (
    IdPersona           INT IDENTITY(1,1)   NOT NULL,
    DNI                 VARCHAR(15)         NULL,       -- opcional: clientes "sin DNI registrado"
    Nombres             NVARCHAR(100)       NOT NULL,   -- NVARCHAR: nombres en español llevan tildes/ñ
    ApellidoPaterno     NVARCHAR(100)       NOT NULL,
    ApellidoMaterno     NVARCHAR(100)       NULL,
    FechaNacimiento     DATE                NULL,
    Telefono            VARCHAR(20)         NULL,
    Email               VARCHAR(150)        NULL,
    -- Un teléfono/email queda "sin verificar" hasta que su dueño confirme un
    -- código enviado por SMS/correo (autoservicio de Mi Perfil, rol CLIENTE).
    -- Cambiarlo después de verificado exige primero autorizar el cambio con
    -- un código enviado al canal YA verificado (ver CodigosVerificacion).
    TelefonoVerificado  BIT                 NOT NULL DEFAULT 0,
    EmailVerificado     BIT                 NOT NULL DEFAULT 0,
    Direccion           NVARCHAR(250)       NULL,
    FechaRegistro       DATETIME2           NOT NULL DEFAULT SYSUTCDATETIME(),
    Estado              BIT                 NOT NULL DEFAULT 1,
    OrigenValidacion    VARCHAR(20)         NOT NULL DEFAULT 'MANUAL',  -- 'RENIEC' | 'MANUAL'
    CONSTRAINT PK_Personas PRIMARY KEY (IdPersona),
    CONSTRAINT CK_Personas_DNI_Formato CHECK (DNI IS NULL OR LEN(DNI) BETWEEN 8 AND 15),
    CONSTRAINT CK_Personas_OrigenValidacion CHECK (OrigenValidacion IN ('RENIEC','MANUAL'))
);
GO

-- Único filtrado: garantiza DNI único solo entre las personas que sí lo tienen.
CREATE UNIQUE INDEX UQ_Personas_DNI_Filtrado ON Personas(DNI) WHERE DNI IS NOT NULL;
GO

CREATE INDEX IX_Personas_Email ON Personas(Email) WHERE Email IS NOT NULL;
GO

-- Códigos de un solo uso (PIN de 6 dígitos) para verificar un teléfono/email
-- nuevo, o para autorizar un cambio sensible (cambiar teléfono/email/
-- contraseña) usando un canal ya verificado. Nunca se guarda el código en
-- texto plano — se guarda su hash, igual que Usuarios.PasswordHash.
CREATE TABLE CodigosVerificacion (
    IdCodigo            INT IDENTITY(1,1)   NOT NULL,
    IdPersona           INT                 NOT NULL,
    Canal               VARCHAR(10)         NOT NULL,   -- 'SMS' | 'EMAIL'
    Proposito           VARCHAR(30)         NOT NULL,   -- 'VERIFICAR_TELEFONO' | 'VERIFICAR_EMAIL' | 'AUTORIZAR_CAMBIO'
    Destino             VARCHAR(150)        NOT NULL,   -- número/correo al que se envió
    CodigoHash          VARCHAR(255)        NOT NULL,
    Intentos            INT                 NOT NULL DEFAULT 0,
    Usado               BIT                 NOT NULL DEFAULT 0,
    FechaCreacion       DATETIME2           NOT NULL DEFAULT SYSUTCDATETIME(),
    FechaExpiracion     DATETIME2           NOT NULL,
    CONSTRAINT PK_CodigosVerificacion PRIMARY KEY (IdCodigo),
    CONSTRAINT FK_CodigosVerificacion_Personas FOREIGN KEY (IdPersona) REFERENCES Personas(IdPersona),
    CONSTRAINT CK_CodigosVerificacion_Canal CHECK (Canal IN ('SMS','EMAIL')),
    CONSTRAINT CK_CodigosVerificacion_Proposito CHECK (Proposito IN ('VERIFICAR_TELEFONO','VERIFICAR_EMAIL','AUTORIZAR_CAMBIO'))
);
GO

CREATE INDEX IX_CodigosVerificacion_Persona_Proposito ON CodigosVerificacion(IdPersona, Proposito, Usado);
GO

/* ============================================================================
   3. PERSONA_ROLES - Historial de roles asumidos por cada persona
      (permite múltiples roles simultáneos o a lo largo del tiempo)
   ============================================================================ */
CREATE TABLE PersonaRoles (
    IdPersonaRol        INT IDENTITY(1,1)   NOT NULL,
    IdPersona           INT                 NOT NULL,
    IdRol               INT                 NOT NULL,
    FechaAsignacion     DATETIME2           NOT NULL DEFAULT SYSUTCDATETIME(),
    FechaFin            DATETIME2           NULL,       -- NULL = rol vigente
    Estado              BIT                 NOT NULL DEFAULT 1,
    CONSTRAINT PK_PersonaRoles PRIMARY KEY (IdPersonaRol),
    CONSTRAINT FK_PersonaRoles_Persona FOREIGN KEY (IdPersona)
        REFERENCES Personas(IdPersona),
    CONSTRAINT FK_PersonaRoles_Rol FOREIGN KEY (IdRol)
        REFERENCES Roles(IdRol)
);
GO

CREATE INDEX IX_PersonaRoles_Persona ON PersonaRoles(IdPersona);
GO

/* ============================================================================
   4. CLIENTES - Perfil de cliente (1:1 opcional con Personas)
      NUNCA se elimina al convertirse en trabajador: solo se agrega el
      perfil de Trabajador en paralelo.
   ============================================================================ */
CREATE TABLE Clientes (
    IdCliente               INT IDENTITY(1,1)   NOT NULL,
    IdPersona                INT                 NOT NULL,
    FechaRegistroCliente     DATETIME2           NOT NULL DEFAULT SYSUTCDATETIME(),
    LimiteCredito            DECIMAL(10,2)       NOT NULL DEFAULT 0,
    PuntosFidelidad          INT                 NOT NULL DEFAULT 0,
    DescripcionNegocio       NVARCHAR(300)       NULL,   -- si el cliente es un negocio (restaurante, bodega, etc.)
    NombreComercialOficial   BIT                 NOT NULL DEFAULT 0,  -- 1 si DescripcionNegocio vino de SUNAT (no editable a mano)
    Estado                   BIT                 NOT NULL DEFAULT 1,
    CONSTRAINT PK_Clientes PRIMARY KEY (IdCliente),
    CONSTRAINT UQ_Clientes_Persona UNIQUE (IdPersona),
    CONSTRAINT FK_Clientes_Persona FOREIGN KEY (IdPersona)
        REFERENCES Personas(IdPersona)
);
GO

/* ============================================================================
   5. TRABAJADORES - Perfil de trabajador (1:1 opcional con Personas)
   ============================================================================ */
CREATE TABLE Trabajadores (
    IdTrabajador            INT IDENTITY(1,1)   NOT NULL,
    IdPersona                INT                 NOT NULL,
    Cargo                    NVARCHAR(100)       NOT NULL,
    FechaContratacion        DATE                NOT NULL DEFAULT CAST(GETDATE() AS DATE),
    FechaCese                DATE                NULL,
    Salario                  DECIMAL(10,2)       NULL,
    Estado                   BIT                 NOT NULL DEFAULT 1,  -- 1=activo, 0=cesado
    CONSTRAINT PK_Trabajadores PRIMARY KEY (IdTrabajador),
    CONSTRAINT UQ_Trabajadores_Persona UNIQUE (IdPersona),
    CONSTRAINT FK_Trabajadores_Persona FOREIGN KEY (IdPersona)
        REFERENCES Personas(IdPersona)
);
GO

/* ============================================================================
   5b. TIENDAS - Unidades de negocio del Hub (Hamburguesas, Horneados, etc.)
   ============================================================================ */
CREATE TABLE Tiendas (
    IdTienda        INT IDENTITY(1,1)   NOT NULL,
    Nombre          NVARCHAR(100)       NOT NULL,
    Slug            VARCHAR(50)         NOT NULL,
    Disponible      BIT                 NOT NULL DEFAULT 0,  -- si ya está operativa (vs "Próximamente")
    Estado          BIT                 NOT NULL DEFAULT 1,
    CONSTRAINT PK_Tiendas PRIMARY KEY (IdTienda),
    CONSTRAINT UQ_Tiendas_Slug UNIQUE (Slug)
);
GO

/* ============================================================================
   5c. TRABAJADOR_TIENDAS - A qué tienda(s) tiene acceso cada trabajador.
       Un ADMIN administra (y un TRABAJADOR trabaja en) exactamente las
       tiendas donde tiene una fila con Estado=1 aquí. SUPERADMIN no
       necesita filas: tiene acceso implícito a todo. Otorgar/quitar acceso
       es solo alternar Estado — nunca se borra la fila, para conservar
       cuándo empezó y terminó cada asignación.
   ============================================================================ */
CREATE TABLE TrabajadorTiendas (
    IdTrabajadorTienda  INT IDENTITY(1,1)   NOT NULL,
    IdTrabajador        INT                 NOT NULL,
    IdTienda            INT                 NOT NULL,
    FechaAsignacion     DATETIME2           NOT NULL DEFAULT SYSUTCDATETIME(),
    FechaRevocacion     DATETIME2           NULL,
    Estado              BIT                 NOT NULL DEFAULT 1,
    CONSTRAINT PK_TrabajadorTiendas PRIMARY KEY (IdTrabajadorTienda),
    CONSTRAINT FK_TrabajadorTiendas_Trabajador FOREIGN KEY (IdTrabajador) REFERENCES Trabajadores(IdTrabajador),
    CONSTRAINT FK_TrabajadorTiendas_Tienda FOREIGN KEY (IdTienda) REFERENCES Tiendas(IdTienda),
    CONSTRAINT UQ_TrabajadorTiendas UNIQUE (IdTrabajador, IdTienda)
);
GO

/* ============================================================================
   6. USUARIOS - Credenciales de acceso al sistema (login)
      Vinculado a Persona, no a Cliente/Trabajador directamente, porque
      el acceso al sistema es un atributo de la persona, no del perfil.
   ============================================================================ */
CREATE TABLE Usuarios (
    IdUsuario                   INT IDENTITY(1,1)   NOT NULL,
    IdPersona                    INT                 NOT NULL,
    NombreUsuario                VARCHAR(50)         NOT NULL,
    PasswordHash                 VARCHAR(255)        NOT NULL,   -- hash bcrypt, nunca texto plano
    IdRol                        INT                 NOT NULL,   -- rol principal para autorización
    Estado                       BIT                 NOT NULL DEFAULT 1,
    IntentosFallidos             INT                 NOT NULL DEFAULT 0,
    Bloqueado                    BIT                 NOT NULL DEFAULT 0,
    FechaBloqueo                 DATETIME2           NULL,
    UltimoAcceso                 DATETIME2           NULL,
    RequiereCambioPassword       BIT                 NOT NULL DEFAULT 0,
    -- Dueño original del sistema (el primer SUPERADMIN, quien instaló la
    -- app) — SOLO puede haber uno. Ningún otro SUPERADMIN, aunque tenga el
    -- mismo rol nominal, puede cambiarle el rol ni darlo de baja (ver
    -- candado en trabajadoresController.js) — así, si algún día se asciende
    -- a alguien más a SUPERADMIN, ese nuevo usuario nunca puede quitarle
    -- acceso ni adueñarse del sistema por encima del dueño original.
    EsPropietario                BIT                 NOT NULL DEFAULT 0,
    -- Quién registró esta cuenta como personal (NULL = nunca se registró
    -- por este mecanismo, ej. el propietario original). Un ADMIN solo
    -- puede modificar a OTRO ADMIN si él mismo lo creó (ver candado en
    -- trabajadoresController.js) — evita que administradores se quiten
    -- poder entre sí, salvo el que ascendió a alguien de su confianza.
    IdCreadoPor                  INT                 NULL,
    FechaCreacion                DATETIME2           NOT NULL DEFAULT SYSUTCDATETIME(),
    FechaActualizacion           DATETIME2           NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Usuarios PRIMARY KEY (IdUsuario),
    CONSTRAINT UQ_Usuarios_NombreUsuario UNIQUE (NombreUsuario),
    CONSTRAINT UQ_Usuarios_Persona UNIQUE (IdPersona),   -- una cuenta de acceso por persona
    CONSTRAINT FK_Usuarios_Persona FOREIGN KEY (IdPersona)
        REFERENCES Personas(IdPersona),
    CONSTRAINT FK_Usuarios_Rol FOREIGN KEY (IdRol)
        REFERENCES Roles(IdRol),
    CONSTRAINT FK_Usuarios_CreadoPor FOREIGN KEY (IdCreadoPor)
        REFERENCES Usuarios(IdUsuario)
);
GO

/* ============================================================================
   6b. DISPOSITIVOS_NOTIFICACION - Tokens de Firebase Cloud Messaging por
       dispositivo, para enviar notificaciones push reales. Un usuario puede
       tener varios dispositivos (celular + otro), cada uno con su propio
       token; el mismo token nunca se repite (un dispositivo = una fila).
   ============================================================================ */
CREATE TABLE DispositivosNotificacion (
    IdDispositivo       INT IDENTITY(1,1)   NOT NULL,
    IdUsuario           INT                 NOT NULL,
    FcmToken            VARCHAR(300)        NOT NULL,
    Plataforma          VARCHAR(20)         NOT NULL DEFAULT 'ANDROID',
    FechaRegistro       DATETIME2           NOT NULL DEFAULT SYSUTCDATETIME(),
    FechaActualizacion  DATETIME2           NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_DispositivosNotificacion PRIMARY KEY (IdDispositivo),
    CONSTRAINT UQ_DispositivosNotificacion_Token UNIQUE (FcmToken),
    CONSTRAINT FK_DispositivosNotificacion_Usuario FOREIGN KEY (IdUsuario)
        REFERENCES Usuarios(IdUsuario)
);
GO

/* ============================================================================
   7. TOKENS_SESION - Refresh tokens (permite revocar sesiones)
   ============================================================================ */
CREATE TABLE TokensSesion (
    IdToken             INT IDENTITY(1,1)   NOT NULL,
    IdUsuario           INT                 NOT NULL,
    RefreshToken        VARCHAR(500)        NOT NULL,
    FechaCreacion       DATETIME2           NOT NULL DEFAULT SYSUTCDATETIME(),
    FechaExpiracion     DATETIME2           NOT NULL,
    Revocado            BIT                 NOT NULL DEFAULT 0,
    IPOrigen            VARCHAR(50)         NULL,
    CONSTRAINT PK_TokensSesion PRIMARY KEY (IdToken),
    CONSTRAINT FK_TokensSesion_Usuario FOREIGN KEY (IdUsuario)
        REFERENCES Usuarios(IdUsuario)
);
GO

CREATE INDEX IX_TokensSesion_Usuario ON TokensSesion(IdUsuario);
GO

/* ============================================================================
   8. AUDITORIA_LOG - Trazabilidad de acciones sensibles del sistema
   ============================================================================ */
CREATE TABLE Auditoria_Log (
    IdAuditoria             BIGINT IDENTITY(1,1)   NOT NULL,
    IdUsuario               INT                     NULL,       -- NULL = acción anónima/sistema
    Accion                  VARCHAR(50)             NOT NULL,   -- LOGIN, LOGIN_FALLIDO, REGISTRO, UPDATE, DELETE...
    TablaAfectada           VARCHAR(100)            NULL,
    RegistroAfectadoId      VARCHAR(50)             NULL,
    DatosAnteriores         NVARCHAR(MAX)           NULL,       -- JSON
    DatosNuevos             NVARCHAR(MAX)           NULL,       -- JSON
    DireccionIP             VARCHAR(50)             NULL,
    UserAgent               VARCHAR(300)            NULL,
    FechaHora               DATETIME2               NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Auditoria_Log PRIMARY KEY (IdAuditoria),
    CONSTRAINT FK_Auditoria_Usuario FOREIGN KEY (IdUsuario)
        REFERENCES Usuarios(IdUsuario)
);
GO

CREATE INDEX IX_Auditoria_FechaHora ON Auditoria_Log(FechaHora);
CREATE INDEX IX_Auditoria_Usuario ON Auditoria_Log(IdUsuario);
GO

/* ============================================================================
   9. CATEGORIAS Y PRODUCTOS - Catálogo del negocio (pan, horneados, etc.)
   ============================================================================ */
CREATE TABLE Categorias (
    IdCategoria     INT IDENTITY(1,1)   NOT NULL,
    IdTienda        INT                 NULL,   -- a qué tienda pertenece este catálogo
    Nombre          NVARCHAR(100)       NOT NULL,
    Estado          BIT                 NOT NULL DEFAULT 1,
    CONSTRAINT PK_Categorias PRIMARY KEY (IdCategoria),
    CONSTRAINT UQ_Categorias_Nombre UNIQUE (Nombre),
    CONSTRAINT FK_Categorias_Tienda FOREIGN KEY (IdTienda) REFERENCES Tiendas(IdTienda)
);
GO

CREATE TABLE Productos (
    IdProducto          INT IDENTITY(1,1)   NOT NULL,
    IdCategoria         INT                 NOT NULL,
    Nombre              NVARCHAR(150)       NOT NULL,
    Descripcion         NVARCHAR(300)       NULL,
    PrecioUnitario      DECIMAL(10,2)       NOT NULL,
    Stock               INT                 NOT NULL DEFAULT 0,
    UnidadMedida        VARCHAR(20)         NOT NULL DEFAULT 'UNIDAD',
    Estado              BIT                 NOT NULL DEFAULT 1,
    FechaCreacion       DATETIME2           NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Productos PRIMARY KEY (IdProducto),
    CONSTRAINT FK_Productos_Categoria FOREIGN KEY (IdCategoria)
        REFERENCES Categorias(IdCategoria),
    CONSTRAINT CK_Productos_Precio CHECK (PrecioUnitario >= 0),
    CONSTRAINT CK_Productos_Stock CHECK (Stock >= 0)
);
GO

/* ============================================================================
   10. VENTAS Y DETALLE_VENTAS - Historial transaccional
       IdCliente se conserva siempre, incluso si esa persona hoy además
       es trabajador: el historial de compras nunca se pierde.
   ============================================================================ */
CREATE TABLE Ventas (
    IdVenta             INT IDENTITY(1,1)   NOT NULL,
    IdCliente           INT                 NULL,       -- NULL = venta sin cliente registrado
    IdTrabajador        INT                 NOT NULL,   -- quién atendió la venta
    FechaVenta          DATETIME2           NOT NULL DEFAULT SYSUTCDATETIME(),
    Subtotal            DECIMAL(10,2)       NOT NULL,
    Descuento           DECIMAL(10,2)       NOT NULL DEFAULT 0,
    Total               DECIMAL(10,2)       NOT NULL,
    MetodoPago          VARCHAR(30)         NOT NULL DEFAULT 'EFECTIVO',
    Estado              VARCHAR(20)         NOT NULL DEFAULT 'COMPLETADA',
    CONSTRAINT PK_Ventas PRIMARY KEY (IdVenta),
    CONSTRAINT FK_Ventas_Cliente FOREIGN KEY (IdCliente)
        REFERENCES Clientes(IdCliente),
    CONSTRAINT FK_Ventas_Trabajador FOREIGN KEY (IdTrabajador)
        REFERENCES Trabajadores(IdTrabajador)
);
GO

CREATE INDEX IX_Ventas_Fecha ON Ventas(FechaVenta);
CREATE INDEX IX_Ventas_Cliente ON Ventas(IdCliente);
GO

CREATE TABLE DetalleVentas (
    IdDetalleVenta      INT IDENTITY(1,1)   NOT NULL,
    IdVenta             INT                 NOT NULL,
    IdProducto          INT                 NOT NULL,
    Cantidad            INT                 NOT NULL,
    PrecioUnitario      DECIMAL(10,2)       NOT NULL,
    Subtotal            DECIMAL(10,2)       NOT NULL,
    CONSTRAINT PK_DetalleVentas PRIMARY KEY (IdDetalleVenta),
    CONSTRAINT FK_DetalleVentas_Venta FOREIGN KEY (IdVenta)
        REFERENCES Ventas(IdVenta),
    CONSTRAINT FK_DetalleVentas_Producto FOREIGN KEY (IdProducto)
        REFERENCES Productos(IdProducto),
    CONSTRAINT CK_DetalleVentas_Cantidad CHECK (Cantidad > 0)
);
GO

/* ============================================================================
   11. PEDIDOS - Pedidos de pan de hamburguesa (unidades o paquetes de 12)
       con fecha/hora de entrega. Distinto de Ventas (venta directa).
   ============================================================================ */
CREATE TABLE Pedidos (
    IdPedido            INT IDENTITY(1,1)   NOT NULL,
    IdCliente           INT                 NOT NULL,
    IdTienda            INT                 NULL,   -- a qué tienda pertenece (ver Tiendas)
    IdProducto          INT                 NOT NULL,
    IdTrabajador        INT                 NULL,   -- vendedor que lo registró; NULL si lo creó el propio cliente
    TipoPedido          VARCHAR(20)         NOT NULL,   -- 'UNIDADES' | 'PAQUETES' (paquete = 12 unidades)
    Cantidad            INT                 NOT NULL,
    PrecioUnitario      DECIMAL(10,2)       NOT NULL,
    Total               DECIMAL(10,2)       NOT NULL,
    FechaEntrega        DATETIME2           NULL,   -- opcional: pedido puede quedar "sin fecha programada"
    -- 'SOLICITADO' (el cliente lo pidió, esperando que el personal lo
    --   acepte o rechace según stock — solo aplica a pedidos de autoservicio,
    --   los que registra el personal nacen directo en 'PENDIENTE')
    -- 'PENDIENTE' (confirmado, en espera de entrega)
    -- 'RECHAZADO' (el personal lo rechazó; desaparece de "Mis pedidos" del cliente)
    -- 'ENTREGADO' (ver EstadoPago para saber si se pagó al momento o quedó como deuda)
    -- 'CANCELADO' (cancelación manual)
    Estado              VARCHAR(20)         NOT NULL DEFAULT 'PENDIENTE',
    -- Solo tiene valor cuando Estado = 'ENTREGADO'.
    EstadoPago          VARCHAR(20)         NULL,   -- 'PAGADO' | 'DEUDA'
    FechaEntregaReal    DATETIME2           NULL,   -- cuándo se marcó como entregado (distinto de FechaEntrega, la programada)
    FechaPagoDeuda      DATETIME2           NULL,   -- cuándo se saldó una deuda (uso futuro: pago por distintos medios)
    -- Quién realizó cada transición de estado (visible solo para
    -- ADMIN/SUPERADMIN en la app) — quién REGISTRÓ el pedido ya se sabe por
    -- IdTrabajador (NULL = lo registró el propio cliente).
    IdUsuarioAprobo     INT                 NULL,
    FechaAprobacion     DATETIME2           NULL,
    IdUsuarioCancelo    INT                 NULL,   -- personal o el propio cliente (autoservicio)
    FechaCancelacion    DATETIME2           NULL,
    IdUsuarioEntrego    INT                 NULL,
    Notas               NVARCHAR(300)       NULL,
    FechaCreacion       DATETIME2           NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Pedidos PRIMARY KEY (IdPedido),
    CONSTRAINT FK_Pedidos_Cliente FOREIGN KEY (IdCliente)
        REFERENCES Clientes(IdCliente),
    CONSTRAINT FK_Pedidos_Tienda FOREIGN KEY (IdTienda)
        REFERENCES Tiendas(IdTienda),
    CONSTRAINT FK_Pedidos_Producto FOREIGN KEY (IdProducto)
        REFERENCES Productos(IdProducto),
    CONSTRAINT FK_Pedidos_Trabajador FOREIGN KEY (IdTrabajador)
        REFERENCES Trabajadores(IdTrabajador),
    CONSTRAINT FK_Pedidos_UsuarioAprobo FOREIGN KEY (IdUsuarioAprobo)
        REFERENCES Usuarios(IdUsuario),
    CONSTRAINT FK_Pedidos_UsuarioCancelo FOREIGN KEY (IdUsuarioCancelo)
        REFERENCES Usuarios(IdUsuario),
    CONSTRAINT FK_Pedidos_UsuarioEntrego FOREIGN KEY (IdUsuarioEntrego)
        REFERENCES Usuarios(IdUsuario),
    CONSTRAINT CK_Pedidos_TipoPedido CHECK (TipoPedido IN ('UNIDADES','PAQUETES')),
    CONSTRAINT CK_Pedidos_Cantidad CHECK (Cantidad > 0),
    CONSTRAINT CK_Pedidos_Estado CHECK (Estado IN ('SOLICITADO','PENDIENTE','RECHAZADO','ENTREGADO','CANCELADO')),
    CONSTRAINT CK_Pedidos_EstadoPago CHECK (EstadoPago IS NULL OR EstadoPago IN ('PAGADO','DEUDA'))
);
GO

CREATE INDEX IX_Pedidos_FechaEntrega ON Pedidos(FechaEntrega);
CREATE INDEX IX_Pedidos_Cliente ON Pedidos(IdCliente);
GO

/* ============================================================================
   12. CONFIGURACIONES - Parámetros globales del negocio (clave/valor),
       editables por ADMIN/SUPERADMIN desde la app (ej. precio de paquete).
   ============================================================================ */
CREATE TABLE Configuraciones (
    IdConfiguracion         INT IDENTITY(1,1)   NOT NULL,
    Clave                   VARCHAR(50)         NOT NULL,
    Valor                   NVARCHAR(200)       NOT NULL,
    Descripcion             NVARCHAR(300)       NULL,
    FechaActualizacion      DATETIME2           NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Configuraciones PRIMARY KEY (IdConfiguracion),
    CONSTRAINT UQ_Configuraciones_Clave UNIQUE (Clave)
);
GO

/* ============================================================================
   13. MEDIOSPAGOTIENDA - Métodos de pago digitales que cada tienda configura
       para que sus clientes salden deudas (Yape/Plin/Transferencia/Otro).
       Solo ADMIN/SUPERADMIN de esa tienda pueden crearlos/editarlos.
   ============================================================================ */
CREATE TABLE MediosPagoTienda (
    IdMedioPago         INT IDENTITY(1,1)   NOT NULL,
    IdTienda            INT                 NOT NULL,
    Tipo                VARCHAR(20)         NOT NULL,   -- 'YAPE' | 'PLIN' | 'TRANSFERENCIA' | 'OTRO'
    Titular             NVARCHAR(150)       NOT NULL,   -- nombre del dueño de la cuenta/número
    NumeroDestino       VARCHAR(30)         NOT NULL,   -- número de Yape/Plin o de cuenta
    CCI                 VARCHAR(20)         NULL,       -- solo TRANSFERENCIA
    NombreBanco         NVARCHAR(100)       NULL,       -- solo TRANSFERENCIA
    Notas               NVARCHAR(200)       NULL,
    Estado              BIT                 NOT NULL DEFAULT 1,
    FechaCreacion       DATETIME2           NOT NULL DEFAULT SYSUTCDATETIME(),
    FechaActualizacion  DATETIME2           NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_MediosPagoTienda PRIMARY KEY (IdMedioPago),
    CONSTRAINT FK_MediosPagoTienda_Tienda FOREIGN KEY (IdTienda)
        REFERENCES Tiendas(IdTienda),
    CONSTRAINT CK_MediosPagoTienda_Tipo CHECK (Tipo IN ('YAPE','PLIN','TRANSFERENCIA','OTRO'))
);
GO

/* ============================================================================
   14. SOLICITUDESPAGO - Sesión de pago de un solo uso: el cliente elige 1+
       pedidos con deuda + un medio de pago, se genera un código de
       referencia único (para el QR informativo) con expiración. No hay
       verificación bancaria automática (ver Fase 18) — el cliente reporta
       "ya pagué" y el personal confirma manualmente.
   ============================================================================ */
CREATE TABLE SolicitudesPago (
    IdSolicitudPago     INT IDENTITY(1,1)   NOT NULL,
    IdCliente           INT                 NOT NULL,
    IdMedioPago         INT                 NOT NULL,
    CodigoReferencia    VARCHAR(10)         NOT NULL,   -- glosa/nota única para identificar el pago
    MontoTotal          DECIMAL(10,2)       NOT NULL,
    Estado              VARCHAR(20)         NOT NULL DEFAULT 'GENERADO',
    FechaCreacion       DATETIME2           NOT NULL DEFAULT SYSUTCDATETIME(),
    FechaExpiracion     DATETIME2           NOT NULL,
    FechaReporte        DATETIME2           NULL,
    FechaConfirmacion   DATETIME2           NULL,
    CONSTRAINT PK_SolicitudesPago PRIMARY KEY (IdSolicitudPago),
    CONSTRAINT FK_SolicitudesPago_Cliente FOREIGN KEY (IdCliente)
        REFERENCES Clientes(IdCliente),
    CONSTRAINT FK_SolicitudesPago_MedioPago FOREIGN KEY (IdMedioPago)
        REFERENCES MediosPagoTienda(IdMedioPago),
    CONSTRAINT UQ_SolicitudesPago_CodigoReferencia UNIQUE (CodigoReferencia),
    CONSTRAINT CK_SolicitudesPago_Estado CHECK (Estado IN ('GENERADO','REPORTADO','CONFIRMADO','EXPIRADO','CANCELADO'))
);
GO

/* ============================================================================
   15. SOLICITUDPAGOPEDIDOS - Qué pedidos (deudas) cubre cada solicitud de
       pago; un cliente puede juntar 2+ deudas en un solo pago.
   ============================================================================ */
CREATE TABLE SolicitudPagoPedidos (
    IdSolicitudPago     INT NOT NULL,
    IdPedido            INT NOT NULL,
    CONSTRAINT PK_SolicitudPagoPedidos PRIMARY KEY (IdSolicitudPago, IdPedido),
    CONSTRAINT FK_SolicitudPagoPedidos_Solicitud FOREIGN KEY (IdSolicitudPago)
        REFERENCES SolicitudesPago(IdSolicitudPago),
    CONSTRAINT FK_SolicitudPagoPedidos_Pedido FOREIGN KEY (IdPedido)
        REFERENCES Pedidos(IdPedido)
);
GO

/* ============================================================================
   DATOS INICIALES (SEED)
   ============================================================================ */
INSERT INTO Roles (NombreRol, Descripcion) VALUES
    ('CLIENTE',     'Persona que compra productos de la panadería'),
    ('TRABAJADOR',  'Colaborador contratado (vendedor, panadero, repartidor)'),
    ('ADMIN',       'Familiar encargado de un área de la empresa'),
    ('SUPERADMIN',  'Acceso total al sistema y configuración (propietario)');
GO

-- Hamburguesas/Horneados ya operativas; el resto queda como "Próximamente"
-- (Disponible=0) hasta que el negocio las active.
INSERT INTO Tiendas (Nombre, Slug, Disponible) VALUES
    ('Hamburguesas', 'hamburguesas', 1),
    ('Horneados',    'horneados',    1),
    ('Panadería',    'panaderia',    0),
    ('Mercadería',   'mercaderia',   0),
    ('Pastelería',   'pasteleria',   0);
GO

INSERT INTO Categorias (IdTienda, Nombre)
SELECT t.IdTienda, 'Pan de Hamburguesa' FROM Tiendas t WHERE t.Slug = 'hamburguesas'
UNION ALL
SELECT t.IdTienda, 'Horneados' FROM Tiendas t WHERE t.Slug = 'horneados';
GO

INSERT INTO Productos (IdCategoria, Nombre, Descripcion, PrecioUnitario, Stock, UnidadMedida)
SELECT IdCategoria, 'Pan de Hamburguesa Clásico', 'Pan artesanal para hamburguesa, unidad', 0.80, 500, 'UNIDAD'
FROM Categorias WHERE Nombre = 'Pan de Hamburguesa';
GO

-- Producto genérico para que Horneados tenga al menos un ítem configurado
-- mientras no se defina su catálogo real (ver memoria de Fase 16).
INSERT INTO Productos (IdCategoria, Nombre, Descripcion, PrecioUnitario, Stock, UnidadMedida)
SELECT IdCategoria, 'Producto Horneados General', 'Placeholder hasta definir el catálogo real de Horneados', 1.00, 100, 'UNIDAD'
FROM Categorias WHERE Nombre = 'Horneados';
GO

INSERT INTO Configuraciones (Clave, Valor, Descripcion) VALUES
    ('PRECIO_PAQUETE', '3.50', 'Precio por defecto del paquete de 12 panes de hamburguesa (PEN)');
GO
