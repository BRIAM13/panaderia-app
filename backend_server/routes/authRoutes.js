const express = require('express');
const rateLimit = require('express-rate-limit');
const { register, login, cambiarPassword, obtenerPerfil, refrescarToken } = require('../controllers/authController');
const { validateRegister, validateLogin, validateCambiarPassword, validateRefreshToken } = require('../middlewares/validators');
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

router.post('/register', limitadorRegistro, validateRegister, register);
router.post('/login', limitadorLogin, validateLogin, login);
router.post('/refresh-token', validateRefreshToken, refrescarToken);

router.get('/perfil', verificarToken, obtenerPerfil);
router.post('/cambiar-password', verificarToken, validateCambiarPassword, cambiarPassword);

module.exports = router;
