const { fechaEntregaEsAnteriorAHoy } = require('../utils/fechaPeru');

const DNI_REGEX = /^[0-9A-Za-z]{8,15}$/;
const DNI_PERU_REGEX = /^\d{8}$/;
const RUC_PERU_REGEX = /^\d{11}$/;
const CELULAR_PERU_REGEX = /^\d{9}$/;
const USERNAME_REGEX = /^[a-zA-Z0-9_.]{4,50}$/;
const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function isNonEmptyString(value) {
  return typeof value === 'string' && value.trim().length > 0;
}

function validateRegister(req, res, next) {
  const { dni, nombres, apellidoPaterno, apellidoMaterno, email, telefono, nombreUsuario, password } = req.body;
  const errores = [];

  if (!isNonEmptyString(dni) || !DNI_REGEX.test(dni.trim())) {
    errores.push('DNI inválido: debe tener entre 8 y 15 caracteres alfanuméricos.');
  }
  if (!isNonEmptyString(nombres) || nombres.trim().length > 100) {
    errores.push('Nombres inválidos.');
  }
  if (!isNonEmptyString(apellidoPaterno) || apellidoPaterno.trim().length > 100) {
    errores.push('Apellido paterno inválido.');
  }
  if (apellidoMaterno !== undefined && apellidoMaterno !== null && apellidoMaterno.trim().length > 100) {
    errores.push('Apellido materno inválido.');
  }
  if (email !== undefined && email !== null && email.trim().length > 0 && !EMAIL_REGEX.test(email.trim())) {
    errores.push('Email inválido.');
  }
  if (telefono !== undefined && telefono !== null && telefono.trim().length > 20) {
    errores.push('Teléfono inválido.');
  }
  if (!isNonEmptyString(nombreUsuario) || !USERNAME_REGEX.test(nombreUsuario.trim())) {
    errores.push('Nombre de usuario inválido: use 4 a 50 caracteres (letras, números, "_" o ".").');
  }
  if (!isNonEmptyString(password) || password.length < 8) {
    errores.push('La contraseña debe tener al menos 8 caracteres.');
  }

  if (errores.length > 0) {
    return res.status(400).json({ mensaje: 'Datos de registro inválidos', errores });
  }

  next();
}

function validateLogin(req, res, next) {
  const { nombreUsuario, password } = req.body;
  const errores = [];

  if (!isNonEmptyString(nombreUsuario) || nombreUsuario.trim().length > 50) {
    errores.push('Nombre de usuario requerido.');
  }
  if (!isNonEmptyString(password) || password.length > 200) {
    errores.push('Contraseña requerida.');
  }

  if (errores.length > 0) {
    return res.status(400).json({ mensaje: 'Datos de inicio de sesión inválidos', errores });
  }

  next();
}

function validateCambiarPassword(req, res, next) {
  const { passwordNueva } = req.body;
  const errores = [];

  if (!isNonEmptyString(passwordNueva) || passwordNueva.length < 8) {
    errores.push('La nueva contraseña debe tener al menos 8 caracteres.');
  }

  if (errores.length > 0) {
    return res.status(400).json({ mensaje: 'Datos de cambio de contraseña inválidos', errores });
  }

  next();
}

function validateRefreshToken(req, res, next) {
  const { refreshToken } = req.body;

  if (!isNonEmptyString(refreshToken)) {
    return res.status(400).json({ mensaje: 'refreshToken es requerido' });
  }

  next();
}

function validateCliente(req, res, next) {
  const { dni, nombres, apellidoPaterno, apellidoMaterno, telefono, email, direccion, descripcionNegocio } = req.body;
  const errores = [];

  if (dni !== undefined && dni !== null && dni !== '') {
    const dniLimpio = String(dni).trim();
    if (!DNI_PERU_REGEX.test(dniLimpio) && !RUC_PERU_REGEX.test(dniLimpio)) {
      errores.push('El documento debe ser un DNI de 8 dígitos o un RUC de 11 dígitos.');
    }
  }
  if (!isNonEmptyString(nombres) || nombres.trim().length > 100) {
    errores.push('Nombres inválidos.');
  }
  // Apellido paterno es opcional en Clientes: el "registro rápido" solo exige Nombres/Razón social.
  if (apellidoPaterno !== undefined && apellidoPaterno !== null && apellidoPaterno.trim().length > 100) {
    errores.push('Apellido paterno inválido.');
  }
  if (apellidoMaterno !== undefined && apellidoMaterno !== null && apellidoMaterno.trim().length > 100) {
    errores.push('Apellido materno inválido.');
  }
  if (telefono !== undefined && telefono !== null && telefono.trim().length > 20) {
    errores.push('Teléfono inválido.');
  }
  if (email !== undefined && email !== null && email.trim().length > 0 && !EMAIL_REGEX.test(email.trim())) {
    errores.push('Email inválido.');
  }
  if (direccion !== undefined && direccion !== null && direccion.trim().length > 250) {
    errores.push('Dirección inválida.');
  }
  if (descripcionNegocio !== undefined && descripcionNegocio !== null && descripcionNegocio.trim().length > 300) {
    errores.push('Descripción de negocio inválida.');
  }

  if (errores.length > 0) {
    return res.status(400).json({ mensaje: 'Datos de cliente inválidos', errores });
  }

  next();
}

/**
 * Trabajadores siempre se identifican con DNI (8 dígitos) — a diferencia de
 * Clientes, aquí no aplica RUC (empresas no "trabajan"). `tiendas` debe
 * traer al menos una tienda.
 */
const ROLES_DE_PERSONAL = ['TRABAJADOR', 'ADMIN', 'SUPERADMIN'];

function validateTrabajador(req, res, next) {
  const { dni, nombres, apellidoPaterno, apellidoMaterno, telefono, email, direccion, rol, salario, tiendas } = req.body;
  const errores = [];

  if (!isNonEmptyString(dni) || !DNI_PERU_REGEX.test(dni.trim())) {
    errores.push('DNI inválido: debe tener 8 dígitos.');
  }
  if (!isNonEmptyString(nombres) || nombres.trim().length > 100) {
    errores.push('Nombres inválidos.');
  }
  if (!isNonEmptyString(apellidoPaterno) || apellidoPaterno.trim().length > 100) {
    errores.push('Apellido paterno inválido.');
  }
  if (apellidoMaterno !== undefined && apellidoMaterno !== null && apellidoMaterno.trim().length > 100) {
    errores.push('Apellido materno inválido.');
  }
  if (telefono !== undefined && telefono !== null && telefono.trim().length > 20) {
    errores.push('Teléfono inválido.');
  }
  if (email !== undefined && email !== null && email.trim().length > 0 && !EMAIL_REGEX.test(email.trim())) {
    errores.push('Email inválido.');
  }
  if (direccion !== undefined && direccion !== null && direccion.trim().length > 250) {
    errores.push('Dirección inválida.');
  }
  if (!ROLES_DE_PERSONAL.includes(rol)) {
    errores.push(`El rol debe ser uno de: ${ROLES_DE_PERSONAL.join(', ')}.`);
  }
  if (salario !== undefined && salario !== null && (typeof salario !== 'number' || salario < 0)) {
    errores.push('Salario inválido.');
  }
  if (!Array.isArray(tiendas) || tiendas.length === 0 || !tiendas.every((t) => Number.isInteger(t) && t > 0)) {
    errores.push('Debes asignar al menos una tienda válida.');
  }

  if (errores.length > 0) {
    return res.status(400).json({ mensaje: 'Datos de trabajador inválidos', errores });
  }

  next();
}

/**
 * Autoservicio de "Mi perfil" (rol CLIENTE): a diferencia de validateCliente,
 * aquí NUNCA se aceptan nombres/apellidos/DNI — esos solo puede tocarlos el
 * personal a través del candado de verificación (ver clientesController.js).
 * Solo dirección de entrega — teléfono y correo tienen su propio flujo con
 * código de verificación (ver validateSolicitarCodigoCelular/Correo).
 */
function validateMiPerfil(req, res, next) {
  const { direccion } = req.body;
  const errores = [];

  if (direccion !== undefined && direccion !== null && direccion.trim().length > 250) {
    errores.push('Dirección inválida.');
  }

  if (errores.length > 0) {
    return res.status(400).json({ mensaje: 'Datos de perfil inválidos', errores });
  }

  next();
}

const TELEFONO_REGEX = /^\d{6,20}$/;
const CODIGO_OTP_REGEX = /^\d{6}$/;

/**
 * `canalAutorizacion`/`codigoAutorizacion` son opcionales aquí a propósito:
 * el controller decide si son obligatorios según si el cliente ya tiene
 * algún canal verificado (ver clientesController.js). Si vienen, deben
 * tener forma válida.
 */
function validarAutorizacionOpcional(body, errores) {
  const { canalAutorizacion, codigoAutorizacion } = body;
  if (canalAutorizacion === undefined && codigoAutorizacion === undefined) return;
  if (canalAutorizacion !== 'SMS' && canalAutorizacion !== 'EMAIL') {
    errores.push('Canal de autorización inválido.');
  }
  if (!isNonEmptyString(codigoAutorizacion) || !CODIGO_OTP_REGEX.test(codigoAutorizacion.trim())) {
    errores.push('Código de autorización inválido.');
  }
}

function validateSolicitarCodigoCelular(req, res, next) {
  const { telefonoNuevo } = req.body;
  const errores = [];
  if (!isNonEmptyString(telefonoNuevo) || !TELEFONO_REGEX.test(telefonoNuevo.trim())) {
    errores.push('Número de celular inválido.');
  }
  validarAutorizacionOpcional(req.body, errores);
  if (errores.length > 0) return res.status(400).json({ mensaje: 'Datos inválidos', errores });
  next();
}

function validateConfirmarCodigoCelular(req, res, next) {
  const { telefonoNuevo, codigo } = req.body;
  const errores = [];
  if (!isNonEmptyString(telefonoNuevo) || !TELEFONO_REGEX.test(telefonoNuevo.trim())) {
    errores.push('Número de celular inválido.');
  }
  if (!isNonEmptyString(codigo) || !CODIGO_OTP_REGEX.test(codigo.trim())) {
    errores.push('El código debe tener 6 dígitos.');
  }
  if (errores.length > 0) return res.status(400).json({ mensaje: 'Datos inválidos', errores });
  next();
}

function validateSolicitarCodigoCorreo(req, res, next) {
  const { emailNuevo } = req.body;
  const errores = [];
  if (!isNonEmptyString(emailNuevo) || !EMAIL_REGEX.test(emailNuevo.trim())) {
    errores.push('Email inválido.');
  }
  validarAutorizacionOpcional(req.body, errores);
  if (errores.length > 0) return res.status(400).json({ mensaje: 'Datos inválidos', errores });
  next();
}

function validateConfirmarCodigoCorreo(req, res, next) {
  const { emailNuevo, codigo } = req.body;
  const errores = [];
  if (!isNonEmptyString(emailNuevo) || !EMAIL_REGEX.test(emailNuevo.trim())) {
    errores.push('Email inválido.');
  }
  if (!isNonEmptyString(codigo) || !CODIGO_OTP_REGEX.test(codigo.trim())) {
    errores.push('El código debe tener 6 dígitos.');
  }
  if (errores.length > 0) return res.status(400).json({ mensaje: 'Datos inválidos', errores });
  next();
}

function validateSolicitarAutorizacion(req, res, next) {
  const { canal } = req.body;
  if (canal !== 'SMS' && canal !== 'EMAIL') {
    return res.status(400).json({ mensaje: 'Canal inválido: debe ser SMS o EMAIL.' });
  }
  next();
}

function validateValidarAutorizacion(req, res, next) {
  const { canal, codigo } = req.body;
  const errores = [];
  if (canal !== 'SMS' && canal !== 'EMAIL') {
    errores.push('Canal inválido: debe ser SMS o EMAIL.');
  }
  if (!isNonEmptyString(codigo) || !CODIGO_OTP_REGEX.test(codigo.trim())) {
    errores.push('El código debe tener 6 dígitos.');
  }
  if (errores.length > 0) return res.status(400).json({ mensaje: 'Datos inválidos', errores });
  next();
}

function validateCambiarPasswordSeguro(req, res, next) {
  const { passwordNueva } = req.body;
  const errores = [];
  if (!isNonEmptyString(passwordNueva) || passwordNueva.length < 8) {
    errores.push('La nueva contraseña debe tener al menos 8 caracteres.');
  }
  const { canalAutorizacion, codigoAutorizacion } = req.body;
  if (canalAutorizacion !== 'SMS' && canalAutorizacion !== 'EMAIL') {
    errores.push('Canal de autorización inválido.');
  }
  if (!isNonEmptyString(codigoAutorizacion) || !CODIGO_OTP_REGEX.test(codigoAutorizacion.trim())) {
    errores.push('Código de autorización inválido.');
  }
  if (errores.length > 0) return res.status(400).json({ mensaje: 'Datos inválidos', errores });
  next();
}

function validatePedido(req, res, next) {
  const { idCliente, idProducto, tipoPedido, cantidad, precioUnitario, fechaEntrega } = req.body;
  const errores = [];

  if (!Number.isInteger(idCliente) || idCliente <= 0) {
    errores.push('Debe seleccionar un cliente válido.');
  }
  if (!Number.isInteger(idProducto) || idProducto <= 0) {
    errores.push('Debe seleccionar un producto válido.');
  }
  if (tipoPedido !== 'UNIDADES' && tipoPedido !== 'PAQUETES') {
    errores.push('El tipo de pedido debe ser UNIDADES o PAQUETES.');
  }
  if (!Number.isInteger(cantidad) || cantidad <= 0) {
    errores.push('La cantidad debe ser un número entero mayor a 0.');
  }
  if (typeof precioUnitario !== 'number' || !Number.isFinite(precioUnitario) || precioUnitario <= 0) {
    errores.push('El precio a cobrar debe ser un número mayor a 0.');
  }
  // La fecha/hora de entrega es opcional: si no se indica, el pedido queda
  // "sin fecha programada". Si SÍ se indica, debe ser una fecha válida y su
  // DÍA (hora de Perú) no puede ser anterior a hoy — la hora exacta no
  // importa para esta validación, ya que por defecto viene en medianoche
  // cuando no se eligió una específica.
  if (fechaEntrega !== undefined && fechaEntrega !== null && fechaEntrega !== '') {
    if (Number.isNaN(Date.parse(fechaEntrega))) {
      errores.push('La fecha y hora de entrega no es válida.');
    } else if (fechaEntregaEsAnteriorAHoy(fechaEntrega)) {
      errores.push('La fecha de entrega no puede ser anterior a hoy.');
    }
  }

  if (errores.length > 0) {
    return res.status(400).json({ mensaje: 'Datos de pedido inválidos', errores });
  }

  next();
}

function validateCrearPedidoHorneado(req, res, next) {
  const {
    idCliente,
    carne,
    presentacion,
    cantidad,
    aplicaAderezo,
    tipoAderezo,
    precioHorneado,
    precioAderezo,
    fechaEntrega,
  } = req.body;
  const errores = [];

  if (!Number.isInteger(idCliente) || idCliente <= 0) {
    errores.push('Debe seleccionar un cliente válido.');
  }
  if (!isNonEmptyString(carne)) {
    errores.push('Indica el tipo de carne.');
  }
  if (!isNonEmptyString(presentacion)) {
    errores.push('Indica la presentación.');
  }
  if (!Number.isInteger(cantidad) || cantidad <= 0) {
    errores.push('La cantidad debe ser un número entero mayor a 0.');
  }
  if (typeof precioHorneado !== 'number' || !Number.isFinite(precioHorneado) || precioHorneado <= 0) {
    errores.push('El precio del horneado debe ser un número mayor a 0.');
  }
  if (aplicaAderezo === true) {
    if (tipoAderezo !== 'CRIOLLO' && tipoAderezo !== 'ORIENTAL') {
      errores.push('Elige el tipo de aderezo (criollo u oriental).');
    }
    if (typeof precioAderezo !== 'number' || !Number.isFinite(precioAderezo) || precioAderezo <= 0) {
      errores.push('El precio del aderezo debe ser un número mayor a 0.');
    }
  } else if (aplicaAderezo !== false) {
    errores.push('Indica si aplica aderezo.');
  }
  if (fechaEntrega !== undefined && fechaEntrega !== null && fechaEntrega !== '') {
    if (Number.isNaN(Date.parse(fechaEntrega))) {
      errores.push('La fecha y hora de entrega no es válida.');
    } else if (fechaEntregaEsAnteriorAHoy(fechaEntrega)) {
      errores.push('La fecha de entrega no puede ser anterior a hoy.');
    }
  }

  if (errores.length > 0) {
    return res.status(400).json({ mensaje: 'Datos de pedido inválidos', errores });
  }

  next();
}

/**
 * Pedido desde la página web pública, sin login (ver publicoController.js)
 * — a diferencia de todo lo demás en este archivo, acá no hay JWT detrás,
 * así que la validación es la única barrera antes de tocar la base de
 * datos y (potencialmente) gastar una consulta paga a apiperu.dev.
 */
function validateCrearPedidoPublico(req, res, next) {
  const { documento, telefono, idProducto, cantidad, notas } = req.body;
  const errores = [];

  if (!isNonEmptyString(documento) || (!DNI_PERU_REGEX.test(documento.trim()) && !RUC_PERU_REGEX.test(documento.trim()))) {
    errores.push('El documento debe ser un DNI de 8 dígitos o un RUC de 11 dígitos.');
  }
  // Celular peruano: siempre 9 dígitos, más estricto que TELEFONO_REGEX
  // (6-20, pensado para otros formularios que sí aceptan fijos/extranjeros).
  if (!isNonEmptyString(telefono) || !CELULAR_PERU_REGEX.test(telefono.trim())) {
    errores.push('Ingresa un número de celular válido de 9 dígitos.');
  }
  if (!Number.isInteger(idProducto) || idProducto <= 0) {
    errores.push('Selecciona un producto válido.');
  }
  if (!Number.isInteger(cantidad) || cantidad <= 0 || cantidad > 500) {
    errores.push('Ingresa una cantidad válida.');
  }
  if (notas !== undefined && notas !== null && String(notas).trim().length > 200) {
    errores.push('La nota es demasiado larga.');
  }

  if (errores.length > 0) {
    return res.status(400).json({ mensaje: 'Datos de pedido inválidos', errores });
  }

  next();
}

/**
 * Autoservicio (rol CLIENTE): a diferencia de validatePedido, aquí no hay
 * `idCliente` (siempre es el del propio JWT) ni `precioUnitario` (siempre
 * sale del catálogo) — el cliente solo elige un producto y una cantidad; la
 * tienda y el tipo de pedido (PAQUETES/UNIDADES) se derivan del producto en
 * el controller, no vienen del body (ver crearMiPedido).
 */
function validateMiPedido(req, res, next) {
  const { idProducto, cantidad, fechaEntrega } = req.body;
  const errores = [];

  if (!Number.isInteger(idProducto) || idProducto <= 0) {
    errores.push('Selecciona un producto válido.');
  }
  if (!Number.isInteger(cantidad) || cantidad <= 0) {
    errores.push('La cantidad debe ser un número entero mayor a 0.');
  }
  if (fechaEntrega !== undefined && fechaEntrega !== null && fechaEntrega !== '') {
    if (Number.isNaN(Date.parse(fechaEntrega))) {
      errores.push('La fecha y hora de entrega no es válida.');
    } else if (fechaEntregaEsAnteriorAHoy(fechaEntrega)) {
      errores.push('La fecha de entrega no puede ser anterior a hoy.');
    }
  }

  if (errores.length > 0) {
    return res.status(400).json({ mensaje: 'Datos de pedido inválidos', errores });
  }

  next();
}

function validateConfiguracion(req, res, next) {
  const { valor } = req.body;

  if (!isNonEmptyString(valor) || valor.trim().length > 200) {
    return res.status(400).json({ mensaje: 'El valor de la configuración es requerido (máx. 200 caracteres).' });
  }

  next();
}

const TIPOS_MEDIO_PAGO = ['YAPE', 'PLIN', 'TRANSFERENCIA', 'OTRO'];

function validateImagenQr(imagenQrBase64, errores) {
  if (imagenQrBase64 === undefined || imagenQrBase64 === null || imagenQrBase64 === '') return;
  if (typeof imagenQrBase64 !== 'string' || imagenQrBase64.length > 4_000_000) {
    errores.push('La imagen del QR no es válida o es demasiado grande.');
  }
}

function validateMedioPago(req, res, next) {
  const { idTienda, tipo, titular, numeroDestino, cci, nombreBanco, imagenQrBase64 } = req.body;
  const errores = [];
  validateImagenQr(imagenQrBase64, errores);

  if (!Number.isInteger(idTienda) || idTienda <= 0) {
    errores.push('Debes indicar una tienda válida.');
  }
  if (!TIPOS_MEDIO_PAGO.includes(tipo)) {
    errores.push(`El tipo debe ser uno de: ${TIPOS_MEDIO_PAGO.join(', ')}.`);
  }
  if (!isNonEmptyString(titular) || titular.trim().length > 150) {
    errores.push('El nombre del titular es requerido (máx. 150 caracteres).');
  }
  if (!isNonEmptyString(numeroDestino) || numeroDestino.trim().length > 30) {
    errores.push('El número de destino es requerido (máx. 30 caracteres).');
  }
  if (tipo === 'TRANSFERENCIA' && !isNonEmptyString(cci)) {
    errores.push('El CCI es requerido para transferencias bancarias.');
  }
  if (cci !== undefined && cci !== null && cci !== '' && !/^\d{20}$/.test(cci.trim())) {
    errores.push('El CCI debe tener 20 dígitos.');
  }
  if (nombreBanco !== undefined && nombreBanco !== null && nombreBanco !== '' && nombreBanco.trim().length > 100) {
    errores.push('El nombre del banco no puede superar 100 caracteres.');
  }

  if (errores.length > 0) {
    return res.status(400).json({ mensaje: 'Datos de medio de pago inválidos', errores });
  }

  next();
}

function validateActualizarMedioPago(req, res, next) {
  const { titular, numeroDestino, cci, nombreBanco, imagenQrBase64 } = req.body;
  const errores = [];
  validateImagenQr(imagenQrBase64, errores);

  if (!isNonEmptyString(titular) || titular.trim().length > 150) {
    errores.push('El nombre del titular es requerido (máx. 150 caracteres).');
  }
  if (!isNonEmptyString(numeroDestino) || numeroDestino.trim().length > 30) {
    errores.push('El número de destino es requerido (máx. 30 caracteres).');
  }
  if (cci !== undefined && cci !== null && cci !== '' && !/^\d{20}$/.test(cci.trim())) {
    errores.push('El CCI debe tener 20 dígitos.');
  }
  if (nombreBanco !== undefined && nombreBanco !== null && nombreBanco !== '' && nombreBanco.trim().length > 100) {
    errores.push('El nombre del banco no puede superar 100 caracteres.');
  }

  if (errores.length > 0) {
    return res.status(400).json({ mensaje: 'Datos de medio de pago inválidos', errores });
  }

  next();
}

function validateSolicitudPago(req, res, next) {
  const { idMedioPago, idsPedidos } = req.body;
  const errores = [];

  if (!Number.isInteger(idMedioPago) || idMedioPago <= 0) {
    errores.push('Debes indicar un medio de pago válido.');
  }
  if (!Array.isArray(idsPedidos) || idsPedidos.length === 0) {
    errores.push('Debes seleccionar al menos un pedido para pagar.');
  } else if (!idsPedidos.every((id) => Number.isInteger(id) && id > 0)) {
    errores.push('La lista de pedidos contiene valores inválidos.');
  }

  if (errores.length > 0) {
    return res.status(400).json({ mensaje: 'Datos de solicitud de pago inválidos', errores });
  }

  next();
}

/**
 * Consulta pública de pedidos por DNI (ver publicoController.js) — igual
 * de sin-JWT que validateCrearPedidoPublico, el DNI viene por query string.
 */
function validateConsultarPedidosPublico(req, res, next) {
  const { dni } = req.query;

  if (!isNonEmptyString(dni) || !DNI_PERU_REGEX.test(dni.trim())) {
    return res.status(400).json({ mensaje: 'Ingresa un DNI válido de 8 dígitos.' });
  }

  next();
}

/**
 * Verificación pública de existencia de DNI/RUC (ver publicoController.js,
 * verificarDocumentoPublico) — mismo criterio sin-JWT que
 * validateCrearPedidoPublico, el documento viene por query string.
 */
function validateVerificarDocumentoPublico(req, res, next) {
  const { documento } = req.query;

  if (!isNonEmptyString(documento) || (!DNI_PERU_REGEX.test(documento.trim()) && !RUC_PERU_REGEX.test(documento.trim()))) {
    return res.status(400).json({ mensaje: 'El documento debe ser un DNI de 8 dígitos o un RUC de 11 dígitos.' });
  }

  next();
}

module.exports = {
  validateRegister,
  validateLogin,
  validateCambiarPassword,
  validateRefreshToken,
  validateCliente,
  validateTrabajador,
  validateMiPerfil,
  validatePedido,
  validateMiPedido,
  validateCrearPedidoHorneado,
  validateCrearPedidoPublico,
  validateConsultarPedidosPublico,
  validateVerificarDocumentoPublico,
  validateConfiguracion,
  validateMedioPago,
  validateActualizarMedioPago,
  validateSolicitudPago,
  validateSolicitarCodigoCelular,
  validateConfirmarCodigoCelular,
  validateSolicitarCodigoCorreo,
  validateConfirmarCodigoCorreo,
  validateSolicitarAutorizacion,
  validateValidarAutorizacion,
  validateCambiarPasswordSeguro,
  DNI_PERU_REGEX,
  RUC_PERU_REGEX,
};
