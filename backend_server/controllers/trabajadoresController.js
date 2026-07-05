const bcrypt = require('bcryptjs');
const { sql, getPool } = require('../config/db');
const { registrarAuditoria } = require('../utils/auditLog');
const { obtenerIdTrabajador, tieneAccesoATienda } = require('../utils/tiendaAcceso');

const SALT_ROUNDS = Number(process.env.BCRYPT_SALT_ROUNDS) || 12;

function mayuscula(valor) {
  return valor ? valor.trim().toUpperCase() : valor;
}

/** ADMIN solo puede asignar TRABAJADOR; SUPERADMIN puede asignar cualquiera
 * de los 3 roles de personal. CLIENTE nunca se asigna por esta vía. */
function rolesQuePuedeAsignar(rolDelQueLlama) {
  return rolDelQueLlama === 'SUPERADMIN' ? ['TRABAJADOR', 'ADMIN', 'SUPERADMIN'] : ['TRABAJADOR'];
}

/** Un ADMIN puede VER (aunque no necesariamente asignar) hasta su propio
 * nivel — TRABAJADOR y ADMIN — pero nunca a un SUPERADMIN; eso queda fuera
 * de su alcance por completo. SUPERADMIN ve a todos. */
function rolesQuePuedeVer(rolDelQueLlama) {
  return rolDelQueLlama === 'SUPERADMIN' ? ['TRABAJADOR', 'ADMIN', 'SUPERADMIN'] : ['TRABAJADOR', 'ADMIN'];
}

/**
 * Busca una Persona por DNI en NUESTRA base (nunca RENIEC — eso lo sigue
 * haciendo el frontend contra /external/dni/:dni, igual que en Clientes).
 * Si ya es trabajador, incluye sus tiendas asignadas para que el admin que
 * está registrando sepa que esta persona ya trabaja en otro lado.
 */
async function buscarPorDni(req, res, next) {
  const { dni } = req.params;
  const dniLimpio = String(dni || '').trim();

  if (!/^\d{8}$/.test(dniLimpio)) {
    return res.status(400).json({ mensaje: 'DNI inválido: debe tener 8 dígitos' });
  }

  try {
    const pool = await getPool();
    const result = await pool
      .request()
      .input('DNI', sql.VarChar(15), dniLimpio)
      .query(`
        SELECT p.IdPersona, p.Nombres, p.ApellidoPaterno, p.ApellidoMaterno, p.Telefono, p.Email,
               p.Direccion, p.OrigenValidacion,
               trab.IdTrabajador, trab.Cargo, trab.Salario,
               CASE WHEN EXISTS (SELECT 1 FROM Clientes c WHERE c.IdPersona = p.IdPersona AND c.Estado = 1) THEN 1 ELSE 0 END AS EsCliente
        FROM Personas p
        LEFT JOIN Trabajadores trab ON trab.IdPersona = p.IdPersona AND trab.Estado = 1
        WHERE p.DNI = @DNI
      `);

    if (result.recordset.length === 0) {
      return res.status(200).json({ existeEnBd: false });
    }

    const fila = result.recordset[0];
    let tiendasAsignadas = [];
    if (fila.IdTrabajador) {
      const tiendas = await pool
        .request()
        .input('IdTrabajador', sql.Int, fila.IdTrabajador)
        .query(`
          SELECT t.IdTienda, t.Nombre, tt.Estado
          FROM TrabajadorTiendas tt
          INNER JOIN Tiendas t ON t.IdTienda = tt.IdTienda
          WHERE tt.IdTrabajador = @IdTrabajador
        `);
      tiendasAsignadas = tiendas.recordset.map((f) => ({
        idTienda: f.IdTienda,
        nombre: f.Nombre,
        activo: Boolean(f.Estado),
      }));
    }

    return res.status(200).json({
      existeEnBd: true,
      idPersona: fila.IdPersona,
      nombres: fila.Nombres,
      apellidoPaterno: fila.ApellidoPaterno,
      apellidoMaterno: fila.ApellidoMaterno,
      telefono: fila.Telefono,
      email: fila.Email,
      direccion: fila.Direccion,
      origenValidacion: fila.OrigenValidacion,
      esCliente: Boolean(fila.EsCliente),
      yaEsTrabajador: Boolean(fila.IdTrabajador),
      idTrabajador: fila.IdTrabajador || null,
      cargo: fila.Cargo || null,
      tiendasAsignadas,
    });
  } catch (err) {
    return next(err);
  }
}

/**
 * Registra un trabajador nuevo, o —si el DNI ya pertenece a una Persona
 * existente (cliente y/o trabajador en otra tienda)— reutiliza esa misma
 * Persona/Trabajador y solo agrega el acceso a las tiendas indicadas. Nunca
 * duplica ni borra el perfil de Cliente existente.
 */
async function crearTrabajador(req, res, next) {
  const {
    dni,
    nombres,
    apellidoPaterno,
    apellidoMaterno,
    telefono,
    email,
    direccion,
    rol,
    salario,
    origenValidacion,
    tiendas,
  } = req.body;
  const dniLimpio = String(dni).trim();

  // El rol a asignar debe ser uno de los que el que llama puede otorgar —
  // un ADMIN nunca puede crear otro ADMIN/SUPERADMIN, eso es exclusivo de
  // SUPERADMIN.
  if (!rolesQuePuedeAsignar(req.usuario.rol).includes(rol)) {
    return res.status(403).json({ mensaje: 'No tienes permiso para asignar ese rol.' });
  }

  const pool = await getPool();
  const transaction = new sql.Transaction(pool);

  try {
    // El admin solo puede asignar tiendas que él mismo administra —
    // SUPERADMIN no tiene esta restricción.
    for (const idTienda of tiendas) {
      const acceso = await tieneAccesoATienda({
        rol: req.usuario.rol,
        idPersona: req.usuario.idPersona,
        idTienda,
      });
      if (!acceso) {
        return res.status(403).json({ mensaje: 'No puedes asignar una tienda que no administras' });
      }
    }

    await transaction.begin();

    const existente = await new sql.Request(transaction)
      .input('DNI', sql.VarChar(15), dniLimpio)
      .query('SELECT IdPersona FROM Personas WHERE DNI = @DNI');

    let idPersona;
    if (existente.recordset.length > 0) {
      idPersona = existente.recordset[0].IdPersona;

      // Nadie puede registrarse a sí mismo como trabajador — no tiene
      // sentido (ya tiene su propia cuenta y acceso) y puede dejar estados
      // raros, como crearse una ficha de Trabajador/Cliente redundante.
      if (idPersona === req.usuario.idPersona) {
        await transaction.rollback();
        return res.status(400).json({ mensaje: 'No puedes registrarte a ti mismo como trabajador.' });
      }
    } else {
      const nuevaPersona = await new sql.Request(transaction)
        .input('DNI', sql.VarChar(15), dniLimpio)
        .input('Nombres', sql.NVarChar(100), mayuscula(nombres))
        .input('ApellidoPaterno', sql.NVarChar(100), mayuscula(apellidoPaterno))
        .input('ApellidoMaterno', sql.NVarChar(100), mayuscula(apellidoMaterno))
        .input('Telefono', sql.VarChar(20), telefono ? telefono.trim() : null)
        .input('Email', sql.VarChar(150), email ? email.trim() : null)
        .input('Direccion', sql.NVarChar(250), mayuscula(direccion))
        .input('OrigenValidacion', sql.VarChar(20), origenValidacion === 'RENIEC' ? 'RENIEC' : 'MANUAL')
        .query(`
          INSERT INTO Personas (DNI, Nombres, ApellidoPaterno, ApellidoMaterno, Telefono, Email, Direccion, OrigenValidacion)
          OUTPUT INSERTED.IdPersona
          VALUES (@DNI, @Nombres, @ApellidoPaterno, @ApellidoMaterno, @Telefono, @Email, @Direccion, @OrigenValidacion)
        `);
      idPersona = nuevaPersona.recordset[0].IdPersona;
    }

    // Todo trabajador (sea cual sea su rol) también queda registrado como
    // cliente si todavía no lo era — ya se verificó su DNI y sus datos
    // están completos para esto, no tiene sentido pedírselos de nuevo más
    // adelante. Nunca duplica: si ya era cliente, no se toca nada.
    const clienteExistente = await new sql.Request(transaction)
      .input('IdPersona', sql.Int, idPersona)
      .query('SELECT IdCliente FROM Clientes WHERE IdPersona = @IdPersona');

    if (clienteExistente.recordset.length === 0) {
      await new sql.Request(transaction).input('IdPersona', sql.Int, idPersona).query('INSERT INTO Clientes (IdPersona) VALUES (@IdPersona)');

      const rolClienteResult = await new sql.Request(transaction).query("SELECT IdRol FROM Roles WHERE NombreRol = 'CLIENTE'");
      const idRolCliente = rolClienteResult.recordset[0].IdRol;
      await new sql.Request(transaction)
        .input('IdPersona', sql.Int, idPersona)
        .input('IdRol', sql.Int, idRolCliente)
        .query('INSERT INTO PersonaRoles (IdPersona, IdRol) VALUES (@IdPersona, @IdRol)');
    }

    const trabajadorExistente = await new sql.Request(transaction)
      .input('IdPersona', sql.Int, idPersona)
      .query('SELECT IdTrabajador FROM Trabajadores WHERE IdPersona = @IdPersona');

    let idTrabajador;
    if (trabajadorExistente.recordset.length > 0) {
      idTrabajador = trabajadorExistente.recordset[0].IdTrabajador;
      // Ya era trabajador (ej. de otra tienda): reactivar por si estaba
      // cesado, sin tocar su Cargo/Salario originales.
      await new sql.Request(transaction)
        .input('IdTrabajador', sql.Int, idTrabajador)
        .query('UPDATE Trabajadores SET Estado = 1, FechaCese = NULL WHERE IdTrabajador = @IdTrabajador');
    } else {
      const nuevoTrabajador = await new sql.Request(transaction)
        .input('IdPersona', sql.Int, idPersona)
        .input('Cargo', sql.NVarChar(100), rol)
        .input('Salario', sql.Decimal(10, 2), salario ?? null)
        .query(`
          INSERT INTO Trabajadores (IdPersona, Cargo, Salario)
          OUTPUT INSERTED.IdTrabajador
          VALUES (@IdPersona, @Cargo, @Salario)
        `);
      idTrabajador = nuevoTrabajador.recordset[0].IdTrabajador;
    }

    for (const idTienda of tiendas) {
      const yaAsignado = await new sql.Request(transaction)
        .input('IdTrabajador', sql.Int, idTrabajador)
        .input('IdTienda', sql.Int, idTienda)
        .query('SELECT 1 FROM TrabajadorTiendas WHERE IdTrabajador = @IdTrabajador AND IdTienda = @IdTienda');

      if (yaAsignado.recordset.length > 0) {
        await new sql.Request(transaction)
          .input('IdTrabajador', sql.Int, idTrabajador)
          .input('IdTienda', sql.Int, idTienda)
          .query(`
            UPDATE TrabajadorTiendas SET Estado = 1, FechaRevocacion = NULL
            WHERE IdTrabajador = @IdTrabajador AND IdTienda = @IdTienda
          `);
      } else {
        await new sql.Request(transaction)
          .input('IdTrabajador', sql.Int, idTrabajador)
          .input('IdTienda', sql.Int, idTienda)
          .query('INSERT INTO TrabajadorTiendas (IdTrabajador, IdTienda) VALUES (@IdTrabajador, @IdTienda)');
      }
    }

    const rolResult = await new sql.Request(transaction)
      .input('NombreRol', sql.VarChar(50), rol)
      .query('SELECT IdRol FROM Roles WHERE NombreRol = @NombreRol');
    const idRolAsignado = rolResult.recordset[0].IdRol;

    // Si la persona todavía no tiene cuenta de acceso, se le crea una con el
    // rol elegido (DNI como usuario y clave inicial, forzando cambio en el
    // primer login) — mismo patrón que la clonación de Clientes. Si YA
    // tenía cuenta (ej. ya era cliente, o trabajador de otra tienda con un
    // rol menor), se actualiza su rol de acceso al recién asignado — así
    // su próximo inicio de sesión refleja el nuevo permiso, sin duplicar
    // su cuenta ni perder su historial de cliente.
    let cuentaCreada = false;
    const cuentaExistente = await new sql.Request(transaction)
      .input('IdPersona', sql.Int, idPersona)
      .query('SELECT IdUsuario FROM Usuarios WHERE IdPersona = @IdPersona');

    if (cuentaExistente.recordset.length === 0) {
      const usuarioTomado = await new sql.Request(transaction)
        .input('NombreUsuario', sql.VarChar(50), dniLimpio)
        .query('SELECT IdUsuario FROM Usuarios WHERE NombreUsuario = @NombreUsuario');

      if (usuarioTomado.recordset.length === 0) {
        const passwordHash = await bcrypt.hash(dniLimpio, SALT_ROUNDS);

        await new sql.Request(transaction)
          .input('IdPersona', sql.Int, idPersona)
          .input('NombreUsuario', sql.VarChar(50), dniLimpio)
          .input('PasswordHash', sql.VarChar(255), passwordHash)
          .input('IdRol', sql.Int, idRolAsignado)
          .query(`
            INSERT INTO Usuarios (IdPersona, NombreUsuario, PasswordHash, IdRol, RequiereCambioPassword)
            VALUES (@IdPersona, @NombreUsuario, @PasswordHash, @IdRol, 1)
          `);
        cuentaCreada = true;
      }
    } else {
      await new sql.Request(transaction)
        .input('IdUsuario', sql.Int, cuentaExistente.recordset[0].IdUsuario)
        .input('IdRol', sql.Int, idRolAsignado)
        .query('UPDATE Usuarios SET IdRol = @IdRol WHERE IdUsuario = @IdUsuario');
    }

    await transaction.commit();

    await registrarAuditoria({
      idUsuario: req.usuario.idUsuario,
      accion: 'CREAR_TRABAJADOR',
      tablaAfectada: 'Trabajadores',
      registroAfectadoId: String(idTrabajador),
      datosNuevos: { dni: dniLimpio, rol, tiendas, cuentaCreada },
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    return res.status(201).json({ mensaje: 'Trabajador registrado correctamente', idTrabajador, cuentaCreada });
  } catch (err) {
    await transaction.rollback();
    return next(err);
  }
}

/**
 * Pool de trabajadores (para que un admin de otra tienda pueda encontrar a
 * alguien ya registrado y decidir si le da acceso a la suya). Un ADMIN
 * solo ve hasta su propio nivel (TRABAJADOR/ADMIN, nunca SUPERADMIN) —
 * SUPERADMIN ve a todos. En ambos casos, el propio usuario que hace la
 * consulta NUNCA aparece en su propia lista: otorgarse/quitarse acceso a
 * sí mismo no tiene sentido y ya causó un bug real (un admin se quitó el
 * acceso a su propia tienda sin querer).
 */
async function listarTrabajadores(req, res, next) {
  try {
    const pool = await getPool();
    const rolesVisibles = rolesQuePuedeVer(req.usuario.rol);
    const result = await pool
      .request()
      .input('IdPersonaQueConsulta', sql.Int, req.usuario.idPersona)
      .query(`
        SELECT trab.IdTrabajador, trab.Cargo, trab.Estado AS TrabajadorActivo,
               p.IdPersona, p.DNI, p.Nombres, p.ApellidoPaterno, p.ApellidoMaterno, p.Telefono, p.Email,
               r.NombreRol
        FROM Trabajadores trab
        INNER JOIN Personas p ON p.IdPersona = trab.IdPersona
        LEFT JOIN Usuarios u ON u.IdPersona = p.IdPersona
        LEFT JOIN Roles r ON r.IdRol = u.IdRol
        WHERE p.IdPersona <> @IdPersonaQueConsulta
          AND (r.NombreRol IS NULL OR r.NombreRol IN ('${rolesVisibles.join("','")}'))
        ORDER BY p.Nombres, p.ApellidoPaterno
      `);

    const trabajadores = await Promise.all(
      result.recordset.map(async (fila) => {
        const tiendas = await pool
          .request()
          .input('IdTrabajador', sql.Int, fila.IdTrabajador)
          .query(`
            SELECT t.IdTienda, t.Nombre, tt.Estado
            FROM TrabajadorTiendas tt
            INNER JOIN Tiendas t ON t.IdTienda = tt.IdTienda
            WHERE tt.IdTrabajador = @IdTrabajador
          `);
        return {
          idTrabajador: fila.IdTrabajador,
          idPersona: fila.IdPersona,
          dni: fila.DNI,
          nombres: fila.Nombres,
          apellidoPaterno: fila.ApellidoPaterno,
          apellidoMaterno: fila.ApellidoMaterno,
          telefono: fila.Telefono,
          email: fila.Email,
          cargo: fila.Cargo,
          rol: fila.NombreRol,
          activo: Boolean(fila.TrabajadorActivo),
          tiendas: tiendas.recordset.map((t) => ({
            idTienda: t.IdTienda,
            nombre: t.Nombre,
            activo: Boolean(t.Estado),
          })),
        };
      }),
    );

    return res.status(200).json({ trabajadores });
  } catch (err) {
    return next(err);
  }
}

/**
 * Cambia el rol de acceso de un trabajador ya existente (ej. ascenderlo de
 * TRABAJADOR a ADMIN) — mismo candado que crearTrabajador: un ADMIN solo
 * puede dejarlo en TRABAJADOR, nunca ascenderlo a ADMIN/SUPERADMIN; eso es
 * exclusivo de SUPERADMIN.
 */
async function cambiarRolTrabajador(req, res, next) {
  const { id } = req.params;
  const { rol } = req.body;

  if (!rolesQuePuedeAsignar(req.usuario.rol).includes(rol)) {
    return res.status(403).json({ mensaje: 'No tienes permiso para asignar ese rol.' });
  }

  try {
    if (await esUnoMismo(req, id)) {
      return res.status(400).json({ mensaje: 'No puedes cambiar tu propio rol.' });
    }

    const pool = await getPool();
    const trabajador = await pool
      .request()
      .input('IdTrabajador', sql.Int, id)
      .query('SELECT IdPersona FROM Trabajadores WHERE IdTrabajador = @IdTrabajador');
    if (trabajador.recordset.length === 0) {
      return res.status(404).json({ mensaje: 'Trabajador no encontrado' });
    }
    const { IdPersona: idPersona } = trabajador.recordset[0];

    const usuario = await pool
      .request()
      .input('IdPersona', sql.Int, idPersona)
      .query('SELECT IdUsuario FROM Usuarios WHERE IdPersona = @IdPersona');
    if (usuario.recordset.length === 0) {
      return res.status(404).json({ mensaje: 'Esta persona todavía no tiene una cuenta de acceso.' });
    }

    const rolResult = await pool.request().input('NombreRol', sql.VarChar(50), rol).query('SELECT IdRol FROM Roles WHERE NombreRol = @NombreRol');
    const idRolAsignado = rolResult.recordset[0].IdRol;

    await pool
      .request()
      .input('IdUsuario', sql.Int, usuario.recordset[0].IdUsuario)
      .input('IdRol', sql.Int, idRolAsignado)
      .query('UPDATE Usuarios SET IdRol = @IdRol WHERE IdUsuario = @IdUsuario');

    await pool.request().input('IdTrabajador', sql.Int, id).input('Cargo', sql.NVarChar(100), rol).query('UPDATE Trabajadores SET Cargo = @Cargo WHERE IdTrabajador = @IdTrabajador');

    await registrarAuditoria({
      idUsuario: req.usuario.idUsuario,
      accion: 'CAMBIAR_ROL_TRABAJADOR',
      tablaAfectada: 'Usuarios',
      registroAfectadoId: String(usuario.recordset[0].IdUsuario),
      datosNuevos: { rol },
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    return res.status(200).json({ mensaje: 'Rol actualizado correctamente' });
  } catch (err) {
    return next(err);
  }
}

/** true si el :id de la URL (IdTrabajador) corresponde a la misma persona
 * que está autenticada — nadie puede otorgarse/quitarse su propio acceso
 * ni cambiarse su propio rol (evita un auto-bloqueo accidental, como
 * ocurrió una vez: un admin se quitó el acceso a su propia tienda). */
async function esUnoMismo(req, idTrabajador) {
  const pool = await getPool();
  const result = await pool
    .request()
    .input('IdTrabajador', sql.Int, idTrabajador)
    .query('SELECT IdPersona FROM Trabajadores WHERE IdTrabajador = @IdTrabajador');
  return result.recordset[0]?.IdPersona === req.usuario.idPersona;
}

/** Otorga (o reactiva) el acceso de un trabajador a la tienda del :idTienda
 * de la URL — el middleware autorizarTienda ya garantiza que el que llama
 * administra esa tienda. */
async function otorgarAccesoTienda(req, res, next) {
  const { id, idTienda } = req.params;

  try {
    if (await esUnoMismo(req, id)) {
      return res.status(400).json({ mensaje: 'No puedes modificar tu propio acceso a una tienda.' });
    }

    const pool = await getPool();
    const yaAsignado = await pool
      .request()
      .input('IdTrabajador', sql.Int, id)
      .input('IdTienda', sql.Int, idTienda)
      .query('SELECT 1 FROM TrabajadorTiendas WHERE IdTrabajador = @IdTrabajador AND IdTienda = @IdTienda');

    if (yaAsignado.recordset.length > 0) {
      await pool
        .request()
        .input('IdTrabajador', sql.Int, id)
        .input('IdTienda', sql.Int, idTienda)
        .query('UPDATE TrabajadorTiendas SET Estado = 1, FechaRevocacion = NULL WHERE IdTrabajador = @IdTrabajador AND IdTienda = @IdTienda');
    } else {
      await pool
        .request()
        .input('IdTrabajador', sql.Int, id)
        .input('IdTienda', sql.Int, idTienda)
        .query('INSERT INTO TrabajadorTiendas (IdTrabajador, IdTienda) VALUES (@IdTrabajador, @IdTienda)');
    }

    await registrarAuditoria({
      idUsuario: req.usuario.idUsuario,
      accion: 'OTORGAR_ACCESO_TIENDA',
      tablaAfectada: 'TrabajadorTiendas',
      registroAfectadoId: `${id}-${idTienda}`,
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    return res.status(200).json({ mensaje: 'Acceso otorgado correctamente' });
  } catch (err) {
    return next(err);
  }
}

async function revocarAccesoTienda(req, res, next) {
  const { id, idTienda } = req.params;

  try {
    if (await esUnoMismo(req, id)) {
      return res.status(400).json({ mensaje: 'No puedes modificar tu propio acceso a una tienda.' });
    }

    const pool = await getPool();
    await pool
      .request()
      .input('IdTrabajador', sql.Int, id)
      .input('IdTienda', sql.Int, idTienda)
      .query(`
        UPDATE TrabajadorTiendas SET Estado = 0, FechaRevocacion = SYSUTCDATETIME()
        WHERE IdTrabajador = @IdTrabajador AND IdTienda = @IdTienda
      `);

    await registrarAuditoria({
      idUsuario: req.usuario.idUsuario,
      accion: 'REVOCAR_ACCESO_TIENDA',
      tablaAfectada: 'TrabajadorTiendas',
      registroAfectadoId: `${id}-${idTienda}`,
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    return res.status(200).json({ mensaje: 'Acceso revocado correctamente' });
  } catch (err) {
    return next(err);
  }
}

module.exports = {
  buscarPorDni,
  crearTrabajador,
  listarTrabajadores,
  cambiarRolTrabajador,
  otorgarAccesoTienda,
  revocarAccesoTienda,
};
