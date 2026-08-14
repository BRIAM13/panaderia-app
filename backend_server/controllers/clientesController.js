const bcrypt = require('bcryptjs');
const { sql, getPool } = require('../config/db');
const { registrarAuditoria } = require('../utils/auditLog');
const { solicitarCodigo, verificarCodigo, OtpError } = require('../services/otpService');

const SALT_ROUNDS = Number(process.env.BCRYPT_SALT_ROUNDS) || 12;

function calcularCalidadDato(dni, origenValidacion) {
  if (!dni) return 'SIN_DNI';
  return origenValidacion === 'RENIEC' ? 'RENIEC' : 'MANUAL';
}

/**
 * RUC que empieza con '20' es Persona Jurídica (empresa): por definición no
 * tiene apellidos. Se fuerza server-side (no solo en el formulario) para que
 * ningún cliente llegue a guardar apellidos "fantasma" en una empresa.
 */
function esRucPersonaJuridica(dni) {
  return typeof dni === 'string' && /^20\d{9}$/.test(dni);
}

/**
 * Todo dato de texto libre (nombres, apellidos, dirección, descripción de
 * negocio) se guarda en mayúsculas — nunca a mitad de camino confiando solo
 * en el formatter del teclado del cliente: el backend es la garantía final,
 * igual que ya pasa con el trim(). Email y teléfono NO pasan por aquí.
 */
function mayuscula(valor) {
  return valor ? valor.trim().toUpperCase() : valor;
}

function mapearCliente(fila) {
  return {
    idCliente: fila.IdCliente,
    idPersona: fila.IdPersona,
    dni: fila.DNI,
    nombres: fila.Nombres,
    apellidoPaterno: fila.ApellidoPaterno,
    apellidoMaterno: fila.ApellidoMaterno,
    telefono: fila.Telefono,
    email: fila.Email,
    direccion: fila.Direccion,
    descripcionNegocio: fila.DescripcionNegocio,
    nombreComercialOficial: Boolean(fila.NombreComercialOficial),
    origenValidacion: fila.OrigenValidacion,
    calidadDato: calcularCalidadDato(fila.DNI, fila.OrigenValidacion),
    puntosFidelidad: fila.PuntosFidelidad,
    activo: fila.Estado === undefined ? true : Boolean(fila.Estado),
    telefonoVerificado: Boolean(fila.TelefonoVerificado),
    emailVerificado: Boolean(fila.EmailVerificado),
  };
}

/**
 * Clonación automática: si un cliente fue verificado con datos reales de
 * apiperu.dev (no simulados, no manuales), se le crea una cuenta de acceso
 * (rol CLIENTE) usando su DNI como usuario y contraseña inicial, forzando
 * el cambio de clave en el primer login. Si ya tiene cuenta, o si el DNI ya
 * está tomado como nombre de usuario por otra persona, no hace nada (no
 * revienta la creación/edición del cliente).
 */
async function intentarClonarUsuarioCliente(transaction, idPersona, identificador) {
  const yaTieneCuenta = await new sql.Request(transaction)
    .input('IdPersona', sql.Int, idPersona)
    .query('SELECT IdUsuario FROM Usuarios WHERE IdPersona = @IdPersona');
  if (yaTieneCuenta.recordset.length > 0) {
    return { creado: false, motivo: 'La persona ya tiene una cuenta de acceso' };
  }

  const usuarioTomado = await new sql.Request(transaction)
    .input('NombreUsuario', sql.VarChar(50), identificador)
    .query('SELECT IdUsuario FROM Usuarios WHERE NombreUsuario = @NombreUsuario');
  if (usuarioTomado.recordset.length > 0) {
    return { creado: false, motivo: 'Ese identificador ya está en uso como nombre de usuario' };
  }

  const rolResult = await new sql.Request(transaction).query("SELECT IdRol FROM Roles WHERE NombreRol = 'CLIENTE'");
  const idRolCliente = rolResult.recordset[0].IdRol;
  const passwordHash = await bcrypt.hash(identificador, SALT_ROUNDS);

  await new sql.Request(transaction)
    .input('IdPersona', sql.Int, idPersona)
    .input('NombreUsuario', sql.VarChar(50), identificador)
    .input('PasswordHash', sql.VarChar(255), passwordHash)
    .input('IdRol', sql.Int, idRolCliente)
    .query(`
      INSERT INTO Usuarios (IdPersona, NombreUsuario, PasswordHash, IdRol, RequiereCambioPassword)
      VALUES (@IdPersona, @NombreUsuario, @PasswordHash, @IdRol, 1)
    `);

  return { creado: true };
}

/**
 * Verificación rápida (contra nuestra propia BD, sin tocar apiperu.dev) de
 * si un DNI/RUC ya pertenece a una Persona registrada — como cliente o con
 * cualquier otro rol (Usuario). Pensada para que el formulario avise ANTES
 * de gastar una consulta paga a la API real, no después.
 */
async function verificarDocumento(req, res, next) {
  const { documento } = req.params;
  const { excluirIdPersona } = req.query;
  const documentoLimpio = String(documento || '').trim();

  if (!/^\d{8}$/.test(documentoLimpio) && !/^\d{11}$/.test(documentoLimpio)) {
    return res.status(400).json({ mensaje: 'Documento inválido' });
  }

  try {
    const pool = await getPool();
    const request = pool
      .request()
      .input('DNI', sql.VarChar(15), documentoLimpio)
      .input('ExcluirIdPersona', sql.Int, excluirIdPersona ? Number(excluirIdPersona) : null);

    const result = await request.query(`
      SELECT p.IdPersona, p.Nombres, p.ApellidoPaterno,
             CASE WHEN EXISTS (SELECT 1 FROM Clientes c WHERE c.IdPersona = p.IdPersona AND c.Estado = 1) THEN 1 ELSE 0 END AS EsCliente,
             CASE WHEN EXISTS (SELECT 1 FROM Usuarios u WHERE u.IdPersona = p.IdPersona) THEN 1 ELSE 0 END AS TieneUsuario
      FROM Personas p
      WHERE p.DNI = @DNI
        AND (@ExcluirIdPersona IS NULL OR p.IdPersona <> @ExcluirIdPersona)
    `);

    if (result.recordset.length === 0) {
      return res.status(200).json({ existe: false });
    }

    const fila = result.recordset[0];
    return res.status(200).json({
      existe: true,
      nombreCompleto: [fila.Nombres, fila.ApellidoPaterno].filter(Boolean).join(' ').trim(),
      esCliente: Boolean(fila.EsCliente),
      tieneUsuario: Boolean(fila.TieneUsuario),
    });
  } catch (err) {
    return next(err);
  }
}

/**
 * `?estado=activos` (por defecto, igual que antes) | `inactivos` | `todos`.
 * Los clientes desactivados no desaparecen para siempre — solo quedan
 * ocultos de la vista normal; este filtro es lo que permite encontrarlos
 * de nuevo para reactivarlos.
 */
async function listarClientes(req, res, next) {
  try {
    const estado = req.query.estado === 'inactivos' ? 'inactivos' : req.query.estado === 'todos' ? 'todos' : 'activos';
    const filtroEstado = estado === 'activos' ? 'WHERE c.Estado = 1' : estado === 'inactivos' ? 'WHERE c.Estado = 0' : '';

    const pool = await getPool();
    const result = await pool.request().query(`
      SELECT c.IdCliente, c.DescripcionNegocio, c.NombreComercialOficial, c.PuntosFidelidad, c.Estado,
             p.IdPersona, p.DNI, p.Nombres, p.ApellidoPaterno, p.ApellidoMaterno,
             p.Telefono, p.Email, p.Direccion, p.OrigenValidacion, p.TelefonoVerificado, p.EmailVerificado
      FROM Clientes c
      INNER JOIN Personas p ON p.IdPersona = c.IdPersona
      ${filtroEstado}
      ORDER BY p.Nombres, p.ApellidoPaterno
    `);

    return res.status(200).json({ clientes: result.recordset.map(mapearCliente) });
  } catch (err) {
    return next(err);
  }
}

async function crearCliente(req, res, next) {
  const {
    dni,
    nombres,
    apellidoPaterno,
    apellidoMaterno,
    telefono,
    email,
    direccion,
    descripcionNegocio,
    nombreComercialOficial,
    origenValidacion,
    dniVerificadoApiReal,
  } = req.body;
  const dniLimpio = dni ? String(dni).trim() : null;

  const pool = await getPool();
  const transaction = new sql.Transaction(pool);

  try {
    await transaction.begin();

    let idPersona = null;

    if (dniLimpio) {
      const existente = await new sql.Request(transaction)
        .input('DNI', sql.VarChar(15), dniLimpio)
        .query('SELECT IdPersona FROM Personas WHERE DNI = @DNI');

      if (existente.recordset.length > 0) {
        idPersona = existente.recordset[0].IdPersona;

        const clienteExistente = await new sql.Request(transaction)
          .input('IdPersona', sql.Int, idPersona)
          .query('SELECT IdCliente FROM Clientes WHERE IdPersona = @IdPersona');

        if (clienteExistente.recordset.length > 0) {
          await transaction.rollback();
          return res.status(409).json({ mensaje: 'Ya existe un cliente registrado con ese DNI' });
        }
      }
    }

    if (!idPersona) {
      const esEmpresa = esRucPersonaJuridica(dniLimpio);
      const nuevaPersona = await new sql.Request(transaction)
        .input('DNI', sql.VarChar(15), dniLimpio)
        .input('Nombres', sql.NVarChar(100), mayuscula(nombres))
        .input('ApellidoPaterno', sql.NVarChar(100), esEmpresa ? '' : mayuscula(apellidoPaterno || ''))
        .input('ApellidoMaterno', sql.NVarChar(100), esEmpresa ? null : mayuscula(apellidoMaterno))
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

    const nuevoCliente = await new sql.Request(transaction)
      .input('IdPersona', sql.Int, idPersona)
      .input('DescripcionNegocio', sql.NVarChar(300), mayuscula(descripcionNegocio))
      .input('NombreComercialOficial', sql.Bit, nombreComercialOficial === true)
      .query(`
        INSERT INTO Clientes (IdPersona, DescripcionNegocio, NombreComercialOficial)
        OUTPUT INSERTED.IdCliente
        VALUES (@IdPersona, @DescripcionNegocio, @NombreComercialOficial)
      `);
    const idCliente = nuevoCliente.recordset[0].IdCliente;

    const rolResult = await new sql.Request(transaction).query("SELECT IdRol FROM Roles WHERE NombreRol = 'CLIENTE'");
    const idRolCliente = rolResult.recordset[0].IdRol;

    // "IF NOT EXISTS (...) INSERT ..." era T-SQL puro (control de flujo fuera
    // de un procedimiento almacenado) — MariaDB no lo soporta y tira error de
    // sintaxis. INSERT...SELECT...WHERE NOT EXISTS es el equivalente
    // portable (no depende de que exista una constraint UNIQUE, a diferencia
    // de INSERT IGNORE).
    await new sql.Request(transaction)
      .input('IdPersona', sql.Int, idPersona)
      .input('IdRol', sql.Int, idRolCliente)
      .query(`
        INSERT INTO PersonaRoles (IdPersona, IdRol)
        SELECT @IdPersona, @IdRol
        WHERE NOT EXISTS (SELECT 1 FROM PersonaRoles WHERE IdPersona = @IdPersona AND IdRol = @IdRol)
      `);

    let clonacion = { creado: false, motivo: 'No verificado con datos reales de la API' };
    if (dniVerificadoApiReal === true && dniLimpio) {
      clonacion = await intentarClonarUsuarioCliente(transaction, idPersona, dniLimpio);
    }

    await transaction.commit();

    await registrarAuditoria({
      idUsuario: req.usuario.idUsuario,
      accion: 'CREAR_CLIENTE',
      tablaAfectada: 'Clientes',
      registroAfectadoId: String(idCliente),
      datosNuevos: { ...req.body, cuentaClonada: clonacion.creado },
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    if (clonacion.creado) {
      await registrarAuditoria({
        accion: 'CLONACION_AUTOMATICA_USUARIO',
        tablaAfectada: 'Usuarios',
        registroAfectadoId: dniLimpio,
        datosNuevos: { idPersona, origen: 'verificacion_api_real' },
        ip: req.ip,
        userAgent: req.headers['user-agent'],
      });
    }

    return res.status(201).json({
      mensaje: 'Cliente creado correctamente',
      idCliente,
      idPersona,
      cuentaClonada: clonacion.creado,
    });
  } catch (err) {
    await transaction.rollback();
    return next(err);
  }
}

async function actualizarCliente(req, res, next) {
  const { id } = req.params;
  const {
    dni,
    nombres,
    apellidoPaterno,
    apellidoMaterno,
    telefono,
    email,
    direccion,
    descripcionNegocio,
    nombreComercialOficial,
    origenValidacion,
    dniVerificadoApiReal,
  } = req.body;

  const pool = await getPool();
  const transaction = new sql.Transaction(pool);

  try {
    await transaction.begin();

    const clienteResult = await new sql.Request(transaction)
      .input('IdCliente', sql.Int, id)
      .query(`
        SELECT c.IdPersona, c.DescripcionNegocio, c.NombreComercialOficial,
               p.DNI, p.OrigenValidacion, p.Nombres, p.ApellidoPaterno, p.ApellidoMaterno
        FROM Clientes c
        INNER JOIN Personas p ON p.IdPersona = c.IdPersona
        WHERE c.IdCliente = @IdCliente AND c.Estado = 1
      `);

    if (clienteResult.recordset.length === 0) {
      await transaction.rollback();
      return res.status(404).json({ mensaje: 'Cliente no encontrado' });
    }

    const cliente = clienteResult.recordset[0];
    const yaVerificadoPermanente = cliente.OrigenValidacion === 'RENIEC';
    const nuevoApellidoPaterno = mayuscula(apellidoPaterno || '');
    const nuevoApellidoMaterno = mayuscula(apellidoMaterno);
    const intentaCambiarNombre =
      mayuscula(nombres) !== mayuscula(cliente.Nombres) ||
      nuevoApellidoPaterno !== mayuscula(cliente.ApellidoPaterno || '') ||
      nuevoApellidoMaterno !== mayuscula(cliente.ApellidoMaterno);

    if (yaVerificadoPermanente && intentaCambiarNombre) {
      await transaction.rollback();
      return res.status(403).json({
        mensaje: 'Los datos de este cliente fueron validados por RENIEC/SUNAT y no se pueden editar manualmente',
      });
    }

    // El nombre comercial oficial de SUNAT se bloquea igual que los nombres:
    // una vez que vino de una búsqueda real, no se puede pisar a mano.
    const descripcionNegocioNueva = mayuscula(descripcionNegocio);
    if (cliente.NombreComercialOficial && descripcionNegocioNueva !== mayuscula(cliente.DescripcionNegocio)) {
      await transaction.rollback();
      return res.status(403).json({
        mensaje: 'El nombre comercial de este cliente fue validado por SUNAT y no se puede editar manualmente',
      });
    }
    // Se bloquea a partir de ahora si esta actualización trae uno oficial
    // (nueva búsqueda de RUC exitosa) y aún no estaba bloqueado; si ya lo
    // estaba, se queda así para siempre.
    const nombreComercialOficialFinal = cliente.NombreComercialOficial || nombreComercialOficial === true;

    // Transición de "registro rápido" (manual/sin documento) a verificado:
    // solo se permite mientras el cliente no esté ya bloqueado permanentemente.
    // A partir de aquí OrigenValidacion pasa a RENIEC y queda fijo para siempre.
    let dniFinal = cliente.DNI;
    let origenFinal = cliente.OrigenValidacion;
    const dniNuevo = dni !== undefined && dni !== null && String(dni).trim() !== '' ? String(dni).trim() : null;

    // Se usa origenValidacion (no dniVerificadoApiReal) como disparador: una
    // búsqueda exitosa por API simulada también debe congelar y actualizar
    // el DNI, igual que en crearCliente. dniVerificadoApiReal solo decide si
    // además se clona una cuenta de acceso (eso sí exige la API real).
    if (!yaVerificadoPermanente && origenValidacion === 'RENIEC' && dniNuevo) {
      if (dniNuevo !== cliente.DNI) {
        const dniTomado = await new sql.Request(transaction)
          .input('DNI', sql.VarChar(15), dniNuevo)
          .input('IdPersonaActual', sql.Int, cliente.IdPersona)
          .query('SELECT IdPersona FROM Personas WHERE DNI = @DNI AND IdPersona <> @IdPersonaActual');

        if (dniTomado.recordset.length > 0) {
          await transaction.rollback();
          return res.status(409).json({ mensaje: 'Ya existe otra persona registrada con ese DNI' });
        }
      }

      dniFinal = dniNuevo;
      origenFinal = 'RENIEC';
    }

    const esEmpresa = esRucPersonaJuridica(dniFinal);
    const apellidoPaternoFinal = esEmpresa ? '' : nuevoApellidoPaterno;
    const apellidoMaternoFinal = esEmpresa ? null : nuevoApellidoMaterno;

    await new sql.Request(transaction)
      .input('IdPersona', sql.Int, cliente.IdPersona)
      .input('DNI', sql.VarChar(15), dniFinal)
      .input('Nombres', sql.NVarChar(100), mayuscula(nombres))
      .input('ApellidoPaterno', sql.NVarChar(100), apellidoPaternoFinal)
      .input('ApellidoMaterno', sql.NVarChar(100), apellidoMaternoFinal)
      .input('Telefono', sql.VarChar(20), telefono ? telefono.trim() : null)
      .input('Email', sql.VarChar(150), email ? email.trim() : null)
      .input('Direccion', sql.NVarChar(250), mayuscula(direccion))
      .input('OrigenValidacion', sql.VarChar(20), origenFinal)
      .query(`
        UPDATE Personas
        SET DNI = @DNI, Nombres = @Nombres, ApellidoPaterno = @ApellidoPaterno, ApellidoMaterno = @ApellidoMaterno,
            Telefono = @Telefono, Email = @Email, Direccion = @Direccion, OrigenValidacion = @OrigenValidacion
        WHERE IdPersona = @IdPersona
      `);

    await new sql.Request(transaction)
      .input('IdCliente', sql.Int, id)
      .input('DescripcionNegocio', sql.NVarChar(300), descripcionNegocioNueva)
      .input('NombreComercialOficial', sql.Bit, nombreComercialOficialFinal)
      .query(
        'UPDATE Clientes SET DescripcionNegocio = @DescripcionNegocio, NombreComercialOficial = @NombreComercialOficial WHERE IdCliente = @IdCliente',
      );

    let clonacion = { creado: false, motivo: 'No verificado con datos reales de la API' };
    if (dniVerificadoApiReal === true && origenFinal === 'RENIEC' && dniFinal) {
      clonacion = await intentarClonarUsuarioCliente(transaction, cliente.IdPersona, dniFinal);
    }

    await transaction.commit();

    await registrarAuditoria({
      idUsuario: req.usuario.idUsuario,
      accion: 'ACTUALIZAR_CLIENTE',
      tablaAfectada: 'Clientes',
      registroAfectadoId: String(id),
      datosNuevos: { ...req.body, cuentaClonada: clonacion.creado },
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    return res.status(200).json({ mensaje: 'Cliente actualizado correctamente', cuentaClonada: clonacion.creado });
  } catch (err) {
    await transaction.rollback();
    return next(err);
  }
}

async function desactivarCliente(req, res, next) {
  const { id } = req.params;

  try {
    const pool = await getPool();
    const result = await pool
      .request()
      .input('IdCliente', sql.Int, id)
      .query('UPDATE Clientes SET Estado = 0 WHERE IdCliente = @IdCliente AND Estado = 1');

    if (result.rowsAffected[0] === 0) {
      return res.status(404).json({ mensaje: 'Cliente no encontrado o ya estaba desactivado' });
    }

    await registrarAuditoria({
      idUsuario: req.usuario.idUsuario,
      accion: 'DESACTIVAR_CLIENTE',
      tablaAfectada: 'Clientes',
      registroAfectadoId: String(id),
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    return res.status(200).json({ mensaje: 'Cliente desactivado correctamente' });
  } catch (err) {
    return next(err);
  }
}

async function reactivarCliente(req, res, next) {
  const { id } = req.params;

  try {
    const pool = await getPool();
    const result = await pool
      .request()
      .input('IdCliente', sql.Int, id)
      .query('UPDATE Clientes SET Estado = 1 WHERE IdCliente = @IdCliente AND Estado = 0');

    if (result.rowsAffected[0] === 0) {
      return res.status(404).json({ mensaje: 'Cliente no encontrado o ya estaba activo' });
    }

    await registrarAuditoria({
      idUsuario: req.usuario.idUsuario,
      accion: 'REACTIVAR_CLIENTE',
      tablaAfectada: 'Clientes',
      registroAfectadoId: String(id),
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    return res.status(200).json({ mensaje: 'Cliente reactivado correctamente' });
  } catch (err) {
    return next(err);
  }
}

/**
 * Autoservicio: el propio cliente autenticado consulta SU cliente asociado
 * (por IdPersona del JWT, nunca por :id de la URL, así es imposible que
 * consulte el perfil de alguien más).
 */
async function obtenerMiPerfil(req, res, next) {
  try {
    const pool = await getPool();
    const result = await pool
      .request()
      .input('IdPersona', sql.Int, req.usuario.idPersona)
      .query(`
        SELECT c.IdCliente, c.DescripcionNegocio, c.NombreComercialOficial, c.PuntosFidelidad,
               p.IdPersona, p.DNI, p.Nombres, p.ApellidoPaterno, p.ApellidoMaterno,
               p.Telefono, p.Email, p.Direccion, p.OrigenValidacion, p.TelefonoVerificado, p.EmailVerificado
        FROM Clientes c
        INNER JOIN Personas p ON p.IdPersona = c.IdPersona
        WHERE c.IdPersona = @IdPersona AND c.Estado = 1
      `);

    if (result.recordset.length === 0) {
      return res.status(404).json({ mensaje: 'No tienes un perfil de cliente asociado a tu cuenta' });
    }

    return res.status(200).json({ cliente: mapearCliente(result.recordset[0]) });
  } catch (err) {
    return next(err);
  }
}

/**
 * Autoservicio: el cliente solo puede actualizar su dirección de entrega
 * aquí. Nombres/apellidos/DNI están fuera de alcance a propósito — esos
 * requieren el candado de verificación de clientesController.actualizarCliente,
 * mediado por el personal. Teléfono y correo TAMPOCO se tocan aquí desde que
 * existe verificación por SMS/PIN — ver solicitarCodigoCelular/Correo y
 * confirmarCodigoCelular/Correo más abajo: cambiarlos ahora es un flujo
 * propio con código de un solo uso, no un simple guardado de formulario.
 */
async function actualizarMiPerfil(req, res, next) {
  const { direccion } = req.body;

  try {
    const pool = await getPool();
    const clienteResult = await pool
      .request()
      .input('IdPersona', sql.Int, req.usuario.idPersona)
      .query('SELECT c.IdCliente FROM Clientes c WHERE c.IdPersona = @IdPersona AND c.Estado = 1');

    if (clienteResult.recordset.length === 0) {
      return res.status(404).json({ mensaje: 'No tienes un perfil de cliente asociado a tu cuenta' });
    }

    await pool
      .request()
      .input('IdPersona', sql.Int, req.usuario.idPersona)
      .input('Direccion', sql.NVarChar(250), mayuscula(direccion))
      .query('UPDATE Personas SET Direccion = @Direccion WHERE IdPersona = @IdPersona');

    await registrarAuditoria({
      idUsuario: req.usuario.idUsuario,
      accion: 'ACTUALIZAR_MI_PERFIL',
      tablaAfectada: 'Personas',
      registroAfectadoId: String(req.usuario.idPersona),
      datosNuevos: req.body,
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    return res.status(200).json({ mensaje: 'Perfil actualizado correctamente' });
  } catch (err) {
    return next(err);
  }
}

async function obtenerClientePropio(idPersona) {
  const pool = await getPool();
  const result = await pool
    .request()
    .input('IdPersona', sql.Int, idPersona)
    .query(`
      SELECT c.IdCliente, p.Telefono, p.Email, p.TelefonoVerificado, p.EmailVerificado
      FROM Clientes c
      INNER JOIN Personas p ON p.IdPersona = c.IdPersona
      WHERE c.IdPersona = @IdPersona AND c.Estado = 1
    `);
  return result.recordset[0] || null;
}

/**
 * Mapea un OtpError a una respuesta HTTP clara. AUTORIZACION_REQUERIDA usa
 * 403 (el cliente está autenticado, pero le falta un paso extra); COOLDOWN
 * usa 429; el resto (código inválido/expirado/demasiados intentos) usa 400.
 */
function manejarOtpError(err, res, next) {
  if (err instanceof OtpError) {
    const status = err.tipo === 'COOLDOWN' ? 429 : err.tipo === 'AUTORIZACION_REQUERIDA' ? 403 : 400;
    return res.status(status).json({ mensaje: err.message, tipo: err.tipo });
  }
  return next(err);
}

/**
 * Si el cliente ya tiene AL MENOS un canal verificado (celular o correo),
 * cualquier cambio sensible (celular, correo o contraseña) exige
 * autorizarlo primero con un código enviado a ESE canal ya verificado. Así,
 * si alguien más usa la sesión del dueño (ej. le prestó la cuenta a un
 * trabajador), no puede tocar estos datos sin tener acceso real al celular
 * o correo del dueño — la autorización, no la contraseña de sesión, es la
 * barrera real.
 */
async function exigirAutorizacionSiCorresponde({ idPersona, cliente, canalAutorizacion, codigoAutorizacion }) {
  const requiereAutorizacion = Boolean(cliente.TelefonoVerificado) || Boolean(cliente.EmailVerificado);
  if (!requiereAutorizacion) return;

  if (!canalAutorizacion || !codigoAutorizacion) {
    throw new OtpError(
      'AUTORIZACION_REQUERIDA',
      'Debes autorizar este cambio primero con un código enviado a tu celular o correo verificado.',
    );
  }
  if (canalAutorizacion === 'SMS' && !cliente.TelefonoVerificado) {
    throw new OtpError('AUTORIZACION_REQUERIDA', 'Tu celular no está verificado. Autoriza con tu correo verificado.');
  }
  if (canalAutorizacion === 'EMAIL' && !cliente.EmailVerificado) {
    throw new OtpError('AUTORIZACION_REQUERIDA', 'Tu correo no está verificado. Autoriza con tu celular verificado.');
  }

  const destino = canalAutorizacion === 'SMS' ? cliente.Telefono : cliente.Email;
  await verificarCodigo({ idPersona, proposito: 'AUTORIZAR_CAMBIO', destino, codigo: codigoAutorizacion });
}

async function solicitarCodigoCelular(req, res, next) {
  const { telefonoNuevo, canalAutorizacion, codigoAutorizacion } = req.body;
  const idPersona = req.usuario.idPersona;

  try {
    const cliente = await obtenerClientePropio(idPersona);
    if (!cliente) return res.status(404).json({ mensaje: 'No tienes un perfil de cliente asociado a tu cuenta' });

    await exigirAutorizacionSiCorresponde({ idPersona, cliente, canalAutorizacion, codigoAutorizacion });
    await solicitarCodigo({ idPersona, canal: 'SMS', proposito: 'VERIFICAR_TELEFONO', destino: telefonoNuevo.trim() });

    return res.status(200).json({ mensaje: 'Código enviado por SMS' });
  } catch (err) {
    return manejarOtpError(err, res, next);
  }
}

async function confirmarCodigoCelular(req, res, next) {
  const { telefonoNuevo, codigo } = req.body;
  const idPersona = req.usuario.idPersona;

  try {
    const cliente = await obtenerClientePropio(idPersona);
    if (!cliente) return res.status(404).json({ mensaje: 'No tienes un perfil de cliente asociado a tu cuenta' });

    await verificarCodigo({ idPersona, proposito: 'VERIFICAR_TELEFONO', destino: telefonoNuevo.trim(), codigo });

    const pool = await getPool();
    await pool
      .request()
      .input('IdPersona', sql.Int, idPersona)
      .input('Telefono', sql.VarChar(20), telefonoNuevo.trim())
      .query('UPDATE Personas SET Telefono = @Telefono, TelefonoVerificado = 1 WHERE IdPersona = @IdPersona');

    await registrarAuditoria({
      idUsuario: req.usuario.idUsuario,
      accion: 'VERIFICAR_TELEFONO',
      tablaAfectada: 'Personas',
      registroAfectadoId: String(idPersona),
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    return res.status(200).json({ mensaje: 'Celular verificado correctamente' });
  } catch (err) {
    return manejarOtpError(err, res, next);
  }
}

async function solicitarCodigoCorreo(req, res, next) {
  const { emailNuevo, canalAutorizacion, codigoAutorizacion } = req.body;
  const idPersona = req.usuario.idPersona;

  try {
    const cliente = await obtenerClientePropio(idPersona);
    if (!cliente) return res.status(404).json({ mensaje: 'No tienes un perfil de cliente asociado a tu cuenta' });

    await exigirAutorizacionSiCorresponde({ idPersona, cliente, canalAutorizacion, codigoAutorizacion });
    await solicitarCodigo({
      idPersona,
      canal: 'EMAIL',
      proposito: 'VERIFICAR_EMAIL',
      destino: emailNuevo.trim().toLowerCase(),
    });

    return res.status(200).json({ mensaje: 'Código enviado por correo' });
  } catch (err) {
    return manejarOtpError(err, res, next);
  }
}

async function confirmarCodigoCorreo(req, res, next) {
  const { emailNuevo, codigo } = req.body;
  const idPersona = req.usuario.idPersona;

  try {
    const cliente = await obtenerClientePropio(idPersona);
    if (!cliente) return res.status(404).json({ mensaje: 'No tienes un perfil de cliente asociado a tu cuenta' });

    await verificarCodigo({
      idPersona,
      proposito: 'VERIFICAR_EMAIL',
      destino: emailNuevo.trim().toLowerCase(),
      codigo,
    });

    const pool = await getPool();
    await pool
      .request()
      .input('IdPersona', sql.Int, idPersona)
      .input('Email', sql.VarChar(150), emailNuevo.trim().toLowerCase())
      .query('UPDATE Personas SET Email = @Email, EmailVerificado = 1 WHERE IdPersona = @IdPersona');

    await registrarAuditoria({
      idUsuario: req.usuario.idUsuario,
      accion: 'VERIFICAR_EMAIL',
      tablaAfectada: 'Personas',
      registroAfectadoId: String(idPersona),
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    return res.status(200).json({ mensaje: 'Correo verificado correctamente' });
  } catch (err) {
    return manejarOtpError(err, res, next);
  }
}

/** Envía el código que autoriza un cambio sensible (celular, correo o
 * contraseña) al canal YA verificado que el cliente elija. */
async function solicitarAutorizacion(req, res, next) {
  const { canal } = req.body;
  const idPersona = req.usuario.idPersona;

  try {
    const cliente = await obtenerClientePropio(idPersona);
    if (!cliente) return res.status(404).json({ mensaje: 'No tienes un perfil de cliente asociado a tu cuenta' });

    if (canal === 'SMS' && !cliente.TelefonoVerificado) {
      return res.status(400).json({ mensaje: 'Tu celular no está verificado.' });
    }
    if (canal === 'EMAIL' && !cliente.EmailVerificado) {
      return res.status(400).json({ mensaje: 'Tu correo no está verificado.' });
    }

    const destino = canal === 'SMS' ? cliente.Telefono : cliente.Email;
    await solicitarCodigo({ idPersona, canal, proposito: 'AUTORIZAR_CAMBIO', destino });

    return res.status(200).json({
      mensaje: `Código de autorización enviado por ${canal === 'SMS' ? 'SMS' : 'correo'}`,
    });
  } catch (err) {
    return manejarOtpError(err, res, next);
  }
}

/**
 * Valida el código de autorización EN EL MOMENTO (sin gastarlo — ver
 * `consumir: false` en `verificarCodigo`), para que el paso de "autoriza
 * este cambio" en la app pueda mostrar el error ahí mismo si el código es
 * incorrecto, en vez de dejarlo avanzar en silencio y recién fallar más
 * adelante al intentar el cambio real (confuso: parece que un código
 * cualquiera "funciona" cuando en realidad solo se pospuso el rechazo).
 */
async function validarAutorizacion(req, res, next) {
  const { canal, codigo } = req.body;
  const idPersona = req.usuario.idPersona;

  try {
    const cliente = await obtenerClientePropio(idPersona);
    if (!cliente) return res.status(404).json({ mensaje: 'No tienes un perfil de cliente asociado a tu cuenta' });

    if (canal === 'SMS' && !cliente.TelefonoVerificado) {
      return res.status(400).json({ mensaje: 'Tu celular no está verificado.' });
    }
    if (canal === 'EMAIL' && !cliente.EmailVerificado) {
      return res.status(400).json({ mensaje: 'Tu correo no está verificado.' });
    }

    const destino = canal === 'SMS' ? cliente.Telefono : cliente.Email;
    await verificarCodigo({ idPersona, proposito: 'AUTORIZAR_CAMBIO', destino, codigo, consumir: false });

    return res.status(200).json({ mensaje: 'Código válido' });
  } catch (err) {
    return manejarOtpError(err, res, next);
  }
}

/**
 * Cambio de contraseña autoservicio (distinto del cambio obligatorio de
 * primer login en authController.cambiarPassword): no pide la contraseña
 * actual — la pide el propio código de autorización, que es lo que de
 * verdad protege esta acción si alguien más usa la sesión del dueño.
 */
async function cambiarPasswordSeguro(req, res, next) {
  const { passwordNueva, canalAutorizacion, codigoAutorizacion } = req.body;
  const idPersona = req.usuario.idPersona;
  const idUsuario = req.usuario.idUsuario;

  try {
    const cliente = await obtenerClientePropio(idPersona);
    if (!cliente) return res.status(404).json({ mensaje: 'No tienes un perfil de cliente asociado a tu cuenta' });

    if (!cliente.TelefonoVerificado && !cliente.EmailVerificado) {
      return res.status(400).json({
        mensaje: 'Verifica tu celular o correo antes de poder cambiar tu contraseña.',
      });
    }

    await exigirAutorizacionSiCorresponde({ idPersona, cliente, canalAutorizacion, codigoAutorizacion });

    const passwordHash = await bcrypt.hash(passwordNueva, SALT_ROUNDS);
    const pool = await getPool();
    await pool
      .request()
      .input('IdUsuario', sql.Int, idUsuario)
      .input('PasswordHash', sql.VarChar(255), passwordHash)
      .query('UPDATE Usuarios SET PasswordHash = @PasswordHash, FechaActualizacion = SYSUTCDATETIME() WHERE IdUsuario = @IdUsuario');

    await registrarAuditoria({
      idUsuario,
      accion: 'CAMBIO_PASSWORD_AUTOSERVICIO',
      tablaAfectada: 'Usuarios',
      registroAfectadoId: String(idUsuario),
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    return res.status(200).json({ mensaje: 'Contraseña actualizada correctamente' });
  } catch (err) {
    return manejarOtpError(err, res, next);
  }
}

module.exports = {
  listarClientes,
  crearCliente,
  actualizarCliente,
  desactivarCliente,
  reactivarCliente,
  obtenerMiPerfil,
  actualizarMiPerfil,
  verificarDocumento,
  solicitarCodigoCelular,
  confirmarCodigoCelular,
  solicitarCodigoCorreo,
  confirmarCodigoCorreo,
  solicitarAutorizacion,
  validarAutorizacion,
  cambiarPasswordSeguro,
  // Reexportado para publicoController.js (pedido web sin login) — mismo
  // clonado de cuenta (usuario=DNI, password=DNI) que ya dispara un
  // registro de cliente hecho por el personal con DNI real verificado.
  intentarClonarUsuarioCliente,
};
