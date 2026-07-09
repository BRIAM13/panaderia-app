const express = require('express');
const { listarActivos, listarPorTienda, crear, actualizar, cambiarEstado } = require('../controllers/mediosPagoController');
const { validateMedioPago, validateActualizarMedioPago } = require('../middlewares/validators');
const { verificarToken, autorizarRoles } = require('../middlewares/authMiddleware');

const router = express.Router();

router.use(verificarToken);

// Cualquier usuario autenticado (incluido CLIENTE) puede ver los medios de
// pago activos de una tienda — los necesita para elegir cómo pagar.
router.get('/', listarActivos);

// Gestión (crear/editar/activar/desactivar) es exclusiva de SUPERADMIN: son
// las cuentas reales (Yape/Plin/transferencia) donde llega el dinero de la
// empresa, ni un ADMIN de tienda puede tocarlas.
router.use(autorizarRoles('SUPERADMIN'));

router.get('/tienda/:idTienda', listarPorTienda);
router.post('/', validateMedioPago, crear);
router.put('/:id', validateActualizarMedioPago, actualizar);
router.put('/:id/estado', cambiarEstado);

module.exports = router;
