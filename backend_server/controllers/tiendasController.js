const { sql, getPool } = require('../config/db');
const { inicioDeHoyPeru, inicioDeDiaPeru, PERU_OFFSET_MS } = require('../utils/fechaPeru');

function mapearTienda(fila) {
  return {
    idTienda: fila.IdTienda,
    nombre: fila.Nombre,
    slug: fila.Slug,
    disponible: Boolean(fila.Disponible),
  };
}

/**
 * Catálogo completo de tiendas (para el Hub "Elige tu tienda" y para que un
 * CLIENTE elija dónde hacer su pedido). Cualquier usuario autenticado puede
 * verlo — el filtrado de "a cuáles tiene acceso" para el personal es
 * `misTiendas`, no este.
 */
async function listarTiendas(req, res, next) {
  try {
    const pool = await getPool();
    const result = await pool
      .request()
      .query('SELECT IdTienda, Nombre, Slug, Disponible FROM Tiendas WHERE Estado = 1 ORDER BY IdTienda');
    return res.status(200).json({ tiendas: result.recordset.map(mapearTienda) });
  } catch (err) {
    return next(err);
  }
}

/**
 * Tiendas a las que el personal autenticado tiene acceso vigente
 * (TrabajadorTiendas.Estado = 1). SUPERADMIN ve todas las disponibles sin
 * necesitar filas propias — es el único rol con acceso global implícito.
 */
async function misTiendas(req, res, next) {
  try {
    const pool = await getPool();

    if (req.usuario.rol === 'SUPERADMIN') {
      const result = await pool
        .request()
        .query('SELECT IdTienda, Nombre, Slug, Disponible FROM Tiendas WHERE Estado = 1 ORDER BY IdTienda');
      return res.status(200).json({ tiendas: result.recordset.map(mapearTienda) });
    }

    const result = await pool
      .request()
      .input('IdPersona', sql.Int, req.usuario.idPersona)
      .query(`
        SELECT t.IdTienda, t.Nombre, t.Slug, t.Disponible
        FROM TrabajadorTiendas tt
        INNER JOIN Trabajadores trab ON trab.IdTrabajador = tt.IdTrabajador
        INNER JOIN Tiendas t ON t.IdTienda = tt.IdTienda
        WHERE trab.IdPersona = @IdPersona AND tt.Estado = 1 AND t.Estado = 1
        ORDER BY t.IdTienda
      `);

    return res.status(200).json({ tiendas: result.recordset.map(mapearTienda) });
  } catch (err) {
    return next(err);
  }
}

/**
 * Resumen/dashboard de una tienda puntual: cobrado y deuda del día
 * (seleccionable vía ?fecha=YYYY-MM-DD, hoy por defecto), pedidos por
 * estado, deuda total acumulada y pagos reportados — todo lo que el
 * personal necesita ver de un vistazo al entrar. El candado de acceso a
 * esa tienda específica lo aplica el middleware `autorizarTienda` en la
 * ruta.
 */
async function resumenTienda(req, res, next) {
  try {
    const idTienda = Number(req.params.idTienda);
    const inicioHoy = inicioDeHoyPeru();
    const finHoy = new Date(inicioHoy.getTime() + 24 * 60 * 60 * 1000);

    // El día que se está mostrando arriba (cobrado/deuda del día) puede ser
    // cualquiera con datos, no solo hoy — pero "pedidos por confirmar" y
    // "pendientes de entrega" (el backlog operativo) siempre miran el HOY
    // real, sin importar qué día se esté navegando arriba.
    const fechaQuery = typeof req.query.fecha === 'string' ? req.query.fecha : null;
    const inicioDia = fechaQuery ? inicioDeDiaPeru(fechaQuery) : inicioHoy;
    const finDia = new Date(inicioDia.getTime() + 24 * 60 * 60 * 1000);

    const pool = await getPool();

    const ventasDiaResult = await pool
      .request()
      .input('IdTienda', sql.Int, idTienda)
      .input('InicioDia', sql.DateTime2, inicioDia)
      .input('FinDia', sql.DateTime2, finDia)
      .query(`
        SELECT
          ISNULL(SUM(CASE WHEN EstadoPago = 'PAGADO' THEN 1 ELSE 0 END), 0) AS CobradoCantidad,
          ISNULL(SUM(CASE WHEN EstadoPago = 'PAGADO' THEN Total ELSE 0 END), 0) AS CobradoTotal,
          ISNULL(SUM(CASE WHEN EstadoPago = 'DEUDA' THEN 1 ELSE 0 END), 0) AS DeudaDiaCantidad,
          ISNULL(SUM(CASE WHEN EstadoPago = 'DEUDA' THEN Total ELSE 0 END), 0) AS DeudaDiaTotal
        FROM Pedidos
        WHERE IdTienda = @IdTienda AND Estado = 'ENTREGADO'
          AND FechaEntregaReal >= @InicioDia AND FechaEntregaReal < @FinDia
      `);

    const inicio7Dias = new Date(inicioHoy.getTime() - 6 * 24 * 60 * 60 * 1000);
    const ventas7DiasResult = await pool
      .request()
      .input('IdTienda', sql.Int, idTienda)
      .input('Inicio7Dias', sql.DateTime2, inicio7Dias)
      .input('FinHoy', sql.DateTime2, finHoy)
      .query(`
        SELECT CAST(DATEADD(HOUR, -5, FechaEntregaReal) AS DATE) AS DiaPeru,
               COUNT(*) AS Cantidad, SUM(Total) AS Total
        FROM Pedidos
        WHERE IdTienda = @IdTienda AND Estado = 'ENTREGADO'
          AND FechaEntregaReal >= @Inicio7Dias AND FechaEntregaReal < @FinHoy
        GROUP BY CAST(DATEADD(HOUR, -5, FechaEntregaReal) AS DATE)
      `);
    // Se rellenan los días sin ventas con 0 — el gráfico siempre debe
    // mostrar 7 barras, aunque algún día no se haya vendido nada.
    const ventasPorDia = new Map(
      ventas7DiasResult.recordset.map((f) => [
        f.DiaPeru.toISOString().slice(0, 10),
        { cantidad: f.Cantidad, total: Number(f.Total) },
      ]),
    );
    const ventasUltimos7Dias = [];
    for (let i = 6; i >= 0; i -= 1) {
      const dia = new Date(inicioHoy.getTime() - i * 24 * 60 * 60 * 1000);
      const clave = dia.toISOString().slice(0, 10);
      const datos = ventasPorDia.get(clave) ?? { cantidad: 0, total: 0 };
      ventasUltimos7Dias.push({ fecha: clave, cantidad: datos.cantidad, total: datos.total });
    }

    const porConfirmarResult = await pool
      .request()
      .input('IdTienda', sql.Int, idTienda)
      .query("SELECT COUNT(*) AS Cantidad FROM Pedidos WHERE IdTienda = @IdTienda AND Estado = 'SOLICITADO'");

    const pendientesResult = await pool
      .request()
      .input('IdTienda', sql.Int, idTienda)
      .input('InicioHoy', sql.DateTime2, inicioHoy)
      .input('FinHoy', sql.DateTime2, finHoy)
      .query(`
        SELECT
          COUNT(*) AS Total,
          ISNULL(SUM(CASE WHEN FechaEntrega IS NULL THEN 1 ELSE 0 END), 0) AS SinFecha,
          ISNULL(SUM(CASE WHEN FechaEntrega IS NOT NULL AND FechaEntrega < @InicioHoy THEN 1 ELSE 0 END), 0) AS Atrasados,
          ISNULL(SUM(CASE WHEN FechaEntrega >= @InicioHoy AND FechaEntrega < @FinHoy THEN 1 ELSE 0 END), 0) AS Hoy,
          ISNULL(SUM(CASE WHEN FechaEntrega >= @FinHoy THEN 1 ELSE 0 END), 0) AS Proximos
        FROM Pedidos
        WHERE IdTienda = @IdTienda AND Estado = 'PENDIENTE'
      `);

    const deudaResult = await pool
      .request()
      .input('IdTienda', sql.Int, idTienda)
      .query(`
        SELECT COUNT(*) AS Cantidad, ISNULL(SUM(Total), 0) AS Total
        FROM Pedidos
        WHERE IdTienda = @IdTienda AND Estado = 'ENTREGADO' AND EstadoPago = 'DEUDA'
      `);

    const pagosReportadosResult = await pool
      .request()
      .input('IdTienda', sql.Int, idTienda)
      .query(`
        SELECT COUNT(DISTINCT s.IdSolicitudPago) AS Cantidad
        FROM SolicitudesPago s
        INNER JOIN SolicitudPagoPedidos spp ON spp.IdSolicitudPago = s.IdSolicitudPago
        INNER JOIN Pedidos pd ON pd.IdPedido = spp.IdPedido
        WHERE pd.IdTienda = @IdTienda AND s.Estado IN ('GENERADO', 'REPORTADO')
      `);

    const pendientes = pendientesResult.recordset[0];
    const ventasDia = ventasDiaResult.recordset[0];
    const fechaDia = fechaQuery ?? new Date(inicioDia.getTime() + PERU_OFFSET_MS).toISOString().slice(0, 10);

    return res.status(200).json({
      fecha: fechaDia,
      cobradoDia: {
        cantidad: ventasDia.CobradoCantidad,
        total: ventasDia.CobradoTotal,
      },
      deudaDia: {
        cantidad: ventasDia.DeudaDiaCantidad,
        total: ventasDia.DeudaDiaTotal,
      },
      pedidosPorConfirmar: porConfirmarResult.recordset[0].Cantidad,
      pedidosPendientesEntrega: {
        total: pendientes.Total,
        sinFecha: pendientes.SinFecha,
        atrasados: pendientes.Atrasados,
        hoy: pendientes.Hoy,
        proximos: pendientes.Proximos,
      },
      deudaTotal: {
        cantidad: deudaResult.recordset[0].Cantidad,
        total: deudaResult.recordset[0].Total,
      },
      pagosReportados: pagosReportadosResult.recordset[0].Cantidad,
      ventasUltimos7Dias,
    });
  } catch (err) {
    return next(err);
  }
}

/**
 * Días (hora de Perú) que sí tienen al menos un pedido ENTREGADO en esta
 * tienda — para que el selector de fecha del Historial de ventas solo deje
 * elegir días con datos reales, en vez de mostrar un calendario en blanco.
 * También trae por separado los días que tienen alguna deuda TODAVÍA
 * pendiente (EstadoPago='DEUDA' — una vez saldada pasa a 'PAGADO' y ese día
 * deja de listarse acá), para marcarlos con un aro en el calendario.
 */
async function fechasConVentas(req, res, next) {
  try {
    const idTienda = Number(req.params.idTienda);
    const pool = await getPool();

    const result = await pool
      .request()
      .input('IdTienda', sql.Int, idTienda)
      .query(`
        SELECT DISTINCT CAST(DATEADD(HOUR, -5, FechaEntregaReal) AS DATE) AS Dia
        FROM Pedidos
        WHERE IdTienda = @IdTienda AND Estado = 'ENTREGADO'
        ORDER BY Dia DESC
      `);

    const conDeuda = await pool
      .request()
      .input('IdTienda', sql.Int, idTienda)
      .query(`
        SELECT DISTINCT CAST(DATEADD(HOUR, -5, FechaEntregaReal) AS DATE) AS Dia
        FROM Pedidos
        WHERE IdTienda = @IdTienda AND Estado = 'ENTREGADO' AND EstadoPago = 'DEUDA'
        ORDER BY Dia DESC
      `);

    return res.status(200).json({
      fechas: result.recordset.map((f) => f.Dia.toISOString().slice(0, 10)),
      fechasConDeuda: conDeuda.recordset.map((f) => f.Dia.toISOString().slice(0, 10)),
    });
  } catch (err) {
    return next(err);
  }
}

module.exports = { listarTiendas, misTiendas, resumenTienda, fechasConVentas };
