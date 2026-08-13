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
 *
 * Si no se manda `titulo`, el mensaje sale sin bloque `notification` —
 * queda "silencioso": no aparece ningún banner en el dispositivo, pero la
 * app (si está en primer plano) igual recibe el `data` y puede reaccionar
 * (ej. refrescar una lista sola). Se usa para sincronizar pantallas entre
 * el personal sin bombardearlos de notificaciones por cada acción de
 * otro — a diferencia de los avisos al cliente, que sí deben ser
 * visibles.
 */
async function enviarPush({ tokens, titulo, cuerpo, datos }) {
  if (!tokens || tokens.length === 0) return { enviados: 0, tokensInvalidos: [] };

  obtenerApp();

  const mensaje = {
    ...(titulo ? { notification: { title: titulo, body: cuerpo } } : {}),
    data: datos ? Object.fromEntries(Object.entries(datos).map(([k, v]) => [k, String(v)])) : undefined,
    tokens,
    // Sin esto, Android trata un mensaje data-only (sin `notification`,
    // como los "silenciosos" de acá arriba) como prioridad normal y puede
    // demorarlo bastante en Doze/segundo plano — es justo lo que hacía que
    // el Dashboard de otro dispositivo no se refrescara solo y hubiera que
    // deslizar a mano para forzar la recarga. "high" no muestra ningún
    // banner (eso lo decide `notification`, no la prioridad) — solo pide
    // entrega inmediata.
    android: { priority: 'high' },
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
