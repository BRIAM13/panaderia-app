const app = require('./app');
const { iniciarCancelacionAutomatica } = require('./jobs/cancelarPedidosVencidos');

const PORT = process.env.PORT || 4000;
app.listen(PORT, () => {
  console.log(`Servidor backend escuchando en el puerto ${PORT}`);
  iniciarCancelacionAutomatica();
});
