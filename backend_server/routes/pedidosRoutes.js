const express = require('express');
const {
  crearPedido,
  crearMiPedido,
  listarPedidos,
  misPedidos,
  cancelarMiPedido,
  aprobarPedido,
  rechazarPedido,
  entregarPedido,
  listarDeudas,
  marcarDeudaPagada,
} = require('../controllers/pedidosController');
const { validatePedido, validateMiPedido } = require('../middlewares/validators');
const { verificarToken, autorizarRoles } = require('../middlewares/authMiddleware');

const router = express.Router();

router.use(verificarToken);

// Autoservicio: el propio CLIENTE ve y registra SUS pedidos. Debe
// registrarse antes del candado de roles de abajo (igual que
// /clientes/mi-perfil).
router.get('/mis-pedidos', misPedidos);
router.post('/mi-pedido', validateMiPedido, crearMiPedido);
router.put('/mis-pedidos/:id/cancelar', cancelarMiPedido);

// Ver o registrar pedidos de CUALQUIER cliente es exclusivo del personal —
// un CLIENTE no debe poder listar los pedidos de otros clientes. El
// candado de tienda específica (aprobar/rechazar/entregar) se resuelve
// dentro de cada controller, porque primero hay que buscar a qué tienda
// pertenece el pedido antes de poder validar el acceso.
router.use(autorizarRoles('TRABAJADOR', 'ADMIN', 'SUPERADMIN'));

router.get('/', listarPedidos);
router.get('/deudas', listarDeudas);
router.post('/', validatePedido, crearPedido);
router.put('/:id/aprobar', aprobarPedido);
router.put('/:id/rechazar', rechazarPedido);
router.put('/:id/entregar', entregarPedido);
router.put('/:id/marcar-deuda-pagada', marcarDeudaPagada);

module.exports = router;
