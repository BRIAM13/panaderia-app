const express = require('express');
const { register, login, cambiarPassword, obtenerPerfil, refrescarToken } = require('../controllers/authController');
const { validateRegister, validateLogin, validateCambiarPassword, validateRefreshToken } = require('../middlewares/validators');
const { verificarToken } = require('../middlewares/authMiddleware');

const router = express.Router();

router.post('/register', validateRegister, register);
router.post('/login', validateLogin, login);
router.post('/refresh-token', validateRefreshToken, refrescarToken);

router.get('/perfil', verificarToken, obtenerPerfil);
router.post('/cambiar-password', verificarToken, validateCambiarPassword, cambiarPassword);

module.exports = router;
