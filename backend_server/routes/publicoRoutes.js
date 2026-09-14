const express = require('express');
const {
  listarCatalogoPublico,
  crearPedidoPublico,
  registrarCodigoPagoPublico,
  consultarPedidosPublicos,
  verificarDocumentoPublico,
  obtenerMedioPagoPublico,
} = require('../controllers/publicoController');
const {
  validateCrearPedidoPublico,
  validateConsultarPedidosPublico,
  validateVerificarDocumentoPublico,
} = require('../middlewares/validators');

// Sin verificarToken a propósito: es la única puerta de entrada pensada
// para un visitante de la página web sin cuenta todavía — ver el
// límite de intentos por IP en publicoController.js.
const router = express.Router();

router.get('/catalogo', listarCatalogoPublico);
router.post('/pedidos', validateCrearPedidoPublico, crearPedidoPublico);
router.get('/pedidos', validateConsultarPedidosPublico, consultarPedidosPublicos);
router.get('/verificar-documento', validateVerificarDocumentoPublico, verificarDocumentoPublico);

// Pago por adelantado con Yape (solo Panadería). Van sin validador propio:
// las dos validan todo dentro del controller, porque cada regla necesita
// mirar la fila del pedido (el monto se compara contra SU total, el código
// solo se acepta si ese pedido sigue esperándolo).
router.get('/medio-pago', obtenerMedioPagoPublico);
router.post('/pedidos/:idPedido/codigo-pago', registrarCodigoPagoPublico);

module.exports = router;
