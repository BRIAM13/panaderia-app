# Panadería Ronceros — Super App

> Documentación de referencia para actualizar el portafolio. Este archivo
> resume qué es el proyecto, el stack técnico, los módulos construidos y
> los retos de ingeniería más destacables — pensado para que se pueda
> convertir directamente en la descripción de un proyecto de portafolio,
> o para dárselo a Claude como contexto y que ayude a redactarlo.
>
> Última actualización: 2026-08-21.

## Qué es

Sistema completo de gestión y venta para **Panadería Ronceros** (nombre
comercial formal: Panadería y Pastelería Briam, RUC 10223034255), un
negocio familiar en Pisco, Perú. No es solo una app de pedidos: es una
"super app" que cubre operación interna (múltiples tiendas/rubros bajo
un mismo negocio), autoservicio de clientes por dos canales distintos
(app móvil y página web), y toda la logística de horarios/producción de
una panadería real, incluyendo control de stock en vivo por parte del
dueño.

Tres tiendas conviven en el mismo sistema, cada una con su propio flujo:
**Hamburguesas** (pan de hamburguesa por paquete), **Horneados** (pedidos
a medida: carne, presentación, aderezo) y **Panadería** (pan de agua/
francés y otros, por unidad, con el sistema de turnos/franjas descrito
más abajo).

## Stack técnico

| Capa | Tecnología |
|---|---|
| App móvil (Android/iOS) | Flutter, `flutter_animate`, Firebase Cloud Messaging (push), `local_auth` (biometría), `geolocator`/`geocoding`, `fl_chart`, Google Mobile Ads |
| Backend | Node.js + Express, MariaDB (con una capa propia que traduce sintaxis T-SQL→MySQL, ver abajo), JWT (`jsonwebtoken`), `bcryptjs`, `firebase-admin` (push), `google-auth-library` (envío de correo vía Gmail API), Twilio |
| Página web pública | React 19 + TypeScript + Vite, Tailwind CSS 4, Framer Motion |
| Verificación de identidad | API externa (apiperu.dev) contra RENIEC (DNI) y SUNAT (RUC), con simulador de respaldo si la API paga no responde |
| Infraestructura | Backend en Render, página web en Vercel, base de datos MariaDB administrada, distribución Android por Google Play (`com.ronceroslabs.panaderiaronceros`) y APK de descarga directa |
| Dominios | panaderiaronceros.com (sitio público), app.panaderiaronceros.com (portal web de la app Flutter) |

## Arquitectura

Un único backend Express sirve a **tres clientes distintos** con
necesidades muy diferentes:

1. **La app Flutter** (personal de las 3 tiendas + clientes con cuenta):
   autenticación JWT completa, roles por tienda, y todas las pantallas
   de gestión (pedidos, deudas, historial de ventas, clientes, medios de
   pago, precios).
2. **La página web pública** (`pagina-web/`): sin login — cualquier
   visitante puede pedir pan dejando su DNI/RUC (que se valida de verdad
   contra RENIEC/SUNAT) y hacer seguimiento de sus pedidos en tiempo
   real, sin crear cuenta.
3. **Un portal web** (`app.panaderiaronceros.com`) que reutiliza la
   misma app Flutter compilada para web, para quien prefiera no instalar
   nada.

La base de datos fue diseñada originalmente para SQL Server (ver el
primer commit del proyecto) y luego migró a MariaDB **sin reescribir
ninguna consulta**: `config/db.js` implementa una capa que reproduce la
API de `mssql` sobre `mysql2`, traduciendo sintaxis T-SQL a MySQL sobre
la marcha (`SELECT TOP N` → `LIMIT N`, `DATEADD`, `ISNULL` → `IFNULL`,
`SYSUTCDATETIME()`, etc.).

## Módulos y funcionalidades

- **Autenticación y roles**: JWT con refresh silencioso, revocación de
  acceso instantánea (cada petición revalida el rol/estado actual del
  usuario, no solo al hacer login), aviso push inmediato cuando cambia
  el rol de alguien con la sesión abierta, biometría opcional, rol
  `VISITOR` de solo lectura para revisores externos (Google Play, Culpi).
- **Gestión por tienda** (Hamburguesas, Horneados, Panadería): pedidos,
  aprobar/rechazar/entregar/cancelar, deudas y pagos, historial de
  ventas, clientes, trabajadores, medios de pago, ajuste de precios —
  con permisos por rol y por tienda asignada.
- **Autoservicio del cliente** (dentro de la app, con cuenta): hacer su
  propio pedido, ver sus pedidos y deudas pendientes.
- **Pedido público sin cuenta** (página web): deja DNI/RUC + celular,
  el sistema verifica el documento contra RENIEC/SUNAT en tiempo real
  (con auto-verificación apenas se completan los dígitos), elige
  producto/cantidad/fecha/hora de recojo, y hace seguimiento del estado
  de sus pedidos recientes sin necesidad de volver a buscar (se
  actualiza solo).
- **Sistema de horarios de Panadería** (el módulo más elaborado del
  proyecto): el día se reparte en dos franjas de recojo secuenciales —
  mañana (4am) y tarde (3pm) — cada una con su propio interruptor
  manual: si el dueño se queda sin stock de una hornada, la apaga desde
  la app y los pedidos nuevos saltan directo a la otra franja, sin tocar
  código ni llamar a nadie. Domingo tiene su propio corte de horario.
  Todo se sincroniza en tiempo real con la página web pública (sondeo
  cada 30s, sin necesidad de recargar).
- **Notificaciones push**: avisos al personal por nuevo pedido, al
  cliente por cambio de estado, y al usuario si su rol cambia — con
  canal de notificación explícito en Android para que sí aparezca el
  banner con la app en segundo plano.
- **Envío de correo transaccional**: verificación de cuenta con código
  de 6 dígitos, vía Gmail API (OAuth2) con plantillas HTML propias.

## Retos técnicos destacados

Buen material para portafolio — problemas reales resueltos, no solo
funcionalidades:

- **Migración de motor de base de datos sin reescribir queries**: capa
  de traducción T-SQL→MySQL a medida (`config/db.js`), permitiendo
  migrar de SQL Server a MariaDB manteniendo intacta toda la lógica de
  negocio ya escrita.
- **Motor de reglas de horario configurable**: piso de tolerancia (30
  min), techo de cierre, dos franjas de recojo con interruptores
  manuales en vivo, corte especial de domingo — todo combinable y
  reconfigurable sin redeploy, con validación dura idéntica en cliente y
  servidor (el servidor nunca confía en lo que mande el navegador).
- **Selector de hora tipo rueda construido desde cero**: sin ninguna
  librería, con animación por `requestAnimationFrame`, soporte de
  arrastre táctil/mouse, scroll de rueda, clic directo, y giro infinito
  real — resolviendo en el camino bugs sutiles de posición (el resaltado
  adelantándose a la animación, el pointer capture del navegador
  redirigiendo el evento `click` al contenedor entero en vez del ítem
  tocado).
- **Bug de `position: fixed` atrapado por un ancestro animado**: una
  ventana emergente anidada dentro de un `motion.div` con `transform`
  quedaba comprimida al alto del contenedor en vez de cubrir toda la
  pantalla — diagnosticado y resuelto con un portal directo a
  `document.body`, arreglando de raíz todos los selectores del sitio a
  la vez.
- **Verificación real de documentos sin depender 100% de una API paga**:
  cae a un simulador local si RENIEC/SUNAT no responde (para no
  bloquear la operación), pero nunca inventa un documento como
  "encontrado" cuando la API real dice que no existe.
- **Sincronización en tiempo real sin WebSockets**: sondeo liviano cada
  20–30s en los puntos donde de verdad importa (seguimiento de pedido,
  horarios), con límites de intentos por IP separados según el costo
  real de cada endpoint (los que llaman a la API paga de RENIEC/SUNAT
  son mucho más estrictos que los de solo lectura).

## Despliegue

- Backend: Render (`panaderia-backend-vtdy.onrender.com`), desde
  `backend_server/`.
- Página web: Vercel, desde `pagina-web/`.
- App: Google Play Store interno/producción (versión actual 1.1.6+9) +
  descarga directa del `.apk` desde la propia página web, con selector
  para elegir entre ambas opciones.
- Un solo `git push` a `main` despliega backend y web a la vez (repos
  monorepo).

## Línea de tiempo (hitos, no exhaustivo)

1. Commit inicial: Super App panadería (Flutter + Node/Express + SQL
   Server).
2. Migración de SQL Server a MariaDB.
3. Sistema de roles, revocación de acceso y notificaciones push por
   cambio de rol.
4. Rediseño completo de la página web pública (paleta, animaciones,
   mascota interactiva).
5. Rebrand: Corporación Ronceros → Panadería Ronceros.
6. Pedido público sin cuenta con selector de fecha/hora propio y
   verificación real de DNI/RUC.
7. Sistema de turnos/franjas de recojo con control de stock en vivo
   (el más reciente, agosto 2026).
