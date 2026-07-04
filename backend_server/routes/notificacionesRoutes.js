const express = require('express');
const { registrarToken } = require('../controllers/notificacionesController');
const { verificarToken } = require('../middlewares/authMiddleware');

const router = express.Router();

router.use(verificarToken);
router.post('/registrar-token', registrarToken);

module.exports = router;
