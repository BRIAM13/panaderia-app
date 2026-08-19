const { sql, getPool } = require('../config/db');
const { registrarAuditoria } = require('../utils/auditLog');
const { notificarCliente, notificarPersonalTienda } = require('../controllers/pedidosController');

// Corre cada 5 minutos — el backend está despierto 24/7 gracias al ping
// externo de keep-alive-24-7.yml, así que un setInterval acá adentro es
// suficiente, sin necesitar un servicio de cron aparte en Render.
const INTERVALO_MS = 5 * 60 * 1000;

/**
 * Cancela solo los pedidos SOLICITADO (pan de agua/francés pedidos desde
 * la web, todavía sin que el personal los confirme) cuya hora de recojo ya
 * pasó — así el cliente no se queda esperando horas una respuesta sobre un
 * pedido que ya no tiene sentido preparar a la hora que pidió. Un pedido ya
 * CONFIRMADO (PENDIENTE) no se toca: si el personal ya lo aceptó, cualquier
 * ajuste de hora lo coordina directamente con el cliente.
 */
async function cancelarPedidosVencidos() {
  const pool = await getPool();
  const vencidos = await pool.request().query(`
    SELECT IdPedido, IdCliente, IdTienda, NumeroPedidoDia
    FROM Pedidos
    WHERE Estado = 'SOLICITADO' AND FechaEntrega IS NOT NULL AND FechaEntrega < SYSUTCDATETIME()
  `);

  for (const pedido of vencidos.recordset) {
    await pool.request()
      .input('IdPedido', sql.Int, pedido.IdPedido)
      .query(`
        UPDATE Pedidos
        SET Estado = 'CANCELADO', FechaCancelacion = SYSUTCDATETIME()
        WHERE IdPedido = @IdPedido
      `);

    await registrarAuditoria({
      idUsuario: null,
      accion: 'CANCELAR_PEDIDO_VENCIDO',
      tablaAfectada: 'Pedidos',
      registroAfectadoId: String(pedido.IdPedido),
      userAgent: 'sistema:cancelarPedidosVencidos',
    });

    await notificarCliente({
      idCliente: pedido.IdCliente,
      titulo: 'Tu pedido fue cancelado',
      cuerpo: `Tu pedido #${pedido.NumeroPedidoDia} se canceló porque no llegamos a confirmarlo antes de la hora de recojo que elegiste.`,
      datos: { tipo: 'PEDIDO_CANCELADO', idPedido: String(pedido.IdPedido) },
    });
    // Silencioso a propósito, mismo criterio que cancelarPedido en
    // pedidosController.js: solo refresca la pantalla de otros
    // dispositivos del personal, sin bombardearlos de notificaciones.
    await notificarPersonalTienda({
      idTienda: pedido.IdTienda,
      datos: { tipo: 'PEDIDO_CANCELADO', idTienda: String(pedido.IdTienda), idPedido: String(pedido.IdPedido) },
    });
  }

  return vencidos.recordset.length;
}

function iniciarCancelacionAutomatica() {
  setInterval(() => {
    cancelarPedidosVencidos().catch((err) => {
      console.error('Error cancelando pedidos vencidos:', err.message);
    });
  }, INTERVALO_MS);
}

module.exports = { cancelarPedidosVencidos, iniciarCancelacionAutomatica };
