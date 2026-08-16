const express = require('express');
const { listarCatalogoPublico, crearPedidoPublico, consultarPedidosPublicos } = require('../controllers/publicoController');
const { validateCrearPedidoPublico, validateConsultarPedidosPublico } = require('../middlewares/validators');

// Sin verificarToken a propósito: es la única puerta de entrada pensada
// para un visitante de la página web sin cuenta todavía — ver el
// límite de intentos por IP en publicoController.js.
const router = express.Router();

router.get('/catalogo', listarCatalogoPublico);
router.post('/pedidos', validateCrearPedidoPublico, crearPedidoPublico);
router.get('/pedidos', validateConsultarPedidosPublico, consultarPedidosPublicos);

module.exports = router;
