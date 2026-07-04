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
  return `
    <p>Tu código de verificación de Corporación Ronceros es:</p>
    <p style="font-size:28px;font-weight:700;letter-spacing:4px;">${codigo}</p>
    <p>Vence en ${MINUTOS_EXPIRACION} minutos. Nunca lo compartas con nadie.</p>
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
