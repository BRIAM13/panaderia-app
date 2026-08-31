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

router.post('/register', validateRegister, register);
router.post('/login', limitadorLogin, validateLogin, login);
router.post('/refresh-token', validateRefreshToken, refrescarToken);

router.get('/perfil', verificarToken, obtenerPerfil);
router.post('/cambiar-password', verificarToken, validateCambiarPassword, cambiarPassword);

module.exports = router;
