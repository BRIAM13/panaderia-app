const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const { sql, getPool } = require('../config/db');
const { enviarEmail } = require('./emailService');

const SALT_ROUNDS = Number(process.env.BCRYPT_SALT_ROUNDS) || 12;

/**
 * Propósito propio en CodigosVerificacion. A diferencia de la recuperación
 * de contraseña (que reusa 'AUTORIZAR_CAMBIO' para no tener que migrar el
 * CHECK), acá SÍ hace falta un valor nuevo: `verificarCodigo` busca la fila
 * más reciente sin usar por (IdPersona, Proposito, Destino), así que si el
 * token de activación compartiera propósito con los códigos de 6 dígitos,
 * pedir un código de verificación de correo invalidaría el link de
 * activación (y al revés). Son dos secretos con vidas distintas.
 * Ver database_migrations/2026_09_activacion_cuenta_web.sql.
 */
const PROPOSITO_ACTIVAR_CUENTA = 'ACTIVAR_CUENTA';

/**
 * 48 horas, contra los 10 minutos de un PIN de 6 dígitos. La diferencia no
 * es capricho: un PIN se pide y se escribe en el mismo minuto, con la app
 * abierta. Un link de activación llega a un correo que la persona puede
 * revisar recién en la noche, al día siguiente, o el lunes si pidió el pan
 * un viernes. Con 10 minutos, la enorme mayoría de estos links llegarían
 * vencidos y la cuenta quedaría inservible sin forma de reclamarla.
 *
 * Que sea largo no lo debilita: el secreto no son 6 dígitos adivinables
 * (10^6) sino 256 bits aleatorios, se guarda hasheado, es de un solo uso,
 * y de todos modos la cuenta que protege está bloqueada para el login
 * mientras siga sin activar. 48h es el equilibrio entre "le llega a tiempo
 * a una persona real" y "no queda un link vivo para siempre".
 */
const HORAS_EXPIRACION = 48;

/**
 * De dónde sale el link del correo. `URL_PAGINA_WEB` permite apuntarlo al
 * entorno de pruebas (http://localhost:5173) sin tocar código; el valor por
 * defecto es el dominio real de la página pública, el mismo que ya figura
 * en la lista de orígenes permitidos por CORS en app.js.
 */
const URL_PAGINA_WEB = (process.env.URL_PAGINA_WEB || 'https://panaderiaronceros.com').replace(/\/+$/, '');

/** Dominio del portal donde el cliente de verdad inicia sesión (la app
 * Flutter compilada para web). Se nombra en el correo para que sepa a dónde
 * va a poder entrar cuando termine. */
const URL_PORTAL_APP = 'https://app.panaderiaronceros.com';

/**
 * 32 bytes aleatorios en base64url: 256 bits de entropía, imposibles de
 * adivinar por fuerza bruta, y sin ningún carácter que un cliente de correo
 * o un navegador tenga que escapar al meterlo en la query string (base64url
 * usa solo A-Z a-z 0-9 - _). `randomBytes` es el generador criptográfico
 * del sistema, no Math.random.
 */
function generarTokenActivacion() {
  return crypto.randomBytes(32).toString('base64url');
}

function armarUrlActivacion(idPersona, token) {
  return `${URL_PAGINA_WEB}/activar-cuenta?p=${idPersona}&t=${encodeURIComponent(token)}`;
}

/**
 * Mismo criterio de robustez que mensajeEmailHtml() en otpService.js:
 * tablas en vez de divs (Outlook de escritorio renderiza con el motor de
 * Word), todo el estilo inline (Gmail recorta el <style> del <head>) y
 * texto de previsualización oculto.
 *
 * Acá SÍ hay un botón de verdad: es un <a href> estilizado, que funciona en
 * cualquier cliente de correo. (La nota de otpService sobre "no es un
 * botón" hablaba de otra cosa: de que un correo no puede ejecutar JS para
 * copiar al portapapeles.) Debajo del botón va igual la URL en texto
 * plano, porque algunos clientes corporativos desactivan los enlaces y la
 * única salida ahí es copiar y pegar a mano.
 */
function mensajeActivacionHtml(url) {
  const previsualizacionOculta = `Define tu contraseña para activar tu cuenta. El enlace vence en ${HORAS_EXPIRACION} horas.`;

  return `
<!doctype html>
<html lang="es">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="color-scheme" content="light" />
    <meta name="supported-color-schemes" content="light" />
    <title>Activa tu cuenta</title>
  </head>
  <body style="margin:0;padding:0;background:#f3ece1;" bgcolor="#f3ece1">
    <!-- Texto de previsualización: visible en la lista de la bandeja de entrada, oculto al abrir el correo. -->
    <div style="display:none;max-height:0;overflow:hidden;opacity:0;mso-hide:all;">${previsualizacionOculta}</div>

    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f3ece1;" bgcolor="#f3ece1">
      <tr>
        <td align="center" style="padding:32px 16px;">
          <table role="presentation" width="440" cellpadding="0" cellspacing="0" style="max-width:440px;width:100%;background:#fff8f3;border-radius:20px;overflow:hidden;border:1px solid #f0ded0;" bgcolor="#fff8f3">
            <tr>
              <td style="background:#7a2e1a;padding:20px 28px;" bgcolor="#7a2e1a">
                <span style="font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;color:#ffffff;font-size:15px;font-weight:700;letter-spacing:0.3px;">Panadería Ronceros</span>
              </td>
            </tr>
            <tr>
              <td style="padding:28px 28px 0;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;">
                <p style="margin:0 0 12px;color:#2a1c14;font-size:19px;font-weight:700;line-height:1.35;">¡Gracias por tu pedido!</p>
                <p style="margin:0 0 22px;color:#2a1c14;font-size:15px;line-height:1.55;">Te creamos una cuenta para que puedas seguir tus pedidos y volver a pedir sin escribir tus datos otra vez. Solo falta que elijas tu contraseña.</p>
              </td>
            </tr>
            <tr>
              <td align="center" style="padding:0 28px 8px;">
                <!-- Botón real: un <a href> con padding y fondo. Se usa una
                tabla de una sola celda alrededor porque Outlook ignora el
                padding de un <a>, y sin ella el botón se ve como un simple
                texto subrayado en Windows. -->
                <table role="presentation" cellpadding="0" cellspacing="0">
                  <tr>
                    <td align="center" style="background:#b5451b;border-radius:100px;" bgcolor="#b5451b">
                      <a href="${url}" style="display:inline-block;padding:15px 34px;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;font-size:15px;font-weight:700;color:#ffffff;text-decoration:none;border-radius:100px;">Activar mi cuenta</a>
                    </td>
                  </tr>
                </table>
              </td>
            </tr>
            <tr>
              <td style="padding:18px 28px 0;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;">
                <p style="margin:0 0 6px;color:#6b5849;font-size:12px;line-height:1.5;">Si el botón no funciona, copia y pega esta dirección en tu navegador:</p>
                <p style="margin:0;font-size:12px;line-height:1.5;word-break:break-all;"><a href="${url}" style="color:#7a2e1a;text-decoration:underline;">${url}</a></p>
              </td>
            </tr>
            <tr>
              <td style="padding:20px 28px 28px;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;">
                <p style="margin:0 0 10px;color:#6b5849;font-size:13px;line-height:1.5;">El enlace vence en ${HORAS_EXPIRACION} horas y solo se puede usar una vez. Después de activarla, entras a <a href="${URL_PORTAL_APP}" style="color:#7a2e1a;text-decoration:underline;">${URL_PORTAL_APP.replace('https://', '')}</a> con tu DNI y la contraseña que elijas.</p>
                <p style="margin:0;color:#9c8b7c;font-size:12px;line-height:1.5;">Si no hiciste ningún pedido, ignora este correo — sin activarla, la cuenta no sirve para entrar a ningún lado.</p>
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
</html>
  `.trim();
}

/** Alternativa en texto plano — la exige la especificación MIME
 * (multipart/alternative) y mejora la entregabilidad; también es lo único
 * que ven algunos lectores de pantalla y clientes de correo minimalistas. */
function mensajeActivacionTexto(url) {
  return [
    'Panadería Ronceros',
    '',
    '¡Gracias por tu pedido!',
    '',
    'Te creamos una cuenta para que puedas seguir tus pedidos y volver a pedir sin escribir tus datos otra vez. Solo falta que elijas tu contraseña:',
    '',
    url,
    '',
    `El enlace vence en ${HORAS_EXPIRACION} horas y solo se puede usar una vez.`,
    `Después de activarla, entras a ${URL_PORTAL_APP} con tu DNI y la contraseña que elijas.`,
    '',
    'Si no hiciste ningún pedido, ignora este correo — sin activarla, la cuenta no sirve para entrar a ningún lado.',
  ].join('\n');
}

/**
 * Crea la cuenta de acceso de un cliente que se registró desde la página
 * web, PENDIENTE DE ACTIVACIÓN. Mismas guardas que
 * `intentarClonarUsuarioCliente` (no pisa una cuenta existente ni un
 * nombre de usuario ya tomado), pero con dos diferencias que son el punto
 * de todo este cambio:
 *
 *  - `Activado = 0`: el login la rechaza hasta que la persona confirme el
 *    correo (ver authController.login).
 *  - La contraseña inicial es un valor ALEATORIO que no se guarda ni se le
 *    dice a nadie, en vez de ser el propio DNI. El DNI en Perú no es un
 *    secreto (está en cualquier boleta), así que usarlo como contraseña
 *    equivale a no tener contraseña. Qué valor exacto tiene este hash es
 *    irrelevante justamente porque nadie lo conoce: es un relleno para
 *    satisfacer el NOT NULL de la columna, y se reemplaza entero por la
 *    contraseña que la persona elija al activar. Aunque alguien lograra
 *    adivinarlo, `Activado = 0` seguiría bloqueando el login.
 *
 * `RequiereCambioPassword` queda en 0: el cambio ya lo hace la activación
 * misma, no tiene sentido volver a pedírselo apenas entre.
 *
 * Corre DENTRO de la transacción del pedido: si el pedido falla y se hace
 * rollback, no queda una cuenta huérfana.
 */
async function crearUsuarioPendienteActivacion(transaction, { idPersona, nombreUsuario }) {
  const yaTieneCuenta = await new sql.Request(transaction)
    .input('IdPersona', sql.Int, idPersona)
    .query('SELECT IdUsuario FROM Usuarios WHERE IdPersona = @IdPersona');
  if (yaTieneCuenta.recordset.length > 0) {
    return { creado: false, motivo: 'La persona ya tiene una cuenta de acceso' };
  }

  const usuarioTomado = await new sql.Request(transaction)
    .input('NombreUsuario', sql.VarChar(50), nombreUsuario)
    .query('SELECT IdUsuario FROM Usuarios WHERE NombreUsuario = @NombreUsuario');
  if (usuarioTomado.recordset.length > 0) {
    return { creado: false, motivo: 'Ese identificador ya está en uso como nombre de usuario' };
  }

  const rolResult = await new sql.Request(transaction).query("SELECT IdRol FROM Roles WHERE NombreRol = 'CLIENTE'");
  const idRolCliente = rolResult.recordset[0].IdRol;
  const passwordHash = await bcrypt.hash(crypto.randomBytes(32).toString('base64url'), SALT_ROUNDS);

  await new sql.Request(transaction)
    .input('IdPersona', sql.Int, idPersona)
    .input('NombreUsuario', sql.VarChar(50), nombreUsuario)
    .input('PasswordHash', sql.VarChar(255), passwordHash)
    .input('IdRol', sql.Int, idRolCliente)
    .query(`
      INSERT INTO Usuarios (IdPersona, NombreUsuario, PasswordHash, IdRol, RequiereCambioPassword, Activado)
      VALUES (@IdPersona, @NombreUsuario, @PasswordHash, @IdRol, 0, 0)
    `);

  return { creado: true };
}

/**
 * Genera el token de activación, invalida cualquier otro anterior y lo
 * guarda hasheado. Devuelve el token EN CLARO (única vez que existe fuera
 * del correo) para que quien llame lo mande.
 *
 * A propósito NO envía el correo y acepta una `transaction`: cuando esto
 * corre dentro del alta de un pedido web, la fila del código tiene que
 * entrar en el mismo commit que la Persona, el Cliente y el Usuario — si
 * el pedido termina en rollback, no puede quedar vivo un token para una
 * cuenta que nunca existió. El envío del correo, en cambio, NO se puede
 * deshacer con un rollback, así que va después del commit (ver
 * `enviarCorreoActivacion`). Sin `transaction`, usa el pool normal.
 *
 * Sin cooldown, a diferencia de `solicitarCodigo`: hoy esto solo se dispara
 * al crear una cuenta nueva (una vez en la vida de esa persona) y la ruta
 * pública que lo dispara ya tiene su propio límite por IP. Si algún día se
 * agrega un botón de "reenviar correo de activación", ahí sí hay que
 * sumarle el cooldown.
 */
async function registrarActivacionCuenta({ transaction = null, idPersona, destino }) {
  const ejecutor = async (query, aplicarInputs) => {
    const request = transaction ? new sql.Request(transaction) : (await getPool()).request();
    aplicarInputs(request);
    return request.query(query);
  };

  await ejecutor(
    `UPDATE CodigosVerificacion SET Usado = 1
     WHERE IdPersona = @IdPersona AND Proposito = @Proposito AND Usado = 0`,
    (r) => r.input('IdPersona', sql.Int, idPersona).input('Proposito', sql.VarChar(30), PROPOSITO_ACTIVAR_CUENTA),
  );

  const token = generarTokenActivacion();
  const tokenHash = await bcrypt.hash(token, SALT_ROUNDS);
  const fechaExpiracion = new Date(Date.now() + HORAS_EXPIRACION * 60 * 60_000);

  await ejecutor(
    `INSERT INTO CodigosVerificacion (IdPersona, Canal, Proposito, Destino, CodigoHash, FechaExpiracion)
     VALUES (@IdPersona, @Canal, @Proposito, @Destino, @CodigoHash, @FechaExpiracion)`,
    (r) =>
      r
        .input('IdPersona', sql.Int, idPersona)
        .input('Canal', sql.VarChar(10), 'EMAIL')
        .input('Proposito', sql.VarChar(30), PROPOSITO_ACTIVAR_CUENTA)
        .input('Destino', sql.VarChar(150), destino)
        .input('CodigoHash', sql.VarChar(255), tokenHash)
        .input('FechaExpiracion', sql.DateTime2, fechaExpiracion),
  );

  return { token };
}

/** Manda el correo con el botón de activación. Se llama DESPUÉS del commit
 * (ver el comentario de `registrarActivacionCuenta`). */
async function enviarCorreoActivacion({ idPersona, destino, token }) {
  const url = armarUrlActivacion(idPersona, token);
  await enviarEmail(destino, 'Activa tu cuenta de Panadería Ronceros', mensajeActivacionHtml(url), mensajeActivacionTexto(url));
}

module.exports = {
  PROPOSITO_ACTIVAR_CUENTA,
  HORAS_EXPIRACION,
  generarTokenActivacion,
  armarUrlActivacion,
  crearUsuarioPendienteActivacion,
  registrarActivacionCuenta,
  enviarCorreoActivacion,
};
