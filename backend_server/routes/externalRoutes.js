const express = require('express');
const rateLimit = require('express-rate-limit');
const { consultarDni, consultarRuc } = require('../controllers/externalController');
const { verificarToken } = require('../middlewares/authMiddleware');

const router = express.Router();

// Estas dos rutas son la puerta directa a apiperu.dev, que es una API PAGA
// con cupo limitado (ver token_api_peru_page.dart en la app). Tenían JWT
// pero ningún límite propio: un usuario autenticado — o un token filtrado —
// podía agotar el saldo del mes en un bucle de un par de minutos. 60 cada 15
// min por IP es de sobra para un mostrador registrando clientes de verdad
// (uno cada 15 segundos, sin parar), y corta el abuso automatizado. Mismo
// patrón que el limitador de /login en authRoutes.js, y misma intención que
// los límites en memoria de publicoController.js.
const limitadorConsultaDocumento = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 60,
  standardHeaders: true,
  legacyHeaders: false,
  message: { mensaje: 'Demasiadas consultas de documento. Intenta de nuevo en unos minutos.' },
});

router.post('/dni', verificarToken, limitadorConsultaDocumento, consultarDni);
router.post('/ruc', verificarToken, limitadorConsultaDocumento, consultarRuc);

module.exports = router;
