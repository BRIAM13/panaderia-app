const credencialesConfiguradas =
  Boolean(process.env.SMTP_HOST) &&
  Boolean(process.env.SMTP_USER) &&
  Boolean(process.env.SMTP_PASSWORD);

let transportador = null;
function obtenerTransportador() {
  if (!transportador) {
    const nodemailer = require('nodemailer');
    transportador = nodemailer.createTransport({
      host: process.env.SMTP_HOST,
      port: Number(process.env.SMTP_PORT) || 587,
      secure: Number(process.env.SMTP_PORT) === 465,
      auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASSWORD },
    });
  }
  return transportador;
}

/**
 * Envía un correo. Sin credenciales SMTP en el .env, no falla ni bloquea el
 * flujo — imprime el mensaje en la consola del servidor (modo desarrollo),
 * misma idea que smsService.js.
 */
async function enviarEmail(destinatario, asunto, cuerpoHtml) {
  if (!credencialesConfiguradas) {
    console.log(`[EMAIL - MODO DESARROLLO] Para ${destinatario} | Asunto: ${asunto}\n${cuerpoHtml}`);
    return { enviado: true, modo: 'DESARROLLO' };
  }

  const transporte = obtenerTransportador();
  await transporte.sendMail({
    from: process.env.SMTP_FROM || process.env.SMTP_USER,
    to: destinatario,
    subject: asunto,
    html: cuerpoHtml,
  });
  return { enviado: true, modo: 'REAL' };
}

module.exports = { enviarEmail };
