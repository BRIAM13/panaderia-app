const { OAuth2Client } = require('google-auth-library');

const credencialesConfiguradas =
  Boolean(process.env.GOOGLE_CLIENT_ID) &&
  Boolean(process.env.GOOGLE_CLIENT_SECRET) &&
  Boolean(process.env.GOOGLE_REFRESH_TOKEN) &&
  Boolean(process.env.GOOGLE_SENDER_EMAIL);

let clienteOAuth = null;
function obtenerClienteOAuth() {
  if (!clienteOAuth) {
    clienteOAuth = new OAuth2Client(process.env.GOOGLE_CLIENT_ID, process.env.GOOGLE_CLIENT_SECRET);
    clienteOAuth.setCredentials({ refresh_token: process.env.GOOGLE_REFRESH_TOKEN });
  }
  return clienteOAuth;
}

function codificarBase64Url(texto) {
  return Buffer.from(texto)
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

function construirMensajeMime(destinatario, asunto, cuerpoHtml) {
  const asuntoCodificado = `=?UTF-8?B?${Buffer.from(asunto, 'utf-8').toString('base64')}?=`;
  const mensaje = [
    `From: Corporación Ronceros <${process.env.GOOGLE_SENDER_EMAIL}>`,
    `To: ${destinatario}`,
    `Subject: ${asuntoCodificado}`,
    'MIME-Version: 1.0',
    'Content-Type: text/html; charset=UTF-8',
    '',
    cuerpoHtml,
  ].join('\r\n');
  return codificarBase64Url(mensaje);
}

/**
 * Envía un correo vía la Gmail API (OAuth2, no SMTP: Render no permite
 * conexiones salientes por el puerto 587/465, se cuelga ~2min y termina en
 * ETIMEDOUT — probado en producción). La Gmail API usa HTTPS, que sí
 * funciona. Sin credenciales en el .env, no falla ni bloquea el flujo —
 * imprime el mensaje en la consola del servidor (modo desarrollo), misma
 * idea que smsService.js.
 */
async function enviarEmail(destinatario, asunto, cuerpoHtml) {
  if (!credencialesConfiguradas) {
    console.log(`[EMAIL - MODO DESARROLLO] Para ${destinatario} | Asunto: ${asunto}\n${cuerpoHtml}`);
    return { enviado: true, modo: 'DESARROLLO' };
  }

  const cliente = obtenerClienteOAuth();
  const { token } = await cliente.getAccessToken();
  const raw = construirMensajeMime(destinatario, asunto, cuerpoHtml);

  const respuesta = await fetch('https://gmail.googleapis.com/gmail/v1/users/me/messages/send', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ raw }),
  });

  if (!respuesta.ok) {
    const cuerpoError = await respuesta.text().catch(() => '');
    throw new Error(`Gmail API respondió ${respuesta.status}: ${cuerpoError}`);
  }

  return { enviado: true, modo: 'REAL' };
}

module.exports = { enviarEmail };
