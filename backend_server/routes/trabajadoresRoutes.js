const express = require('express');
const {
  buscarPorDni,
  crearTrabajador,
  listarTrabajadores,
  cambiarRolTrabajador,
  otorgarAccesoTienda,
  revocarAccesoTienda,
  darDeBajaTrabajador,
} = require('../controllers/trabajadoresController');
const { validateTrabajador } = require('../middlewares/validators');
const { verificarToken, autorizarRoles, autorizarTienda } = require('../middlewares/authMiddleware');

const router = express.Router();

router.use(verificarToken);
// Gestionar trabajadores es exclusivo de administración — un TRABAJADOR
// raso no registra ni otorga acceso a otros trabajadores.
router.use(autorizarRoles('ADMIN', 'SUPERADMIN'));

router.get('/buscar-por-dni/:dni', buscarPorDni);
router.get('/', listarTrabajadores);
router.post('/', validateTrabajador, crearTrabajador);
router.put('/:id/rol', cambiarRolTrabajador);
router.put('/:id/tiendas/:idTienda', autorizarTienda((req) => req.params.idTienda), otorgarAccesoTienda);
router.delete('/:id/tiendas/:idTienda', autorizarTienda((req) => req.params.idTienda), revocarAccesoTienda);
router.delete('/:id', darDeBajaTrabajador);

module.exports = router;
