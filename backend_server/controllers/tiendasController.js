const { sql, getPool } = require('../config/db');
const {
  inicioDeHoyPeru,
  inicioDeDiaPeru,
  inicioDeMesPeru,
  inicioDeMesAnteriorPeru,
  inicioDeSemanaPeru,
  PERU_OFFSET_MS,
} = require('../utils/fechaPeru');

/**
 * Las 24 horas del día, con `{ hora, cantidad, total }` en cada una — las
 * horas sin ninguna venta quedan en 0 en vez de faltar, para que el gráfico
 * siempre dibuje el día completo y no una silueta con huecos (mismo criterio
 * que el relleno de los 7 días en `resumenTienda`).
 *
 * Función pura a propósito: es la única parte de la métrica "ventas por
 * hora" que tiene lógica real, así que se puede probar sin base de datos
 * (ver __tests__/tiendasController.test.js).
 */
function rellenarVentasPorHora(filas) {
  const porHora = new Map(
    (filas ?? []).map((f) => [Number(f.Hora), { cantidad: Number(f.Cantidad) || 0, total: Number(f.Total) || 0 }]),
  );
  const serie = [];
  for (let hora = 0; hora < 24; hora += 1) {
    const datos = porHora.get(hora) ?? { cantidad: 0, total: 0 };
    serie.push({ hora, cantidad: datos.cantidad, total: datos.total });
  }
  return serie;
}

/**
 * Variación porcentual del mes actual contra el MISMO TRAMO del mes anterior
 * (los mismos días transcurridos), no contra el mes anterior completo —
 * comparar 5 días de setiembre contra los 30 de agosto siempre daría una
 * caída inventada.
 *
 * `null` (no 0, ni -100%) cuando el tramo anterior no vendió nada: no hay
 * contra qué comparar, y la UI lo muestra como "sin datos" en vez de fingir
 * una cifra.
 */
function calcularVariacionMensual({ totalMesActual, totalMesAnteriorMismoTramo }) {
  if (!totalMesAnteriorMismoTramo || totalMesAnteriorMismoTramo <= 0) return null;
  return ((totalMesActual - totalMesAnteriorMismoTramo) / totalMesAnteriorMismoTramo) * 100;
}

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

    // ---- Ventas por hora del día navegado ----------------------------
    // Sigue el mismo día que las tarjetas de arriba (?fecha=YYYY-MM-DD, hoy
    // por defecto): es el detalle de ESE día, no del hoy real. La hora se
    // agrupa en hora de Perú (DATEADD -5), no UTC — si no, un pedido
    // entregado a las 8pm de Perú caería en la 1am del día siguiente.
    const ventasPorHoraResult = await pool
      .request()
      .input('IdTienda', sql.Int, idTienda)
      .input('InicioDia', sql.DateTime2, inicioDia)
      .input('FinDia', sql.DateTime2, finDia)
      .query(`
        SELECT HOUR(DATEADD(HOUR, -5, FechaEntregaReal)) AS Hora, COUNT(*) AS Cantidad, SUM(Total) AS Total
        FROM Pedidos
        WHERE IdTienda = @IdTienda AND Estado = 'ENTREGADO'
          AND FechaEntregaReal >= @InicioDia AND FechaEntregaReal < @FinDia
        GROUP BY HOUR(DATEADD(HOUR, -5, FechaEntregaReal))
      `);
    const ventasPorHora = rellenarVentasPorHora(ventasPorHoraResult.recordset);

    // ---- Comparativo mes a mes ---------------------------------------
    // SIEMPRE el mes calendario real actual, sin importar qué día se esté
    // navegando arriba: es una métrica de tendencia del negocio, no del día
    // mostrado — si saltara con el selector de fecha, "este mes" querría
    // decir una cosa distinta en cada pantallazo.
    const inicioMesActual = inicioDeMesPeru();
    const inicioMesAnterior = inicioDeMesAnteriorPeru();
    // El mismo número de días/horas transcurridos, aplicado al mes anterior
    // — así se compara "lo que va del mes" contra "lo que iba del mes
    // pasado a esta misma altura".
    const finTramoMesAnterior = new Date(inicioMesAnterior.getTime() + (Date.now() - inicioMesActual.getTime()));

    const comparativoResult = await pool
      .request()
      .input('IdTienda', sql.Int, idTienda)
      .input('InicioMesActual', sql.DateTime2, inicioMesActual)
      .input('InicioMesAnterior', sql.DateTime2, inicioMesAnterior)
      .input('FinTramoMesAnterior', sql.DateTime2, finTramoMesAnterior)
      .query(`
        SELECT
          ISNULL(SUM(CASE WHEN FechaEntregaReal >= @InicioMesActual THEN Total ELSE 0 END), 0) AS TotalMesActual,
          ISNULL(SUM(CASE WHEN FechaEntregaReal >= @InicioMesActual THEN 1 ELSE 0 END), 0) AS PedidosMesActual,
          ISNULL(SUM(CASE WHEN FechaEntregaReal >= @InicioMesAnterior AND FechaEntregaReal < @InicioMesActual THEN Total ELSE 0 END), 0) AS TotalMesAnteriorCompleto,
          ISNULL(SUM(CASE WHEN FechaEntregaReal >= @InicioMesAnterior AND FechaEntregaReal < @InicioMesActual THEN 1 ELSE 0 END), 0) AS PedidosMesAnteriorCompleto,
          ISNULL(SUM(CASE WHEN FechaEntregaReal >= @InicioMesAnterior AND FechaEntregaReal < @FinTramoMesAnterior THEN Total ELSE 0 END), 0) AS TotalMesAnteriorMismoTramo,
          ISNULL(SUM(CASE WHEN FechaEntregaReal >= @InicioMesAnterior AND FechaEntregaReal < @FinTramoMesAnterior THEN 1 ELSE 0 END), 0) AS PedidosMesAnteriorMismoTramo
        FROM Pedidos
        WHERE IdTienda = @IdTienda AND Estado = 'ENTREGADO' AND FechaEntregaReal >= @InicioMesAnterior
      `);
    const comparativo = comparativoResult.recordset[0];

    // ---- Clientes nuevos de la semana (GLOBAL, no por tienda) ---------
    // `Clientes` no tiene IdTienda — un cliente compra en cualquiera de las
    // tiendas del negocio, así que este número es de todo el negocio. La UI
    // lo rotula explícitamente para que nadie lo lea como "clientes nuevos
    // de ESTA tienda".
    const inicioSemana = inicioDeSemanaPeru();
    const clientesNuevosResult = await pool
      .request()
      .input('InicioSemana', sql.DateTime2, inicioSemana)
      .query(`
        SELECT COUNT(*) AS Cantidad
        FROM Clientes
        WHERE Estado = 1 AND FechaRegistroCliente >= @InicioSemana
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
      ventasPorHora,
      comparativoMensual: {
        mesActual: {
          total: Number(comparativo.TotalMesActual),
          pedidos: Number(comparativo.PedidosMesActual),
        },
        mesAnteriorCompleto: {
          total: Number(comparativo.TotalMesAnteriorCompleto),
          pedidos: Number(comparativo.PedidosMesAnteriorCompleto),
        },
        mesAnteriorMismoTramo: {
          total: Number(comparativo.TotalMesAnteriorMismoTramo),
          pedidos: Number(comparativo.PedidosMesAnteriorMismoTramo),
        },
        variacionPorcentual: calcularVariacionMensual({
          totalMesActual: Number(comparativo.TotalMesActual),
          totalMesAnteriorMismoTramo: Number(comparativo.TotalMesAnteriorMismoTramo),
        }),
      },
      clientesNuevosSemana: {
        cantidad: clientesNuevosResult.recordset[0].Cantidad,
        inicioSemana: new Date(inicioSemana.getTime() + PERU_OFFSET_MS).toISOString().slice(0, 10),
        // Siempre true: `Clientes` no tiene tienda. Va explícito en la
        // respuesta para que la UI lo rotule sin tener que "saberlo".
        esGlobal: true,
      },
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

// Mismas tiendas que SLUGS_AUTOSERVICIO en pedidosController.js: catálogo
// simple de producto+cantidad, a diferencia de Horneados (campos propios,
// sin catálogo de precio fijo).
const SLUGS_CATALOGO_SIMPLE = ['hamburguesas', 'panaderia'];

/**
 * Catálogo de una tienda puntual para que el personal registre un pedido
 * (`NuevoPedidoPage`) — mismo shape que el catálogo público de la página web
 * (`listarCatalogoPublico` en publicoController.js), pero autenticado y
 * acotado a UNA tienda. El candado de acceso a esa tienda lo aplica
 * `autorizarTienda` en la ruta.
 */
async function listarProductosTienda(req, res, next) {
  try {
    const idTienda = Number(req.params.idTienda);
    const pool = await getPool();

    const tiendaResult = await pool
      .request()
      .input('IdTienda', sql.Int, idTienda)
      .query('SELECT Slug FROM Tiendas WHERE IdTienda = @IdTienda AND Estado = 1');
    if (tiendaResult.recordset.length === 0 || !SLUGS_CATALOGO_SIMPLE.includes(tiendaResult.recordset[0].Slug)) {
      return res.status(400).json({ mensaje: 'Esta tienda no tiene catálogo de autoservicio.' });
    }
    const slug = tiendaResult.recordset[0].Slug;

    const result = await pool
      .request()
      .input('IdTienda', sql.Int, idTienda)
      .query(`
        SELECT p.IdProducto, p.Nombre, p.PrecioUnitario
        FROM Productos p
        INNER JOIN Categorias c ON c.IdCategoria = p.IdCategoria
        WHERE c.IdTienda = @IdTienda AND p.Estado = 1
        ORDER BY p.IdProducto
      `);

    // El pan de hamburguesa se vende por paquete de 12 a precio fijo (el
    // mismo que ve el cliente en autoservicio), no por unidad suelta como el
    // resto del catálogo — ver misma lógica en listarCatalogoPublico.
    const esPaquete = slug === 'hamburguesas';
    let precioPaquete = null;
    if (esPaquete) {
      const config = await pool.request().query("SELECT Valor FROM Configuraciones WHERE Clave = 'PRECIO_PAQUETE'");
      precioPaquete = config.recordset.length > 0 ? Number(config.recordset[0].Valor) : null;
    }

    return res.status(200).json({
      productos: result.recordset.map((p) => ({
        idProducto: p.IdProducto,
        nombre: p.Nombre,
        precioUnitario: esPaquete && precioPaquete != null ? precioPaquete : p.PrecioUnitario,
        esPaquete,
      })),
    });
  } catch (err) {
    return next(err);
  }
}

/**
 * Cambia el precio por unidad de UN producto de una tienda de catálogo
 * simple (ej. Pan de Agua en Panadería) — usado por la pantalla "Ajustar
 * precios". Restringido a ADMIN/SUPERADMIN en la ruta, además del candado
 * de acceso a la tienda (`autorizarTienda`). El precio nuevo solo aplica
 * hacia adelante — no toca pedidos ya registrados (mismo criterio que
 * `AjusteCostosPage`, que edita el precio de PAQUETE de Hamburguesas).
 */
async function actualizarPrecioProducto(req, res, next) {
  try {
    const idTienda = Number(req.params.idTienda);
    const idProducto = Number(req.params.idProducto);
    const { precioUnitario } = req.body;

    if (typeof precioUnitario !== 'number' || !Number.isFinite(precioUnitario) || precioUnitario <= 0) {
      return res.status(400).json({ mensaje: 'El precio debe ser un número mayor a 0.' });
    }

    const pool = await getPool();

    const tiendaResult = await pool
      .request()
      .input('IdTienda', sql.Int, idTienda)
      .query('SELECT Slug FROM Tiendas WHERE IdTienda = @IdTienda AND Estado = 1');
    if (tiendaResult.recordset.length === 0 || !SLUGS_CATALOGO_SIMPLE.includes(tiendaResult.recordset[0].Slug)) {
      return res.status(400).json({ mensaje: 'Esta tienda no tiene catálogo de autoservicio.' });
    }

    const productoResult = await pool
      .request()
      .input('IdProducto', sql.Int, idProducto)
      .input('IdTienda', sql.Int, idTienda)
      .query(`
        SELECT p.IdProducto
        FROM Productos p
        INNER JOIN Categorias c ON c.IdCategoria = p.IdCategoria
        WHERE p.IdProducto = @IdProducto AND c.IdTienda = @IdTienda AND p.Estado = 1
      `);
    if (productoResult.recordset.length === 0) {
      return res.status(404).json({ mensaje: 'Ese producto no pertenece a esta tienda.' });
    }

    const precioFinal = Number(precioUnitario.toFixed(2));
    await pool
      .request()
      .input('IdProducto', sql.Int, idProducto)
      .input('PrecioUnitario', sql.Decimal(10, 2), precioFinal)
      .query('UPDATE Productos SET PrecioUnitario = @PrecioUnitario WHERE IdProducto = @IdProducto');

    return res.status(200).json({ mensaje: 'Precio actualizado', precioUnitario: precioFinal });
  } catch (err) {
    return next(err);
  }
}

module.exports = {
  listarTiendas,
  misTiendas,
  resumenTienda,
  fechasConVentas,
  listarProductosTienda,
  actualizarPrecioProducto,
  // Exportadas para poder probarlas como funciones puras, sin base de datos
  // (mismo criterio que resumirSegmentosClientes en clientesController.js).
  rellenarVentasPorHora,
  calcularVariacionMensual,
};
