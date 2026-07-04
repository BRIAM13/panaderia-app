const express = require('express');
const { listarProductos } = require('../controllers/productosController');
const { verificarToken } = require('../middlewares/authMiddleware');

const router = express.Router();

router.get('/', verificarToken, listarProductos);

module.exports = router;
