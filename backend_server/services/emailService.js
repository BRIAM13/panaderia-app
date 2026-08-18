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

/**
 * Los encabezados (From, Subject) van en ASCII salvo que se codifiquen
 * como "encoded-word" (RFC 2047) — sin esto, tildes/ñ en esos campos
 * llegan como símbolos rotos aunque el cuerpo HTML sí las muestre bien.
 */
function codificarEncabezado(texto) {
  return `=?UTF-8?B?${Buffer.from(texto, 'utf-8').toString('base64')}?=`;
}

/**
 * multipart/alternative con una parte de texto plano y una de HTML: el
 * cliente de correo elige la mejor que sepa mostrar (los lectores de
 * pantalla y clientes minimalistas usan la de texto). Sin la parte de
 * texto, algunos filtros antispam penalizan la entregabilidad por
 * considerarlo "solo HTML" — señal típica de correo masivo/spam.
 */
function construirMensajeMime(destinatario, asunto, cuerpoTexto, cuerpoHtml) {
  const limite = `limite_${Date.now()}_${Math.random().toString(36).slice(2)}`;
  const mensaje = [
    `From: ${codificarEncabezado('Panadería Ronceros')} <${process.env.GOOGLE_SENDER_EMAIL}>`,
    `To: ${destinatario}`,
    `Subject: ${codificarEncabezado(asunto)}`,
    'MIME-Version: 1.0',
    `Content-Type: multipart/alternative; boundary="${limite}"`,
    '',
    `--${limite}`,
    'Content-Type: text/plain; charset=UTF-8',
    // Sin esto, el cuerpo se asume ASCII de 7 bits y las tildes/ñ (bytes
    // UTF-8 de 2+) llegan corruptas — la codificación base64 del mensaje
    // completo para la Gmail API es un transporte aparte, no alcanza.
    'Content-Transfer-Encoding: 8bit',
    '',
    cuerpoTexto,
    '',
    `--${limite}`,
    'Content-Type: text/html; charset=UTF-8',
    'Content-Transfer-Encoding: 8bit',
    '',
    cuerpoHtml,
    '',
    `--${limite}--`,
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
async function enviarEmail(destinatario, asunto, cuerpoHtml, cuerpoTexto) {
  if (!credencialesConfiguradas) {
    console.log(`[EMAIL - MODO DESARROLLO] Para ${destinatario} | Asunto: ${asunto}\n${cuerpoTexto || cuerpoHtml}`);
    return { enviado: true, modo: 'DESARROLLO' };
  }

  const cliente = obtenerClienteOAuth();
  const { token } = await cliente.getAccessToken();
  const raw = construirMensajeMime(destinatario, asunto, cuerpoTexto || asunto, cuerpoHtml);

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
