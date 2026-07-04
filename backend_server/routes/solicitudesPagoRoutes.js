const express = require('express');
const { misDeudas, crear, reportar, confirmar, rechazar, listarPendientes } = require('../controllers/solicitudesPagoController');
const { validateSolicitudPago } = require('../middlewares/validators');
const { verificarToken, autorizarRoles } = require('../middlewares/authMiddleware');

const router = express.Router();

router.use(verificarToken);

// Autoservicio: el propio CLIENTE ve sus deudas, genera su solicitud de
// pago y reporta cuando ya transfirió/yapeó.
router.get('/mis-deudas', misDeudas);
router.post('/', validateSolicitudPago, crear);
router.put('/:id/reportar', reportar);

// Revisar/confirmar/rechazar pagos reportados es exclusivo del personal —
// el candado de tienda específica se resuelve dentro de cada controller.
router.use(autorizarRoles('TRABAJADOR', 'ADMIN', 'SUPERADMIN'));

router.get('/pendientes', listarPendientes);
router.put('/:id/confirmar', confirmar);
router.put('/:id/rechazar', rechazar);

module.exports = router;
