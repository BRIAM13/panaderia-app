const express = require('express');
const { predecirDemanda } = require('../controllers/prediccionDemandaController');
const { verificarToken, autorizarRoles } = require('../middlewares/authMiddleware');

const router = express.Router();

router.use(verificarToken);
router.use(autorizarRoles('ADMIN', 'SUPERADMIN'));

router.get('/:idTienda/:idProducto', predecirDemanda);

module.exports = router;
