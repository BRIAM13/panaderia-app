# Informe de seguridad — Panadería Ronceros API

Revisión del backend (`backend_server/`) mapeada contra el [OWASP Top 10 (2021)](https://owasp.org/Top10/), como referencia para el capítulo de seguridad de la tesis. Incluye qué ya estaba resuelto antes de esta revisión, qué se corrigió en esta pasada, y qué queda documentado como limitación conocida (no oculta).

Fecha de la revisión: agosto de 2026.

## Resumen de cambios de esta pasada

| Hallazgo | Antes | Después |
|---|---|---|
| Sin cabeceras de seguridad HTTP | Ninguna (`helmet` no estaba instalado) | `helmet` habilitado en `app.js` |
| CORS abierto a cualquier origen | `cors()` sin restricción | Lista blanca de orígenes (`panaderiaronceros.com`, `www.`, `app.`) |
| Sin límite de intentos en `/auth/login` | Sin protección propia (las rutas públicas de `publicoController.js` sí tenían límites ad-hoc) | `express-rate-limit`: 20 intentos / 15 min por IP |
| 2 dependencias con vulnerabilidad **alta** | `brace-expansion`, `fast-xml-parser` desactualizadas | Actualizadas vía `npm audit fix` |

## Mapeo OWASP Top 10 (2021)

### A01 — Broken Access Control
- **Estado: cubierto.** Todas las rutas de gestión pasan por `verificarToken` + `autorizarRoles(...)` (`middlewares/authMiddleware.js`), verificado contra el rol real guardado en la base de datos en cada request (no solo en el JWT). El caso "cliente propio" (ej. `mi-perfil`) nunca acepta un `:id` de la URL — siempre resuelve por `idPersona` del token, así nadie puede leer/editar el perfil de otro cliente cambiando un número en la petición.
- Detección de cambio de rol en caliente (`tipo: 'ROL_CAMBIADO'`): si el rol de un usuario cambia mientras tiene una sesión abierta, el próximo refresh de token lo detecta y fuerza un logout, en vez de dejarlo operar con permisos viejos.

### A02 — Cryptographic Failures
- **Estado: cubierto.** Contraseñas con `bcryptjs` (12 rondas de sal, `BCRYPT_SALT_ROUNDS`), nunca en texto plano ni siquiera en logs de auditoría. JWT firmado con secreto de entorno, nunca hardcodeado. Todo el tráfico corre sobre HTTPS (Render/Vercel lo fuerzan a nivel de plataforma).
- **Limitación conocida:** la base de datos (MariaDB) no tiene cifrado en reposo propio más allá de lo que ofrezca el proveedor de hosting — aceptable para el volumen y sensibilidad de datos actual (nombres, teléfonos, direcciones; no se guardan tarjetas ni datos financieros completos, los pagos son manuales con comprobante).

### A03 — Injection
- **Estado: cubierto.** Ninguna consulta arma SQL por concatenación de datos de usuario — todas usan parámetros tipados (`sql.Int`, `sql.VarChar(n)`, etc.) vía el shim de `config/db.js`, incluso tras la migración de SQL Server a MariaDB. Los pocos lugares con interpolación de string en la consulta (ej. listas de IDs para un `IN (...)` en `clientesController.js`/`pedidosController.js`) siempre interpolan valores ya validados como enteros (`Number(...)`), nunca texto libre del usuario.
- Validación de entrada centralizada en `middlewares/validators.js` antes de que cualquier controlador toque la base de datos (confirmado en las pruebas de integración de `POST /auth/login`).

### A04 — Insecure Design
- **Estado: cubierto para el caso de negocio real.** El flujo de verificación de identidad (DNI/RUC contra RENIEC/SUNAT antes de clonar una cuenta) evita que alguien se registre con datos inventados. Las reglas de horario de pedido/recojo se revalidan siempre en el servidor con la hora real (nunca se confía en lo que mande el cliente — ver `utils/horariosPanaderia.js` y sus pruebas unitarias).

### A05 — Security Misconfiguration
- **Corregido en esta pasada:** faltaban las cabeceras de seguridad estándar (`X-Content-Type-Options`, `X-Frame-Options`, `Strict-Transport-Security`, etc.) — ahora las agrega `helmet`. CORS aceptaba peticiones de cualquier origen web — ahora restringido a los 3 dominios reales que consumen la API desde un navegador.
- Variables sensibles (credenciales de base de datos, secreto JWT, claves de API externas) viven en variables de entorno (`.env`, nunca versionado — confirmado en `.gitignore`), no en el código.

### A06 — Vulnerable and Outdated Components
- **Corregido parcialmente:** `npm audit fix` resolvió las 2 vulnerabilidades de severidad **alta** (`brace-expansion`, `fast-xml-parser`) sin cambios que rompan nada (confirmado con la suite de pruebas).
- **Limitación conocida, aceptada y monitoreada:** quedan 5 vulnerabilidades de severidad **moderada**, todas originadas en una versión vieja de `uuid` dentro de la cadena de dependencias de `firebase-admin` (usado para notificaciones push). Arreglarlas de raíz requiere `npm audit fix --force`, que **degradaría `firebase-admin` a una versión mayor anterior** (rompería las notificaciones push) — no se aplicó a propósito, priorizando la disponibilidad del sistema de notificaciones sobre una vulnerabilidad de severidad moderada sin exploit conocido contra esta app. Queda documentado para revisar cuando `firebase-admin` publique una versión reciente que ya no dependa de ese `uuid` viejo.

### A07 — Identification and Authentication Failures
- **Corregido en esta pasada:** `/auth/login` no tenía ningún límite de intentos propio — ahora tiene `express-rate-limit` (20 intentos / 15 min por IP), que dificulta un ataque de fuerza bruta de contraseñas sin afectar a un usuario real que se equivoca alguna vez.
- Los flujos sensibles del lado del cliente (cambiar celular/correo/contraseña) exigen un código de un solo uso enviado al canal ya verificado, no solo la sesión activa — así que aunque alguien tome el celular desbloqueado de un cliente, no puede cambiar su contraseña sin también tener acceso a su SMS/correo.

### A08 — Software and Data Integrity Failures
- **Estado: cubierto para el alcance actual.** No hay actualizaciones automáticas ni deserialización de datos no confiables. El pipeline de despliegue es manual (`git push` → Render/Vercel), sin pasos de CI que ejecuten código de terceros sin revisión.

### A09 — Security Logging and Monitoring Failures
- **Estado: parcialmente cubierto.** Existe una tabla `Auditoria_Log` que registra acciones sensibles (login, cambios de cliente, canjes de puntos, campañas de reactivación, etc.) con usuario, IP, user-agent y datos antes/después.
- **Limitación conocida:** no hay alertas automáticas ni un dashboard de monitoreo — la auditoría es consultable pero no proactiva. Aceptable para el tamaño actual del equipo (revisión manual cuando hace falta), sería el siguiente paso natural si el negocio crece.

### A10 — Server-Side Request Forgery (SSRF)
- **Estado: no aplica de forma significativa.** El backend no arma peticiones salientes a URLs que el usuario controle — las únicas llamadas externas (RENIEC/SUNAT vía apiperu.dev, Twilio, Firebase) van a endpoints fijos y hardcodeados, nunca a una URL que llegue en el body de una petición.

## Pruebas automatizadas relacionadas

Ver `__tests__/app.test.js`: confirma que `POST /auth/login` rechaza credenciales inválidas con 400 **antes** de tocar la base de datos (evita filtrar si un usuario existe o no vía tiempos de respuesta distintos), y que una ruta inexistente responde 404 en vez de un error 500 que exponga detalles internos.
