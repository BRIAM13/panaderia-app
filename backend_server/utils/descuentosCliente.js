const { sql } = require('../config/db');
const { calcularSegmento, obtenerConfiguracionesCrm } = require('../controllers/clientesController');

// Descuento por fidelidad, atado al SEGMENTO del CRM que ya calcula
// clientesController (NUEVO/EN_RIESGO/VIP/FRECUENTE/REGULAR) — no a los
// puntos ni al número de pedidos por separado: el segmento ya resume eso y
// es el mismo criterio que ve el personal en la ficha del cliente, así que
// el descuento nunca puede contradecir lo que dice el CRM.
//
// Mismo patrón que PRECIO_PAQUETE/horariosPanaderia.js: las 6 claves se
// leen de la BD EN CADA CONSULTA (nada de caché en memoria), así el dueño
// cambia un porcentaje desde la app y el siguiente pedido de la página web
// ya lo usa, sin redeploy y sin ningún paso de sincronización.
const CLAVE_DESCUENTO_NUEVO = 'DESCUENTO_SEGMENTO_NUEVO';
const CLAVE_DESCUENTO_REGULAR = 'DESCUENTO_SEGMENTO_REGULAR';
const CLAVE_DESCUENTO_EN_RIESGO = 'DESCUENTO_SEGMENTO_EN_RIESGO';
const CLAVE_DESCUENTO_FRECUENTE = 'DESCUENTO_SEGMENTO_FRECUENTE';
const CLAVE_DESCUENTO_VIP = 'DESCUENTO_SEGMENTO_VIP';
// Lista separada por comas de `Tiendas.Slug` donde este descuento está
// activo. El pan de hamburguesa es un negocio aparte según el dueño y NO
// debe tener este descuento mientras no lo habilite a mano, así que la
// lista es la única fuente de verdad y no hay ningún slug hardcodeado acá.
const CLAVE_TIENDAS_HABILITADAS = 'DESCUENTOS_TIENDAS_HABILITADAS';

// Los mismos valores que siembra scripts/seed_descuentos_clientes.js: si
// una clave todavía no existe en Configuraciones (base sin sembrar), el
// pedido no se cae — cae a este valor. NUEVO nunca es 0: el acuerdo con el
// dueño es que hasta el cliente que pide por primera vez recibe algo.
const PORCENTAJES_POR_DEFECTO = {
  NUEVO: 5,
  REGULAR: 5,
  EN_RIESGO: 5,
  FRECUENTE: 10,
  VIP: 15,
};

// A diferencia de los porcentajes, la lista de tiendas SÍ falla cerrada: si
// la clave falta o quedó vacía, no se descuenta en ninguna tienda. Un
// descuento de más aplicado por accidente es plata que ya salió; uno de
// menos se corrige habilitando la tienda desde la app.
const TIENDAS_HABILITADAS_POR_DEFECTO = '';

/**
 * "panaderia, horneados" -> Set { 'panaderia', 'horneados' }. Tolera
 * espacios sueltos y comas de más (el valor se edita a mano desde la app),
 * y descarta lo vacío: "panaderia," no habilita una tienda sin nombre.
 */
function parsearTiendasHabilitadas(valor) {
  return new Set(
    String(valor || '')
      .split(',')
      .map((slug) => slug.trim())
      .filter((slug) => slug.length > 0),
  );
}

/**
 * Porcentaje que le toca a un segmento. Un segmento desconocido (o null)
 * devuelve 0 en vez de reventar: si algún día se agrega un segmento nuevo
 * en clientesController y nadie se acuerda de sembrar su clave acá, el
 * pedido se cobra completo — nunca se regala un descuento por descuido.
 */
function porcentajeDeSegmento(porcentajePorSegmento, segmento) {
  const porcentaje = Number(porcentajePorSegmento[segmento]);
  return Number.isFinite(porcentaje) && porcentaje > 0 ? porcentaje : 0;
}

/**
 * Total ya descontado, redondeado a 2 decimales — es lo que de verdad le
 * cobramos al cliente y lo que se guarda en `Pedidos.Total`.
 */
function aplicarDescuento(subtotal, porcentaje) {
  if (!porcentaje) return Number(Number(subtotal).toFixed(2));
  return Number((Number(subtotal) * (1 - porcentaje / 100)).toFixed(2));
}

/**
 * Las 6 claves de Configuraciones en una sola consulta. Sin caché a
 * propósito (ver el comentario del encabezado): cada llamada vuelve a leer
 * la base, así un cambio hecho desde la app aplica en la petición
 * siguiente.
 */
async function obtenerConfiguracionDescuentos(pool) {
  const result = await pool.request().query(`
    SELECT Clave, Valor FROM Configuraciones
    WHERE Clave IN (
      '${CLAVE_DESCUENTO_NUEVO}', '${CLAVE_DESCUENTO_REGULAR}', '${CLAVE_DESCUENTO_EN_RIESGO}',
      '${CLAVE_DESCUENTO_FRECUENTE}', '${CLAVE_DESCUENTO_VIP}', '${CLAVE_TIENDAS_HABILITADAS}'
    )
  `);
  const mapa = Object.fromEntries(result.recordset.map((r) => [r.Clave, r.Valor]));

  const numero = (clave, porDefecto) => {
    const valor = Number(mapa[clave]);
    return Number.isFinite(valor) && valor >= 0 ? valor : porDefecto;
  };

  return {
    porcentajePorSegmento: {
      NUEVO: numero(CLAVE_DESCUENTO_NUEVO, PORCENTAJES_POR_DEFECTO.NUEVO),
      REGULAR: numero(CLAVE_DESCUENTO_REGULAR, PORCENTAJES_POR_DEFECTO.REGULAR),
      EN_RIESGO: numero(CLAVE_DESCUENTO_EN_RIESGO, PORCENTAJES_POR_DEFECTO.EN_RIESGO),
      FRECUENTE: numero(CLAVE_DESCUENTO_FRECUENTE, PORCENTAJES_POR_DEFECTO.FRECUENTE),
      VIP: numero(CLAVE_DESCUENTO_VIP, PORCENTAJES_POR_DEFECTO.VIP),
    },
    tiendasHabilitadas: parsearTiendasHabilitadas(
      mapa[CLAVE_TIENDAS_HABILITADAS] ?? TIENDAS_HABILITADAS_POR_DEFECTO,
    ),
  };
}

/**
 * Historial agregado del cliente con el MISMO criterio de "compra real" que
 * usa el CRM en `obtenerPerfilCliente` (solo pedidos ENTREGADO; ni
 * rechazados ni pendientes inflan el historial). Si `idCliente` es null
 * —una persona que todavía no existe en la base— ni se consulta: no hay
 * historial que buscar y el segmento es NUEVO por definición.
 */
async function obtenerHistorialCliente(pool, idCliente) {
  if (idCliente === null || idCliente === undefined) {
    return { pedidosEntregados: 0, totalGastado: 0, diasDesdeUltimaCompra: null };
  }

  const result = await pool
    .request()
    .input('IdCliente', sql.Int, idCliente)
    .query(`
      SELECT
        SUM(CASE WHEN Estado = 'ENTREGADO' THEN 1 ELSE 0 END) AS PedidosEntregados,
        COALESCE(SUM(CASE WHEN Estado = 'ENTREGADO' THEN Total ELSE 0 END), 0) AS TotalGastado,
        MAX(CASE WHEN Estado = 'ENTREGADO' THEN COALESCE(FechaEntregaReal, FechaCreacion) END) AS UltimaCompra
      FROM Pedidos
      WHERE IdCliente = @IdCliente
    `);

  // Un agregado sin GROUP BY siempre devuelve una fila, con NULLs si el
  // cliente no tiene ni un pedido — de ahí los `|| 0`.
  const agregado = result.recordset[0] || {};
  const ultimaCompra = agregado.UltimaCompra ? new Date(agregado.UltimaCompra) : null;

  return {
    pedidosEntregados: Number(agregado.PedidosEntregados) || 0,
    totalGastado: Number(agregado.TotalGastado) || 0,
    diasDesdeUltimaCompra: ultimaCompra
      ? Math.floor((Date.now() - ultimaCompra.getTime()) / 86400000)
      : null,
  };
}

/**
 * Descuento que le corresponde a un cliente en una tienda concreta.
 *
 * `aplica:false` (porcentaje 0) cuando la tienda no está en la lista
 * habilitada — ese es el único portón; adentro, TODOS los segmentos
 * descuentan algo, incluido NUEVO (decisión del dueño: quien pide por
 * primera vez también se lleva su descuento).
 *
 * `idCliente` puede ser null/undefined: es el caso del visitante que
 * todavía no existe como cliente en la base y solo está escribiendo su DNI
 * en el formulario público. Se trata como historial vacío -> NUEVO.
 */
async function calcularDescuentoCliente({ pool, idCliente, tiendaSlug }) {
  const config = await obtenerConfiguracionDescuentos(pool);

  const slug = typeof tiendaSlug === 'string' ? tiendaSlug.trim() : '';
  if (!slug || !config.tiendasHabilitadas.has(slug)) {
    return { aplica: false, segmento: null, porcentaje: 0 };
  }

  const configCrm = await obtenerConfiguracionesCrm(pool);
  const historial = await obtenerHistorialCliente(pool, idCliente);
  const segmento = calcularSegmento(historial, configCrm);

  return {
    aplica: true,
    segmento,
    porcentaje: porcentajeDeSegmento(config.porcentajePorSegmento, segmento),
  };
}

module.exports = {
  CLAVE_DESCUENTO_NUEVO,
  CLAVE_DESCUENTO_REGULAR,
  CLAVE_DESCUENTO_EN_RIESGO,
  CLAVE_DESCUENTO_FRECUENTE,
  CLAVE_DESCUENTO_VIP,
  CLAVE_TIENDAS_HABILITADAS,
  PORCENTAJES_POR_DEFECTO,
  parsearTiendasHabilitadas,
  porcentajeDeSegmento,
  aplicarDescuento,
  obtenerConfiguracionDescuentos,
  calcularDescuentoCliente,
};
