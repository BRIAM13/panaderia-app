const express = require('express');
const rateLimit = require('express-rate-limit');
const {
  register,
  login,
  cambiarPassword,
  obtenerPerfil,
  refrescarToken,
  solicitarRecuperacion,
  confirmarRecuperacion,
  activarCuenta,
} = require('../controllers/authController');
const {
  validateRegister,
  validateLogin,
  validateCambiarPassword,
  validateRefreshToken,
  validateSolicitarRecuperacion,
  validateConfirmarRecuperacion,
  validateActivarCuenta,
} = require('../middlewares/validators');
const { verificarToken } = require('../middlewares/authMiddleware');

const router = express.Router();

// 20 intentos cada 15 min por IP — de sobra para un usuario real que se
// equivoca de contraseña varias veces, pero corta un ataque de fuerza bruta
// contra /login, que antes no tenía ningún límite propio (a diferencia de
// publicoController.js, que ya limitaba sus propias rutas públicas).
const limitadorLogin = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: { mensaje: 'Demasiados intentos de inicio de sesión. Intenta de nuevo en unos minutos.' },
});

// /register es la otra ruta sin JWT de este archivo y no tenía ningún
// límite: un bot podía crear cuentas (y Personas) en masa hasta llenar la
// base. 10 registros cada 15 min por IP es de sobra para un alta real
// —incluso varias personas compartiendo el wifi de la tienda— y corta el
// abuso automatizado. Mismo patrón que limitadorLogin.
const limitadorRegistro = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { mensaje: 'Demasiados registros desde esta conexión. Intenta de nuevo en unos minutos.' },
});

// Más estricto que limitadorLogin: cada intento acá, si la cuenta existe,
// manda un correo real (costo) y, ya con el código en mano, cambia una
// contraseña. 8 cada 15 min por IP alcanza de sobra a un usuario real
// (incluso si se equivoca de código un par de veces) y corta tanto el
// tanteo de cuentas existentes como el spam de correos.
const limitadorRecuperacion = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 8,
  standardHeaders: true,
  legacyHeaders: false,
  message: { mensaje: 'Demasiados intentos. Intenta de nuevo en unos minutos.' },
});

// Contador propio (no se comparte con limitadorRecuperacion): son dos
// flujos distintos y no tiene sentido que un cliente que está activando su
// cuenta gaste los intentos de otro que olvidó su contraseña. 10 cada 15
// min por IP alcanza de sobra para alguien que se equivoca al repetir la
// contraseña, y corta el tanteo de tokens — que de por sí es inviable
// (256 bits), pero cada intento cuesta un bcrypt.compare del servidor.
const limitadorActivacion = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { mensaje: 'Demasiados intentos. Intenta de nuevo en unos minutos.' },
});

router.post('/register', limitadorRegistro, validateRegister, register);
router.post('/login', limitadorLogin, validateLogin, login);
router.post('/refresh-token', validateRefreshToken, refrescarToken);
router.post('/recuperar/solicitar', limitadorRecuperacion, validateSolicitarRecuperacion, solicitarRecuperacion);
router.post('/recuperar/confirmar', limitadorRecuperacion, validateConfirmarRecuperacion, confirmarRecuperacion);
// Sin JWT a propósito: quien llega acá todavía no puede iniciar sesión
// (su cuenta no está activada). La puerta de entrada real es el token del
// correo — ver activarCuenta en authController.js.
router.post('/activar-cuenta', limitadorActivacion, validateActivarCuenta, activarCuenta);

router.get('/perfil', verificarToken, obtenerPerfil);
router.post('/cambiar-password', verificarToken, validateCambiarPassword, cambiarPassword);

module.exports = router;
