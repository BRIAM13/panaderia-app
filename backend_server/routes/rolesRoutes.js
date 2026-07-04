const express = require('express');
const { listarAsignables } = require('../controllers/rolesController');
const { verificarToken, autorizarRoles } = require('../middlewares/authMiddleware');

const router = express.Router();

router.use(verificarToken);
router.use(autorizarRoles('ADMIN', 'SUPERADMIN'));

router.get('/asignables', listarAsignables);

module.exports = router;
