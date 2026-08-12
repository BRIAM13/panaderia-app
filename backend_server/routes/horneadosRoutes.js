const express = require('express');
const { listarSugerencias, crearPedidoHorneado } = require('../controllers/horneadosController');
const { validateCrearPedidoHorneado } = require('../middlewares/validators');
const { verificarToken, autorizarRoles } = require('../middlewares/authMiddleware');

const router = express.Router();

router.use(verificarToken);
// Igual que /pedidos: registrar pedidos de Horneados es exclusivo del
// personal, nunca autoservicio directo (ver nota de "precio no estable
// todavía" en pedidosController.js — mismo motivo aplica acá).
router.use(autorizarRoles('TRABAJADOR', 'ADMIN', 'SUPERADMIN'));

router.get('/sugerencias', listarSugerencias);
router.post('/pedidos', validateCrearPedidoHorneado, crearPedidoHorneado);

module.exports = router;
