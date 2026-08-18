const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const { sql, getPool } = require('../config/db');
const { enviarSms } = require('./smsService');
const { enviarEmail } = require('./emailService');

const SALT_ROUNDS = Number(process.env.BCRYPT_SALT_ROUNDS) || 12;
const MINUTOS_EXPIRACION = 10;
const SEGUNDOS_COOLDOWN = 60;
const MAX_INTENTOS = 5;

/** Error tipado: el controller lo mapea a un código HTTP y mensaje claro. */
class OtpError extends Error {
  constructor(tipo, mensaje) {
    super(mensaje);
    this.tipo = tipo; // 'COOLDOWN' | 'INVALIDO' | 'EXPIRADO' | 'MAX_INTENTOS'
  }
}

function generarCodigo() {
  // 6 dígitos, con ceros a la izquierda si hace falta (ej. "004821").
  return String(crypto.randomInt(0, 1_000_000)).padStart(6, '0');
}

function mensajeSms(codigo) {
  return `Panadería Ronceros: tu código de verificación es ${codigo}. Vence en ${MINUTOS_EXPIRACION} minutos. Nunca lo compartas con nadie.`;
}

/**
 * Tablas en vez de divs/flex: es la única forma de que el layout no se
 * rompa en Outlook de escritorio (renderiza el HTML con el motor de Word,
 * que ignora la mayoría de CSS moderno) — regla básica de email marketing.
 * Todo el estilo va inline porque muchos clientes (Gmail incluido) recortan
 * o ignoran <style> en el <head>.
 */
function mensajeEmailHtml(codigo) {
  const previsualizacionOculta = `Tu código de verificación es ${codigo}. Vence en ${MINUTOS_EXPIRACION} minutos.`;

  return `
<!doctype html>
<html lang="es">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="color-scheme" content="light" />
    <meta name="supported-color-schemes" content="light" />
    <title>Código de verificación</title>
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
              <td style="padding:28px 28px 8px;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;">
                <p style="margin:0 0 20px;color:#2a1c14;font-size:15px;line-height:1.5;">Tu código de verificación es:</p>
              </td>
            </tr>
            <tr>
              <td style="padding:0 28px;">
                <!-- Un solo bloque con letter-spacing, no celdas por dígito:
                probado en Gmail Android con modo oscuro, una tabla de 6
                <td> se colapsaba a un solo cuadro visible (bug real de
                renderizado). Esto sí se ve igual en todos los clientes.
                bgcolor (además del style) porque el modo oscuro de Gmail no
                siempre respeta bien el color-scheme/CSS inline por sí solo. -->
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
                  <tr>
                    <td align="center" style="background:#ffffff;border:1.5px solid #e8c9b4;border-radius:14px;padding:18px 12px;" bgcolor="#ffffff">
                      <span style="font-family:'Courier New',Courier,monospace;font-size:34px;font-weight:700;letter-spacing:10px;color:#7a2e1a;">${codigo}</span>
                    </td>
                  </tr>
                </table>
              </td>
            </tr>
            <tr>
              <td align="center" style="padding:14px 28px 4px;">
                <!-- No es un botón (un email no puede ejecutar JS para copiar
                al portapapeles) — es un aviso destacado del gesto real que
                sí funciona: mantener presionado. Que se vea distinto a un
                botón evita la falsa expectativa de que "hace algo" al tocarlo. -->
                <table role="presentation" cellpadding="0" cellspacing="0">
                  <tr>
                    <td style="background:#f6e9dc;border-radius:100px;padding:9px 18px;" bgcolor="#f6e9dc">
                      <span style="font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;color:#7a2e1a;font-size:13px;font-weight:700;">📋&nbsp; Mantén presionado el código para copiarlo</span>
                    </td>
                  </tr>
                </table>
              </td>
            </tr>
            <tr>
              <td style="padding:14px 28px 4px;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;">
                <p style="margin:0;color:#6b5849;font-size:13px;line-height:1.5;">Luego vuelve a la app y pégalo con el botón "Pegar" del campo de verificación.</p>
              </td>
            </tr>
            <tr>
              <td style="padding:14px 28px 28px;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;">
                <p style="margin:0 0 10px;color:#6b5849;font-size:13px;line-height:1.5;">Vence en ${MINUTOS_EXPIRACION} minutos. Nunca lo compartas con nadie, ni siquiera con alguien que diga ser de Panadería Ronceros.</p>
                <p style="margin:0;color:#9c8b7c;font-size:12px;line-height:1.5;">Si no solicitaste este código, ignora este correo — tu cuenta sigue segura.</p>
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

/** Alternativa en texto plano — la exige la especificación MIME (multipart/alternative) y mejora la entregabilidad; también es lo único que ven algunos lectores de pantalla y clientes de correo minimalistas. */
function mensajeEmailTexto(codigo) {
  return [
    'Panadería Ronceros',
    '',
    `Tu código de verificación es: ${codigo}`,
    '',
    `Vence en ${MINUTOS_EXPIRACION} minutos. Nunca lo compartas con nadie, ni siquiera con alguien que diga ser de Panadería Ronceros.`,
    '',
    'Si no solicitaste este código, ignora este correo — tu cuenta sigue segura.',
  ].join('\n');
}

/**
 * Genera, guarda y envía un código de 6 dígitos. Antes de crear uno nuevo:
 * - Respeta un cooldown de 60s desde el último código pedido para el mismo
 *   (idPersona, proposito), sin importar el destino — evita "bombardeo" de
 *   SMS/correos.
 * - Invalida (Usado=1) cualquier código anterior sin usar del mismo
 *   propósito, así solo el más reciente es válido.
 */
async function solicitarCodigo({ idPersona, canal, proposito, destino }) {
  const pool = await getPool();

  const ultimo = await pool
    .request()
    .input('IdPersona', sql.Int, idPersona)
    .input('Proposito', sql.VarChar(30), proposito)
    .query(`
      SELECT TOP 1 FechaCreacion FROM CodigosVerificacion
      WHERE IdPersona = @IdPersona AND Proposito = @Proposito
      ORDER BY FechaCreacion DESC
    `);

  if (ultimo.recordset.length > 0) {
    const segundosTranscurridos = (Date.now() - new Date(ultimo.recordset[0].FechaCreacion).getTime()) / 1000;
    if (segundosTranscurridos < SEGUNDOS_COOLDOWN) {
      throw new OtpError(
        'COOLDOWN',
        `Espera ${Math.ceil(SEGUNDOS_COOLDOWN - segundosTranscurridos)} segundos antes de pedir otro código.`,
      );
    }
  }

  await pool
    .request()
    .input('IdPersona', sql.Int, idPersona)
    .input('Proposito', sql.VarChar(30), proposito)
    .query(`
      UPDATE CodigosVerificacion SET Usado = 1
      WHERE IdPersona = @IdPersona AND Proposito = @Proposito AND Usado = 0
    `);

  const codigo = generarCodigo();
  const codigoHash = await bcrypt.hash(codigo, SALT_ROUNDS);
  const fechaExpiracion = new Date(Date.now() + MINUTOS_EXPIRACION * 60_000);

  await pool
    .request()
    .input('IdPersona', sql.Int, idPersona)
    .input('Canal', sql.VarChar(10), canal)
    .input('Proposito', sql.VarChar(30), proposito)
    .input('Destino', sql.VarChar(150), destino)
    .input('CodigoHash', sql.VarChar(255), codigoHash)
    .input('FechaExpiracion', sql.DateTime2, fechaExpiracion)
    .query(`
      INSERT INTO CodigosVerificacion (IdPersona, Canal, Proposito, Destino, CodigoHash, FechaExpiracion)
      VALUES (@IdPersona, @Canal, @Proposito, @Destino, @CodigoHash, @FechaExpiracion)
    `);

  if (canal === 'SMS') {
    await enviarSms(destino, mensajeSms(codigo));
  } else {
    await enviarEmail(destino, 'Tu código de verificación', mensajeEmailHtml(codigo), mensajeEmailTexto(codigo));
  }
}

/**
 * Verifica un código contra el más reciente sin usar para
 * (idPersona, proposito, destino). Nunca revela si el código "no existe"
 * vs "no coincide" — mismo mensaje genérico, para no filtrar información.
 *
 * `consumir: false` valida (y sigue contando intentos fallidos) SIN marcar
 * el código como usado — para poder confirmarlo de inmediato en la UI (ej.
 * el paso de autorización) sin gastarlo todavía, ya que ese mismo código se
 * vuelve a validar (y ahí sí se consume) más adelante en el flujo real
 * (ej. `exigirAutorizacionSiCorresponde`). Sin esto, validarlo dos veces
 * marcaría "usado" en la primera y la segunda (la que de verdad importa)
 * fallaría siempre.
 */
async function verificarCodigo({ idPersona, proposito, destino, codigo, consumir = true }) {
  const pool = await getPool();

  const resultado = await pool
    .request()
    .input('IdPersona', sql.Int, idPersona)
    .input('Proposito', sql.VarChar(30), proposito)
    .input('Destino', sql.VarChar(150), destino)
    .query(`
      SELECT TOP 1 IdCodigo, CodigoHash, Intentos, FechaExpiracion
      FROM CodigosVerificacion
      WHERE IdPersona = @IdPersona AND Proposito = @Proposito AND Destino = @Destino AND Usado = 0
      ORDER BY FechaCreacion DESC
    `);

  if (resultado.recordset.length === 0) {
    throw new OtpError('INVALIDO', 'Código inválido o ya expirado. Solicita uno nuevo.');
  }

  const { IdCodigo: idCodigo, CodigoHash: codigoHash, Intentos: intentos, FechaExpiracion: fechaExpiracion } =
    resultado.recordset[0];

  if (new Date(fechaExpiracion).getTime() < Date.now()) {
    throw new OtpError('EXPIRADO', 'El código expiró. Solicita uno nuevo.');
  }
  if (intentos >= MAX_INTENTOS) {
    await pool.request().input('IdCodigo', sql.Int, idCodigo).query('UPDATE CodigosVerificacion SET Usado = 1 WHERE IdCodigo = @IdCodigo');
    throw new OtpError('MAX_INTENTOS', 'Demasiados intentos fallidos. Solicita un código nuevo.');
  }

  const coincide = await bcrypt.compare(codigo, codigoHash);
  if (!coincide) {
    await pool.request().input('IdCodigo', sql.Int, idCodigo).query('UPDATE CodigosVerificacion SET Intentos = Intentos + 1 WHERE IdCodigo = @IdCodigo');
    throw new OtpError('INVALIDO', 'Código inválido o ya expirado. Solicita uno nuevo.');
  }

  if (consumir) {
    await pool.request().input('IdCodigo', sql.Int, idCodigo).query('UPDATE CodigosVerificacion SET Usado = 1 WHERE IdCodigo = @IdCodigo');
  }
}

module.exports = { solicitarCodigo, verificarCodigo, OtpError };
