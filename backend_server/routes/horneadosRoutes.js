const express = require('express');
const {
  listarSugerencias,
  crearPedidoHorneado,
  listarPedidosHorneados,
  listarDeudasHorneados,
} = require('../controllers/horneadosController');
const { validateCrearPedidoHorneado } = require('../middlewares/validators');
const { verificarToken, autorizarRoles } = require('../middlewares/authMiddleware');

const router = express.Router();

router.use(verificarToken);
// Igual que /pedidos: registrar pedidos de Horneados es exclusivo del
// personal, nunca autoservicio directo (ver nota de "precio no estable
// todavía" en pedidosController.js — mismo motivo aplica acá).
router.use(autorizarRoles('TRABAJADOR', 'ADMIN', 'SUPERADMIN'));

router.get('/sugerencias', listarSugerencias);
router.get('/pedidos', listarPedidosHorneados);
router.get('/deudas', listarDeudasHorneados);
router.post('/pedidos', validateCrearPedidoHorneado, crearPedidoHorneado);

// Aprobar/rechazar/entregar/cancelar/marcar-deuda-pagada de un pedido de
// Horneados NO tienen ruta propia acá — se resuelven en /api/pedidos/:id/...
// (pedidosController.js), que ya es genérico por tienda (ver
// obtenerPedidoConAcceso/tieneAccesoATienda: resuelven la tienda real del
// pedido, no asumen Hamburguesas). Duplicarlas acá sería repetir la misma
// lógica sin ganar nada.

module.exports = router;
