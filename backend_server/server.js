require('dotenv').config();

const express = require('express');
const cors = require('cors');
const morgan = require('morgan');

const { getPool } = require('./config/db');
const authRoutes = require('./routes/authRoutes');
const externalRoutes = require('./routes/externalRoutes');
const clientesRoutes = require('./routes/clientesRoutes');
const pedidosRoutes = require('./routes/pedidosRoutes');
const productosRoutes = require('./routes/productosRoutes');
const configuracionesRoutes = require('./routes/configuracionesRoutes');
const notificacionesRoutes = require('./routes/notificacionesRoutes');
const tiendasRoutes = require('./routes/tiendasRoutes');
const trabajadoresRoutes = require('./routes/trabajadoresRoutes');
const mediosPagoRoutes = require('./routes/mediosPagoRoutes');
const solicitudesPagoRoutes = require('./routes/solicitudesPagoRoutes');
const rolesRoutes = require('./routes/rolesRoutes');
const { notFoundHandler, errorHandler } = require('./middlewares/errorHandler');

const app = express();

app.use(cors());
// 3mb (no 10kb): el registro de medios de pago admite subir la imagen real
// del QR de Yape/Plin en base64 — un PNG de esos, ya comprimido en el
// cliente, ronda unos cientos de KB.
app.use(express.json({ limit: '3mb' }));
app.use(morgan('dev'));

app.get('/api/health', (req, res) => {
  res.json({ estado: 'ok', fecha: new Date().toISOString() });
});

// Distinto de /api/health: este SÍ toca la base de datos (Azure SQL, oferta
// gratuita) con una consulta trivial. Pensado para que un ping externo
// periódico (ver .github/workflows/keep-alive.yml) evite que Render duerma
// el servicio Y que Azure pause la base de datos por inactividad — ninguno
// de los dos se puede desactivar directamente en el nivel gratuito.
app.get('/api/keep-alive', async (req, res) => {
  try {
    const pool = await getPool();
    await pool.request().query('SELECT 1 AS Ping');
    res.json({ estado: 'ok', bd: 'activa', fecha: new Date().toISOString() });
  } catch (err) {
    res
      .status(503)
      .json({ estado: 'error', bd: 'inactiva', mensaje: err.message });
  }
});

app.use('/api/auth', authRoutes);
app.use('/api/external', externalRoutes);
app.use('/api/clientes', clientesRoutes);
app.use('/api/pedidos', pedidosRoutes);
app.use('/api/productos', productosRoutes);
app.use('/api/configuraciones', configuracionesRoutes);
app.use('/api/notificaciones', notificacionesRoutes);
app.use('/api/tiendas', tiendasRoutes);
app.use('/api/trabajadores', trabajadoresRoutes);
app.use('/api/medios-pago', mediosPagoRoutes);
app.use('/api/solicitudes-pago', solicitudesPagoRoutes);
app.use('/api/roles', rolesRoutes);

app.use(notFoundHandler);
app.use(errorHandler);

const PORT = process.env.PORT || 4000;
app.listen(PORT, () => {
  console.log(`Servidor backend escuchando en el puerto ${PORT}`);
});
