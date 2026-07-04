const credencialesConfiguradas =
  Boolean(process.env.TWILIO_ACCOUNT_SID) &&
  Boolean(process.env.TWILIO_AUTH_TOKEN) &&
  Boolean(process.env.TWILIO_FROM_NUMBER);

let clienteTwilio = null;
function obtenerClienteTwilio() {
  if (!clienteTwilio) {
    // Import perezoso: si nunca hay credenciales configuradas, el SDK de
    // Twilio ni siquiera se inicializa.
    const twilio = require('twilio');
    clienteTwilio = twilio(process.env.TWILIO_ACCOUNT_SID, process.env.TWILIO_AUTH_TOKEN);
  }
  return clienteTwilio;
}

/**
 * Envía un SMS. Sin credenciales de Twilio en el .env, no falla ni bloquea
 * el flujo — imprime el mensaje en la consola del servidor (modo
 * desarrollo), para poder probar la verificación de celular de punta a
 * punta sin gastar SMS reales ni depender de una cuenta de Twilio.
 */
async function enviarSms(numero, mensaje) {
  if (!credencialesConfiguradas) {
    console.log(`[SMS - MODO DESARROLLO] Para ${numero}: ${mensaje}`);
    return { enviado: true, modo: 'DESARROLLO' };
  }

  const cliente = obtenerClienteTwilio();
  await cliente.messages.create({
    body: mensaje,
    from: process.env.TWILIO_FROM_NUMBER,
    to: numero,
  });
  return { enviado: true, modo: 'REAL' };
}

module.exports = { enviarSms };
