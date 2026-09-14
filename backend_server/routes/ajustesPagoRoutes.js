const express = require('express');
const { listarAjustesPendientes, resolverAjustePago } = require('../controllers/pagoAdelantoController');
const { verificarToken, autorizarRoles } = require('../middlewares/authMiddleware');

const router = express.Router();

router.use(verificarToken);

// Saldos y vueltos pendientes son plata de la tienda: solo el personal.
// El candado de tienda concreta se resuelve dentro de cada controller
// (listar filtra por las tiendas asignadas; resolver mira a qué tienda
// pertenece el pedido del ajuste), igual que en pedidosRoutes.js.
router.use(autorizarRoles('TRABAJADOR', 'ADMIN', 'SUPERADMIN'));

router.get('/', listarAjustesPendientes);
router.post('/:id/resolver', resolverAjustePago);

module.exports = router;
