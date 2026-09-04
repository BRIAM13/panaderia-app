const { sql, getPool } = require('../config/db');

/**
 * Puente entre el backend Node de producción y el microservicio Python de
 * predicción de demanda (ver `ml_service/`, entrenado y validado con datos
 * SINTÉTICOS — nunca toca esta base de datos). Este archivo es el único
 * lugar del backend que sabe que ese servicio existe.
 *
 * `ML_SERVICE_URL` no está configurada todavía en producción (el
 * microservicio vive listo en el repo pero aún no se desplegó en ningún
 * servidor — eso es un paso de infraestructura aparte). Mientras tanto,
 * este endpoint responde 503 de forma clara en vez de fallar silencioso o
 * inventar un número.
 */
const TIEMPO_ESPERA_MS = 10000;

/**
 * Últimos N días de demanda REAL entregada para una tienda+producto, en el
 * formato que espera `contextoReciente` del microservicio ([{fecha,
 * cantidad}]). Se agrupa por día porque puede haber varios pedidos
 * entregados el mismo día. Solo cuenta ENTREGADO — un pedido rechazado o
 * cancelado nunca fue demanda real satisfecha.
 *
 * La cantidad sale de `PedidoItems`, no de `Pedidos`: desde que un pedido
 * puede tener varios productos, la cantidad de ESTE producto es la de sus
 * líneas. Un pedido con pan francés y pan de agua ya no aporta su total
 * entero a los dos.
 */
async function obtenerContextoReciente(idTienda, idProducto, dias = 30) {
  const pool = await getPool();
  const resultado = await pool
    .request()
    .input('IdTienda', sql.Int, idTienda)
    .input('IdProducto', sql.Int, idProducto)
    .input('Dias', sql.Int, dias)
    .query(`
      SELECT
        DATE(COALESCE(pd.FechaEntregaReal, pd.FechaCreacion)) AS Fecha,
        SUM(pi.Cantidad) AS Cantidad
      FROM Pedidos pd
      INNER JOIN PedidoItems pi ON pi.IdPedido = pd.IdPedido
      WHERE pd.IdTienda = @IdTienda
        AND pi.IdProducto = @IdProducto
        AND pd.Estado = 'ENTREGADO'
        AND COALESCE(pd.FechaEntregaReal, pd.FechaCreacion) >= DATE_SUB(CURDATE(), INTERVAL @Dias DAY)
      GROUP BY DATE(COALESCE(pd.FechaEntregaReal, pd.FechaCreacion))
      ORDER BY Fecha
    `);
  return resultado.recordset.map((fila) => ({
    fecha: fila.Fecha,
    cantidad: Number(fila.Cantidad),
  }));
}

/**
 * GET /api/prediccion-demanda/:idTienda/:idProducto?fechas=2026-09-05,2026-09-06
 * Exclusivo ADMIN/SUPERADMIN (ver prediccionDemandaRoutes.js) — es una
 * herramienta de planificación de compra/producción, no algo operativo del
 * día a día del personal de piso.
 */
async function predecirDemanda(req, res, next) {
  const urlServicio = process.env.ML_SERVICE_URL;
  if (!urlServicio) {
    return res.status(503).json({
      mensaje: 'El servicio de predicción de demanda todavía no está desplegado. Ver ml_service/README.md.',
    });
  }

  const idTienda = Number(req.params.idTienda);
  const idProducto = Number(req.params.idProducto);
  const fechasTexto = String(req.query.fechas || '').trim();

  if (!Number.isInteger(idTienda) || !Number.isInteger(idProducto) || !fechasTexto) {
    return res.status(400).json({ mensaje: 'idTienda, idProducto y al menos una fecha son obligatorios.' });
  }
  const fechas = fechasTexto.split(',').map((f) => f.trim()).filter(Boolean);

  try {
    // El contexto reciente es una mejora opcional: si la consulta a la BD
    // falla o no hay suficiente historial, se sigue pidiendo la predicción
    // base sin bloquear al usuario por eso.
    let contextoReciente = [];
    try {
      contextoReciente = await obtenerContextoReciente(idTienda, idProducto);
    } catch (_) {
      contextoReciente = [];
    }

    const controlador = new AbortController();
    const timeoutId = setTimeout(() => controlador.abort(), TIEMPO_ESPERA_MS);
    let respuestaServicio;
    try {
      respuestaServicio = await fetch(`${urlServicio}/predecir`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          idTienda,
          idProducto,
          fechas,
          ...(contextoReciente.length >= 3 ? { contextoReciente } : {}),
        }),
        signal: controlador.signal,
      });
    } finally {
      clearTimeout(timeoutId);
    }

    const datos = await respuestaServicio.json().catch(() => null);
    if (!respuestaServicio.ok) {
      return res.status(respuestaServicio.status).json(
        datos || { mensaje: 'El servicio de predicción respondió con un error.' }
      );
    }

    return res.status(200).json(datos);
  } catch (err) {
    // No se pudo ni siquiera contactar al servicio (caído, URL mal
    // configurada, timeout) — 503, no 500: no es un bug de este backend.
    if (err.name === 'AbortError') {
      return res.status(503).json({ mensaje: 'El servicio de predicción tardó demasiado en responder.' });
    }
    return res.status(503).json({ mensaje: 'No se pudo conectar con el servicio de predicción de demanda.' });
  }
}

module.exports = { predecirDemanda, obtenerContextoReciente };
