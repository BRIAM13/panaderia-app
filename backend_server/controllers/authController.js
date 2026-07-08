const bcrypt = require('bcryptjs');
const { sql, getPool } = require('../config/db');
const {
  generateAccessToken,
  generateRefreshToken,
  verifyRefreshToken,
} = require('../utils/jwt');
const { registrarAuditoria } = require('../utils/auditLog');

const SALT_ROUNDS = Number(process.env.BCRYPT_SALT_ROUNDS) || 12;
const MAX_LOGIN_ATTEMPTS = Number(process.env.MAX_LOGIN_ATTEMPTS) || 5;
const ROL_CLIENTE_DEFAULT = 'CLIENTE';

/**
 * Roles y perfiles (Cliente/Trabajador) vigentes de una persona. Con esto
 * el frontend sabe si debe ofrecer la vista dual Cliente/Trabajador.
 */
async function obtenerPerfilPersona(pool, idPersona) {
  const personaResult = await pool
    .request()
    .input('IdPersona', sql.Int, idPersona)
    .query('SELECT Nombres, ApellidoPaterno, ApellidoMaterno FROM Personas WHERE IdPersona = @IdPersona');

  const rolesResult = await pool
    .request()
    .input('IdPersona', sql.Int, idPersona)
    .query(`
      SELECT DISTINCT r.NombreRol
      FROM PersonaRoles pr
      INNER JOIN Roles r ON r.IdRol = pr.IdRol
      WHERE pr.IdPersona = @IdPersona AND pr.Estado = 1
    `);

  const clienteResult = await pool
    .request()
    .input('IdPersona', sql.Int, idPersona)
    .query('SELECT IdCliente FROM Clientes WHERE IdPersona = @IdPersona AND Estado = 1');

  const trabajadorResult = await pool
    .request()
    .input('IdPersona', sql.Int, idPersona)
    .query('SELECT IdTrabajador, Cargo FROM Trabajadores WHERE IdPersona = @IdPersona AND Estado = 1');

  const esCliente = clienteResult.recordset.length > 0;
  const esTrabajador = trabajadorResult.recordset.length > 0;
  const persona = personaResult.recordset[0];

  return {
    nombres: persona?.Nombres ?? null,
    apellidoPaterno: persona?.ApellidoPaterno ?? null,
    apellidoMaterno: persona?.ApellidoMaterno ?? null,
    roles: rolesResult.recordset.map((r) => r.NombreRol),
    esCliente,
    esTrabajador,
    esHibrido: esCliente && esTrabajador,
    cargoTrabajador: esTrabajador ? trabajadorResult.recordset[0].Cargo : null,
  };
}

async function register(req, res, next) {
  const { dni, nombres, apellidoPaterno, apellidoMaterno, email, telefono, direccion, nombreUsuario, password } = req.body;
  const dniLimpio = dni.trim();
  const usuarioLimpio = nombreUsuario.trim();

  const pool = await getPool();
  const transaction = new sql.Transaction(pool);

  try {
    await transaction.begin();

    // ¿El nombre de usuario ya existe?
    const usuarioExistente = await new sql.Request(transaction)
      .input('NombreUsuario', sql.VarChar(50), usuarioLimpio)
      .query('SELECT IdUsuario FROM Usuarios WHERE NombreUsuario = @NombreUsuario');

    if (usuarioExistente.recordset.length > 0) {
      await transaction.rollback();
      return res.status(409).json({ mensaje: 'El nombre de usuario ya está en uso' });
    }

    // ¿Ya existe una Persona con este DNI? (evita duplicar datos personales / historial)
    const personaExistente = await new sql.Request(transaction)
      .input('DNI', sql.VarChar(15), dniLimpio)
      .query('SELECT IdPersona FROM Personas WHERE DNI = @DNI');

    let idPersona;

    if (personaExistente.recordset.length > 0) {
      idPersona = personaExistente.recordset[0].IdPersona;

      // Si esa persona ya tiene una cuenta de acceso, no se permite duplicar
      const cuentaExistente = await new sql.Request(transaction)
        .input('IdPersona', sql.Int, idPersona)
        .query('SELECT IdUsuario FROM Usuarios WHERE IdPersona = @IdPersona');

      if (cuentaExistente.recordset.length > 0) {
        await transaction.rollback();
        return res.status(409).json({ mensaje: 'Esta persona ya cuenta con un usuario registrado' });
      }
    } else {
      const nuevaPersona = await new sql.Request(transaction)
        .input('DNI', sql.VarChar(15), dniLimpio)
        .input('Nombres', sql.NVarChar(100), nombres.trim().toUpperCase())
        .input('ApellidoPaterno', sql.NVarChar(100), apellidoPaterno.trim().toUpperCase())
        .input('ApellidoMaterno', sql.NVarChar(100), apellidoMaterno ? apellidoMaterno.trim().toUpperCase() : null)
        .input('Email', sql.VarChar(150), email ? email.trim() : null)
        .input('Telefono', sql.VarChar(20), telefono ? telefono.trim() : null)
        .input('Direccion', sql.NVarChar(250), direccion ? direccion.trim().toUpperCase() : null)
        .query(`
          INSERT INTO Personas (DNI, Nombres, ApellidoPaterno, ApellidoMaterno, Email, Telefono, Direccion)
          OUTPUT INSERTED.IdPersona
          VALUES (@DNI, @Nombres, @ApellidoPaterno, @ApellidoMaterno, @Email, @Telefono, @Direccion)
        `);
      idPersona = nuevaPersona.recordset[0].IdPersona;
    }

    // Rol CLIENTE por defecto
    const rolResult = await new sql.Request(transaction)
      .input('NombreRol', sql.VarChar(50), ROL_CLIENTE_DEFAULT)
      .query('SELECT IdRol FROM Roles WHERE NombreRol = @NombreRol');
    const idRolCliente = rolResult.recordset[0].IdRol;

    // Perfil de Cliente (si no existe ya para esta persona)
    const clienteExistente = await new sql.Request(transaction)
      .input('IdPersona', sql.Int, idPersona)
      .query('SELECT IdCliente FROM Clientes WHERE IdPersona = @IdPersona');

    if (clienteExistente.recordset.length === 0) {
      await new sql.Request(transaction)
        .input('IdPersona', sql.Int, idPersona)
        .query('INSERT INTO Clientes (IdPersona) VALUES (@IdPersona)');

      await new sql.Request(transaction)
        .input('IdPersona', sql.Int, idPersona)
        .input('IdRol', sql.Int, idRolCliente)
        .query('INSERT INTO PersonaRoles (IdPersona, IdRol) VALUES (@IdPersona, @IdRol)');
    }

    // Cuenta de acceso (Usuario)
    const passwordHash = await bcrypt.hash(password, SALT_ROUNDS);
    const nuevoUsuario = await new sql.Request(transaction)
      .input('IdPersona', sql.Int, idPersona)
      .input('NombreUsuario', sql.VarChar(50), usuarioLimpio)
      .input('PasswordHash', sql.VarChar(255), passwordHash)
      .input('IdRol', sql.Int, idRolCliente)
      .query(`
        INSERT INTO Usuarios (IdPersona, NombreUsuario, PasswordHash, IdRol)
        OUTPUT INSERTED.IdUsuario
        VALUES (@IdPersona, @NombreUsuario, @PasswordHash, @IdRol)
      `);
    const idUsuario = nuevoUsuario.recordset[0].IdUsuario;

    await transaction.commit();

    await registrarAuditoria({
      idUsuario,
      accion: 'REGISTRO',
      tablaAfectada: 'Usuarios',
      registroAfectadoId: String(idUsuario),
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    return res.status(201).json({
      mensaje: 'Usuario registrado correctamente',
      usuario: { idUsuario, nombreUsuario: usuarioLimpio, rol: ROL_CLIENTE_DEFAULT },
    });
  } catch (err) {
    await transaction.rollback();
    return next(err);
  }
}

async function login(req, res, next) {
  const nombreUsuario = req.body.nombreUsuario.trim();
  const { password } = req.body;

  try {
    const pool = await getPool();

    const result = await pool
      .request()
      .input('NombreUsuario', sql.VarChar(50), nombreUsuario)
      .query(`
        SELECT u.IdUsuario, u.NombreUsuario, u.PasswordHash, u.Estado, u.Bloqueado,
               u.IntentosFallidos, u.IdPersona, u.RequiereCambioPassword, r.NombreRol
        FROM Usuarios u
        INNER JOIN Roles r ON r.IdRol = u.IdRol
        WHERE u.NombreUsuario = @NombreUsuario
      `);

    if (result.recordset.length === 0) {
      await registrarAuditoria({
        accion: 'LOGIN_FALLIDO',
        tablaAfectada: 'Usuarios',
        datosNuevos: { nombreUsuario },
        ip: req.ip,
        userAgent: req.headers['user-agent'],
      });
      return res.status(401).json({ mensaje: 'Credenciales inválidas' });
    }

    const usuario = result.recordset[0];

    if (!usuario.Estado) {
      return res.status(403).json({ mensaje: 'La cuenta está deshabilitada' });
    }

    if (usuario.Bloqueado) {
      return res.status(423).json({ mensaje: 'La cuenta está bloqueada por múltiples intentos fallidos. Contacte al administrador.' });
    }

    const passwordValido = await bcrypt.compare(password, usuario.PasswordHash);

    if (!passwordValido) {
      const intentos = usuario.IntentosFallidos + 1;
      const bloquear = intentos >= MAX_LOGIN_ATTEMPTS;

      await pool
        .request()
        .input('IdUsuario', sql.Int, usuario.IdUsuario)
        .input('IntentosFallidos', sql.Int, intentos)
        .input('Bloqueado', sql.Bit, bloquear)
        .input('FechaBloqueo', sql.DateTime2, bloquear ? new Date() : null)
        .query(`
          UPDATE Usuarios
          SET IntentosFallidos = @IntentosFallidos,
              Bloqueado = @Bloqueado,
              FechaBloqueo = @FechaBloqueo,
              FechaActualizacion = SYSUTCDATETIME()
          WHERE IdUsuario = @IdUsuario
        `);

      await registrarAuditoria({
        idUsuario: usuario.IdUsuario,
        accion: 'LOGIN_FALLIDO',
        tablaAfectada: 'Usuarios',
        registroAfectadoId: String(usuario.IdUsuario),
        ip: req.ip,
        userAgent: req.headers['user-agent'],
      });

      return res.status(401).json({ mensaje: 'Credenciales inválidas' });
    }

    // Login exitoso: resetear contador y actualizar último acceso
    await pool
      .request()
      .input('IdUsuario', sql.Int, usuario.IdUsuario)
      .query(`
        UPDATE Usuarios
        SET IntentosFallidos = 0,
            UltimoAcceso = SYSUTCDATETIME(),
            FechaActualizacion = SYSUTCDATETIME()
        WHERE IdUsuario = @IdUsuario
      `);

    const perfil = await obtenerPerfilPersona(pool, usuario.IdPersona);

    const payload = {
      idUsuario: usuario.IdUsuario,
      idPersona: usuario.IdPersona,
      nombreUsuario: usuario.NombreUsuario,
      rol: usuario.NombreRol,
    };

    const accessToken = generateAccessToken(payload);
    const refreshToken = generateRefreshToken(payload);

    const expiracionRefresh = new Date();
    expiracionRefresh.setDate(expiracionRefresh.getDate() + 7);

    await pool
      .request()
      .input('IdUsuario', sql.Int, usuario.IdUsuario)
      .input('RefreshToken', sql.VarChar(500), refreshToken)
      .input('FechaExpiracion', sql.DateTime2, expiracionRefresh)
      .input('IPOrigen', sql.VarChar(50), req.ip)
      .query(`
        INSERT INTO TokensSesion (IdUsuario, RefreshToken, FechaExpiracion, IPOrigen)
        VALUES (@IdUsuario, @RefreshToken, @FechaExpiracion, @IPOrigen)
      `);

    await registrarAuditoria({
      idUsuario: usuario.IdUsuario,
      accion: 'LOGIN',
      tablaAfectada: 'Usuarios',
      registroAfectadoId: String(usuario.IdUsuario),
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    return res.status(200).json({
      mensaje: 'Inicio de sesión exitoso',
      accessToken,
      refreshToken,
      usuario: {
        ...payload,
        requiereCambioPassword: Boolean(usuario.RequiereCambioPassword),
        ...perfil,
      },
    });
  } catch (err) {
    return next(err);
  }
}

/** Cambia la contraseña del usuario autenticado y limpia RequiereCambioPassword. */
/**
 * Cambio de contraseña obligatorio del primer ingreso (clave temporal =
 * DNI). No pide la contraseña actual: llegar hasta acá ya requirió
 * autenticarse con ella (verificarToken ya validó el JWT), y pedirla de
 * nuevo solo añade fricción sin ganancia real de seguridad en este flujo
 * — es distinto del cambio voluntario desde "Mi Perfil"
 * (`cambiarPasswordSeguro`), que sí exige autorizar por un canal ya
 * verificado porque ahí el riesgo es "alguien usando la sesión ya
 * abierta de otra persona".
 */
async function cambiarPassword(req, res, next) {
  const { passwordNueva } = req.body;
  const { idUsuario } = req.usuario;

  try {
    const pool = await getPool();

    const result = await pool
      .request()
      .input('IdUsuario', sql.Int, idUsuario)
      .query('SELECT PasswordHash FROM Usuarios WHERE IdUsuario = @IdUsuario');

    if (result.recordset.length === 0) {
      return res.status(404).json({ mensaje: 'Usuario no encontrado' });
    }

    const nuevoHash = await bcrypt.hash(passwordNueva, SALT_ROUNDS);

    await pool
      .request()
      .input('IdUsuario', sql.Int, idUsuario)
      .input('PasswordHash', sql.VarChar(255), nuevoHash)
      .query(`
        UPDATE Usuarios
        SET PasswordHash = @PasswordHash,
            RequiereCambioPassword = 0,
            FechaActualizacion = SYSUTCDATETIME()
        WHERE IdUsuario = @IdUsuario
      `);

    await registrarAuditoria({
      idUsuario,
      accion: 'CAMBIO_PASSWORD',
      tablaAfectada: 'Usuarios',
      registroAfectadoId: String(idUsuario),
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    return res.status(200).json({ mensaje: 'Contraseña actualizada correctamente' });
  } catch (err) {
    return next(err);
  }
}

/** Devuelve el perfil vigente (roles, vista dual) del usuario autenticado. */
async function obtenerPerfil(req, res, next) {
  const { idUsuario, idPersona } = req.usuario;

  try {
    const pool = await getPool();

    const result = await pool
      .request()
      .input('IdUsuario', sql.Int, idUsuario)
      .query(`
        SELECT u.IdUsuario, u.NombreUsuario, u.IdPersona, u.RequiereCambioPassword,
               u.Estado, r.NombreRol
        FROM Usuarios u
        INNER JOIN Roles r ON r.IdRol = u.IdRol
        WHERE u.IdUsuario = @IdUsuario
      `);

    if (result.recordset.length === 0 || !result.recordset[0].Estado) {
      return res.status(404).json({ mensaje: 'Usuario no encontrado o deshabilitado' });
    }

    const usuario = result.recordset[0];
    const perfil = await obtenerPerfilPersona(pool, idPersona);

    return res.status(200).json({
      usuario: {
        idUsuario: usuario.IdUsuario,
        idPersona: usuario.IdPersona,
        nombreUsuario: usuario.NombreUsuario,
        rol: usuario.NombreRol,
        requiereCambioPassword: Boolean(usuario.RequiereCambioPassword),
        ...perfil,
      },
    });
  } catch (err) {
    return next(err);
  }
}

/** Emite un nuevo accessToken a partir de un refreshToken vigente y no revocado. */
async function refrescarToken(req, res, next) {
  const { refreshToken } = req.body;

  try {
    let payload;
    try {
      payload = verifyRefreshToken(refreshToken);
    } catch (err) {
      return res.status(401).json({ mensaje: 'Refresh token inválido o expirado' });
    }

    const pool = await getPool();

    const sesion = await pool
      .request()
      .input('IdUsuario', sql.Int, payload.idUsuario)
      .input('RefreshToken', sql.VarChar(500), refreshToken)
      .query(`
        SELECT TOP 1 IdToken
        FROM TokensSesion
        WHERE IdUsuario = @IdUsuario
          AND RefreshToken = @RefreshToken
          AND Revocado = 0
          AND FechaExpiracion > SYSUTCDATETIME()
      `);

    if (sesion.recordset.length === 0) {
      return res.status(401).json({ mensaje: 'La sesión ya no es válida, inicia sesión nuevamente' });
    }

    const usuarioResult = await pool
      .request()
      .input('IdUsuario', sql.Int, payload.idUsuario)
      .query(`
        SELECT u.IdUsuario, u.NombreUsuario, u.IdPersona, u.Estado, r.NombreRol
        FROM Usuarios u
        INNER JOIN Roles r ON r.IdRol = u.IdRol
        WHERE u.IdUsuario = @IdUsuario
      `);

    if (usuarioResult.recordset.length === 0 || !usuarioResult.recordset[0].Estado) {
      return res.status(401).json({ mensaje: 'Usuario no encontrado o deshabilitado' });
    }

    const usuario = usuarioResult.recordset[0];

    // El refresh token también trae el rol que tenía el usuario al momento
    // del login/último refresh (mismo payload que el access token). Si ya
    // no coincide con el rol actual en la base de datos, NO se renueva en
    // silencio — eso le daría un access token nuevo con el rol correcto
    // pero dejaría la app (armada en memoria con las pantallas del rol
    // viejo) sin enterarse del cambio. Esta es la comprobación que de
    // verdad importa: authMiddleware ya hace una comprobación parecida,
    // pero solo alcanza a dispararse si el access token todavía no había
    // vencido por tiempo — en la práctica, casi siempre se llega primero
    // acá (al vencer y pedir uno nuevo), así que el chequeo real tiene que
    // vivir en este endpoint para cubrir ambos casos sin depender de cuál
    // ocurra primero.
    if (usuario.NombreRol !== payload.rol) {
      return res.status(401).json({
        mensaje:
          'Tu cuenta fue actualizada con nuevos permisos. Vuelve a iniciar sesión para continuar.',
        tipo: 'ROL_CAMBIADO',
      });
    }

    const nuevoAccessToken = generateAccessToken({
      idUsuario: usuario.IdUsuario,
      idPersona: usuario.IdPersona,
      nombreUsuario: usuario.NombreUsuario,
      rol: usuario.NombreRol,
    });

    return res.status(200).json({ accessToken: nuevoAccessToken });
  } catch (err) {
    return next(err);
  }
}

module.exports = { register, login, cambiarPassword, obtenerPerfil, refrescarToken };
