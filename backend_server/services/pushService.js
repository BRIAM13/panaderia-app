const fs = require('fs');
const path = require('path');
const { initializeApp, cert, getApps } = require('firebase-admin/app');
const { getMessaging } = require('firebase-admin/messaging');

// En local, el archivo vive en config/firebase-service-account.json. En
// Render, los "Secret Files" no admiten subcarpetas en el nombre — quedan
// montados tal cual en /etc/secrets/<archivo> — así que ahí se busca
// primero si existe.
const RUTA_SECRETO_RENDER = '/etc/secrets/firebase-service-account.json';
const RUTA_LOCAL = path.join(__dirname, '..', 'config', 'firebase-service-account.json');

function obtenerApp() {
  if (getApps().length === 0) {
    const ruta = fs.existsSync(RUTA_SECRETO_RENDER) ? RUTA_SECRETO_RENDER : RUTA_LOCAL;
    const credenciales = require(ruta);
    initializeApp({ credential: cert(credenciales) });
  }
}

/**
 * Envía una notificación push a una lista de tokens FCM. Los tokens
 * inválidos/expirados (dispositivo desinstaló la app, etc.) se devuelven
 * en `tokensInvalidos` para que el llamador los borre de
 * DispositivosNotificacion — Firebase no los limpia solo.
 */
async function enviarPush({ tokens, titulo, cuerpo, datos }) {
  if (!tokens || tokens.length === 0) return { enviados: 0, tokensInvalidos: [] };

  obtenerApp();

  const mensaje = {
    notification: { title: titulo, body: cuerpo },
    data: datos ? Object.fromEntries(Object.entries(datos).map(([k, v]) => [k, String(v)])) : undefined,
    tokens,
  };

  const respuesta = await getMessaging().sendEachForMulticast(mensaje);

  const tokensInvalidos = [];
  respuesta.responses.forEach((r, i) => {
    if (!r.success) {
      const codigo = r.error?.code;
      if (codigo === 'messaging/registration-token-not-registered' || codigo === 'messaging/invalid-registration-token') {
        tokensInvalidos.push(tokens[i]);
      }
    }
  });

  return { enviados: respuesta.successCount, tokensInvalidos };
}

module.exports = { enviarPush };
