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
  return `Corporación Ronceros: tu código de verificación es ${codigo}. Vence en ${MINUTOS_EXPIRACION} minutos. Nunca lo compartas con nadie.`;
}

function mensajeEmailHtml(codigo) {
  // El bloque del código es texto plano seleccionable (no imagen): en Gmail
  // y la mayoría de clientes basta con mantener presionado para copiarlo,
  // que es el gesto que complementa al botón "Pegar" dentro de la app.
  return `
    <div style="font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;max-width:420px;margin:0 auto;background:#fff8f3;border-radius:20px;overflow:hidden;border:1px solid #f0ded0;">
      <div style="background:#7a2e1a;padding:20px 24px;">
        <span style="color:#fff;font-size:15px;font-weight:700;letter-spacing:0.3px;">Corporación Ronceros</span>
      </div>
      <div style="padding:28px 24px;">
        <p style="margin:0 0 18px;color:#2a1c14;font-size:15px;line-height:1.5;">Tu código de verificación es:</p>
        <div style="background:#ffffff;border:1.5px solid #e8c9b4;border-radius:14px;padding:18px 12px;text-align:center;margin-bottom:18px;">
          <span style="font-family:'Courier New',monospace;font-size:34px;font-weight:700;letter-spacing:10px;color:#7a2e1a;">${codigo}</span>
        </div>
        <p style="margin:0 0 6px;color:#6b5849;font-size:13px;line-height:1.5;">Vence en ${MINUTOS_EXPIRACION} minutos. Nunca lo compartas con nadie, ni siquiera con alguien que diga ser de Corporación Ronceros.</p>
        <p style="margin:16px 0 0;color:#9c8b7c;font-size:12px;">Si no solicitaste este código, ignora este correo.</p>
      </div>
    </div>
  `;
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
    await enviarEmail(destino, 'Tu código de verificación', mensajeEmailHtml(codigo));
  }
}

/**
 * Verifica un código contra el más reciente sin usar para
 * (idPersona, proposito, destino). Nunca revela si el código "no existe"
 * vs "no coincide" — mismo mensaje genérico, para no filtrar información.
 */
async function verificarCodigo({ idPersona, proposito, destino, codigo }) {
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

  await pool.request().input('IdCodigo', sql.Int, idCodigo).query('UPDATE CodigosVerificacion SET Usado = 1 WHERE IdCodigo = @IdCodigo');
}

module.exports = { solicitarCodigo, verificarCodigo, OtpError };
