const express = require('express');
const { obtenerConfiguracion, actualizarConfiguracion } = require('../controllers/configuracionesController');
const { validateConfiguracion } = require('../middlewares/validators');
const { verificarToken, autorizarRoles } = require('../middlewares/authMiddleware');

const router = express.Router();

router.use(verificarToken);

// Cualquier usuario autenticado puede leer (ej. la pantalla de Nuevo Pedido
// necesita el precio del paquete). Solo ADMIN/SUPERADMIN pueden modificarla.
router.get('/:clave', obtenerConfiguracion);
router.put('/:clave', autorizarRoles('ADMIN', 'SUPERADMIN'), validateConfiguracion, actualizarConfiguracion);

module.exports = router;
