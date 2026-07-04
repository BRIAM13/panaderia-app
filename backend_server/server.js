require('dotenv').config();

const express = require('express');
const cors = require('cors');
const morgan = require('morgan');

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
app.use(express.json({ limit: '10kb' }));
app.use(morgan('dev'));

app.get('/api/health', (req, res) => {
  res.json({ estado: 'ok', fecha: new Date().toISOString() });
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
