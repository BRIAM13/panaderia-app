const express = require('express');
const {
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
  obtenerPerfilCliente,
  listarNotasCliente,
  crearNotaCliente,
  canjearPuntos,
  enviarCampaniaReactivacion,
} = require('../controllers/clientesController');
const {
  validateCliente,
  validateMiPerfil,
  validateSolicitarCodigoCelular,
  validateConfirmarCodigoCelular,
  validateSolicitarCodigoCorreo,
  validateConfirmarCodigoCorreo,
  validateSolicitarAutorizacion,
  validateValidarAutorizacion,
  validateCambiarPasswordSeguro,
} = require('../middlewares/validators');
const { verificarToken, autorizarRoles } = require('../middlewares/authMiddleware');

const router = express.Router();

router.use(verificarToken);

// Autoservicio: cualquier usuario autenticado con un perfil de Cliente
// asociado a su propia Persona (típicamente rol CLIENTE) puede ver/editar
// SUS PROPIOS datos de contacto y dirección de entrega. Nunca sus nombres
// ni su DNI (eso solo lo puede tocar el personal, ver clientesController.js).
// Debe registrarse antes del candado de roles de abajo.
router.get('/mi-perfil', obtenerMiPerfil);
router.put('/mi-perfil', validateMiPerfil, actualizarMiPerfil);

// Verificar/cambiar celular y correo, y cambio de contraseña autoservicio —
// todos con código de un solo uso (SMS o email), nunca un simple guardado.
router.post('/mi-perfil/celular/solicitar-codigo', validateSolicitarCodigoCelular, solicitarCodigoCelular);
router.post('/mi-perfil/celular/confirmar-codigo', validateConfirmarCodigoCelular, confirmarCodigoCelular);
router.post('/mi-perfil/correo/solicitar-codigo', validateSolicitarCodigoCorreo, solicitarCodigoCorreo);
router.post('/mi-perfil/correo/confirmar-codigo', validateConfirmarCodigoCorreo, confirmarCodigoCorreo);
router.post('/mi-perfil/autorizacion/solicitar', validateSolicitarAutorizacion, solicitarAutorizacion);
router.post('/mi-perfil/autorizacion/validar', validateValidarAutorizacion, validarAutorizacion);
router.post('/mi-perfil/password/cambiar-seguro', validateCambiarPasswordSeguro, cambiarPasswordSeguro);

// El resto del CRUD de Clientes (listar/crear/editar cualquier cliente,
// desactivar) es exclusivo del personal.
router.use(autorizarRoles('TRABAJADOR', 'ADMIN', 'SUPERADMIN'));

router.get('/', listarClientes);
// Antes de gastar una consulta paga a apiperu.dev, el formulario pregunta
// aquí (barato, contra nuestra propia BD) si el documento ya pertenece a
// alguien registrado (cliente o cualquier otro rol).
router.get('/verificar-documento/:documento', verificarDocumento);
router.post('/', validateCliente, crearCliente);
router.put('/:id', validateCliente, actualizarCliente);
router.delete('/:id', desactivarCliente);
router.put('/:id/reactivar', reactivarCliente);

// CRM: perfil con historial agregado + segmento, notas internas del
// personal, y canje de puntos de fidelidad.
router.get('/:id/perfil', obtenerPerfilCliente);
router.get('/:id/notas', listarNotasCliente);
router.post('/:id/notas', crearNotaCliente);
router.post('/:id/canjear-puntos', canjearPuntos);

// Campaña de reactivación (push a clientes "en riesgo") — exclusivo
// ADMIN/SUPERADMIN, a diferencia del resto del CRUD de arriba.
router.post('/campanias/reactivacion', autorizarRoles('ADMIN', 'SUPERADMIN'), enviarCampaniaReactivacion);

module.exports = router;
