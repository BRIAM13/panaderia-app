const express = require('express');
const { listarTiendas, misTiendas, resumenTienda, fechasConVentas } = require('../controllers/tiendasController');
const { verificarToken, autorizarRoles, autorizarTienda } = require('../middlewares/authMiddleware');

const router = express.Router();

router.use(verificarToken);

router.get('/', listarTiendas);
router.get('/mis-tiendas', autorizarRoles('TRABAJADOR', 'ADMIN', 'SUPERADMIN'), misTiendas);
router.get(
  '/:idTienda/resumen',
  // El Dashboard de su tienda ahora es la pantalla principal para TODO el
  // personal, no solo Admin/Superadmin — un Trabajador también necesita
  // poder pedir este resumen. autorizarTienda igual se encarga de que solo
  // vea el de una tienda a la que de verdad tiene acceso.
  autorizarRoles('TRABAJADOR', 'ADMIN', 'SUPERADMIN'),
  autorizarTienda((req) => req.params.idTienda),
  resumenTienda,
);
router.get(
  '/:idTienda/fechas-con-ventas',
  autorizarRoles('TRABAJADOR', 'ADMIN', 'SUPERADMIN'),
  autorizarTienda((req) => req.params.idTienda),
  fechasConVentas,
);

module.exports = router;
