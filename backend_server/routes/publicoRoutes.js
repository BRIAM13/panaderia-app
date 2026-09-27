const express = require('express');
const {
  listarCatalogoPublico,
  crearPedidoPublico,
  registrarCodigoPagoPublico,
  pagarPedidoCulqi,
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

// Pago por adelantado del pedido de Panadería. Van sin validador propio:
// todas validan dentro del controller, porque cada regla necesita mirar la
// fila del pedido (el monto se cobra contra SU total, y solo se acepta un
// pago si ese pedido sigue esperándolo).
router.get('/medio-pago', obtenerMedioPagoPublico);

// Culqi (la vía vigente desde el 2026-09-26): el navegador tokeniza la
// tarjeta con la llave PÚBLICA y manda solo el token; el cargo lo crea el
// servidor con la secreta. Ni un dato de tarjeta pasa por acá.
router.post('/pedidos/:idPedido/pagar-culqi', pagarPedidoCulqi);

// Código de operación de Yape — dado de baja el 2026-09-17 y ya inalcanzable
// desde la web (ningún pedido nuevo nace esperando un código). La ruta se
// deja en pie porque un pedido viejo podría estar todavía en 'VERIFICANDO'
// esperando el suyo; para todo pedido nuevo responde 400 sola, por la
// máquina de estados.
router.post('/pedidos/:idPedido/codigo-pago', registrarCodigoPagoPublico);

module.exports = router;
