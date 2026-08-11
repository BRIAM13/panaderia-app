const credencialesConfiguradas = Boolean(process.env.RESEND_API_KEY);

/**
 * Envía un correo vía la API HTTP de Resend (no SMTP: Render no permite
 * conexiones salientes por el puerto 587/465, se cuelga ~2min y termina en
 * ETIMEDOUT — probado en producción). Sin RESEND_API_KEY en el .env, no
 * falla ni bloquea el flujo — imprime el mensaje en la consola del servidor
 * (modo desarrollo), misma idea que smsService.js.
 */
async function enviarEmail(destinatario, asunto, cuerpoHtml) {
  if (!credencialesConfiguradas) {
    console.log(`[EMAIL - MODO DESARROLLO] Para ${destinatario} | Asunto: ${asunto}\n${cuerpoHtml}`);
    return { enviado: true, modo: 'DESARROLLO' };
  }

  const respuesta = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${process.env.RESEND_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: process.env.RESEND_FROM || 'Corporación Ronceros <onboarding@resend.dev>',
      to: [destinatario],
      subject: asunto,
      html: cuerpoHtml,
    }),
  });

  if (!respuesta.ok) {
    const cuerpoError = await respuesta.text().catch(() => '');
    throw new Error(`Resend respondió ${respuesta.status}: ${cuerpoError}`);
  }

  return { enviado: true, modo: 'REAL' };
}

module.exports = { enviarEmail };
