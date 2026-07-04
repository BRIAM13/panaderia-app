const express = require('express');
const { listarTiendas, misTiendas, resumenTienda } = require('../controllers/tiendasController');
const { verificarToken, autorizarRoles, autorizarTienda } = require('../middlewares/authMiddleware');

const router = express.Router();

router.use(verificarToken);

router.get('/', listarTiendas);
router.get('/mis-tiendas', autorizarRoles('TRABAJADOR', 'ADMIN', 'SUPERADMIN'), misTiendas);
router.get(
  '/:idTienda/resumen',
  autorizarRoles('ADMIN', 'SUPERADMIN'),
  autorizarTienda((req) => req.params.idTienda),
  resumenTienda,
);

module.exports = router;
