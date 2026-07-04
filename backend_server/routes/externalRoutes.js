const express = require('express');
const { consultarDni, consultarRuc } = require('../controllers/externalController');
const { verificarToken } = require('../middlewares/authMiddleware');

const router = express.Router();

router.post('/dni', verificarToken, consultarDni);
router.post('/ruc', verificarToken, consultarRuc);

module.exports = router;
