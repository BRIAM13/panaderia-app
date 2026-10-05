// Delivery del pedido web de PANADERÍA, solo dentro de Pisco.
//
// Pedido del dueño (2026-10-05): "Quiero agregar el servicio de delivery
// solo para Pisco, por 4 soles." Decisiones ya tomadas con él:
//
//   1. Solo Panadería (pan de agua / pan francés, por unidad). El pan de
//      hamburguesa (por paquete) sigue siendo solo para recoger en tienda.
//   2. Si el pin cae fuera del radio de Pisco, el delivery se BLOQUEA — la
//      página le ofrece al cliente pedir igual para recoger, pero eso lo
//      decide él; el servidor nunca convierte un DELIVERY en RECOJO solo.
//   3. Se pide pin en el mapa + dirección escrita + referencia (el GPS de
//      una laptop puede errar por cuadras; la dirección escrita es lo que
//      de verdad usa el repartidor).
//
// Mismo reparto que `pagoAdelanto.js` y `descuentosCliente.js`: toda la
// CUENTA es pura (distancia, zona, validación) y se prueba sin levantar
// nada. Lo único que toca la base es leer la configuración editable
// (`Configuraciones`), SIN caché, para que un cambio del dueño desde la app
// aplique en el pedido siguiente sin redeploy.
//
// ⚠️ A propósito SIN `require('../config/db')`: ese módulo crea el pool de
//    mysql2 al importarse, y este archivo lo importan las pruebas puras
//    (`__tests__/delivery.test.js`). El `pool` llega por parámetro y los
//    `.input()` usan la forma de dos argumentos (nombre, valor), que la capa
//    de compatibilidad soporta igual (ver `pagoAdelanto.js`).
//
// Ver `database_migrations/2026_10_delivery_panaderia.sql` por las columnas
// nuevas de `Pedidos` y las claves de `Configuraciones`.

/** Los 2 valores de `Pedidos.TipoEntrega` (CK_Pedidos_TipoEntrega). VARCHAR
 * con lista cerrada y NO un BIT "EsDelivery": ver el bug de BIT-como-Buffer
 * del 2026-09-29 en `pagoAdelanto.js` (`bitAVerdadero`). */
const TIPO_ENTREGA_RECOJO = 'RECOJO';
const TIPO_ENTREGA_DELIVERY = 'DELIVERY';
const TIPOS_ENTREGA = [TIPO_ENTREGA_RECOJO, TIPO_ENTREGA_DELIVERY];

/** Tiendas donde se ofrece delivery. Decisión de ARQUITECTURA, no operativa
 * (igual que `SLUGS_PAGO_ADELANTO`): el pan de hamburguesa no entra. */
const SLUGS_DELIVERY = ['panaderia'];

/** Claves de `Configuraciones` — editables desde la app, sin redeploy. */
const CLAVE_COSTO_DELIVERY = 'COSTO_DELIVERY_PANADERIA';
const CLAVE_LATITUD_CENTRO = 'DELIVERY_LATITUD_CENTRO';
const CLAVE_LONGITUD_CENTRO = 'DELIVERY_LONGITUD_CENTRO';
const CLAVE_RADIO_KM = 'DELIVERY_RADIO_KM';

/**
 * Valores por defecto si una clave no existe o la consulta falla. Nunca se
 * tira el pedido abajo por la configuración.
 *
 * El centro por defecto es la ubicación REAL de la panadería, confirmada
 * por el dueño el 2026-10-05 — los mismos números que siembra
 * `scripts/seed_delivery.js` en `DELIVERY_LATITUD_CENTRO` /
 * `DELIVERY_LONGITUD_CENTRO`. Este default solo se usa si esas claves
 * faltan o la consulta falla; el valor que manda es el de `Configuraciones`.
 */
const COSTO_DELIVERY_POR_DEFECTO = 4;
const LATITUD_CENTRO_POR_DEFECTO = -13.706622640097475;
const LONGITUD_CENTRO_POR_DEFECTO = -76.20123704674447;
const RADIO_KM_POR_DEFECTO = 8;

/** Radio medio de la Tierra en km (IUGG), el usado habitualmente con Haversine. */
const RADIO_TIERRA_KM = 6371;

/** Largos de la dirección escrita (+ referencia). La columna es VARCHAR(300). */
const LARGO_MINIMO_DIRECCION = 8;
const LARGO_MAXIMO_DIRECCION = 300;

function aRadianes(grados) {
  return (grados * Math.PI) / 180;
}

/**
 * Distancia en km entre dos puntos (lat/lon en grados decimales), por la
 * fórmula de Haversine sobre una esfera de radio [RADIO_TIERRA_KM]:
 *
 *   a = sin²(Δφ/2) + cos φ1 · cos φ2 · sin²(Δλ/2)
 *   d = 2R · asin(√a)
 *
 * El error frente al elipsoide real es < 0.5%, irrelevante para decidir si
 * una casa está a 7 u 9 km de la panadería. Devuelve NaN si algún valor no
 * es numérico (quien llama ya validó; NaN falla toda comparación, así que
 * nunca "cae dentro de la zona" por accidente).
 */
function distanciaKm(lat1, lon1, lat2, lon2) {
  const [a1, o1, a2, o2] = [lat1, lon1, lat2, lon2].map(Number);
  const dLat = aRadianes(a2 - a1);
  const dLon = aRadianes(o2 - o1);
  const h =
    Math.sin(dLat / 2) ** 2 + Math.cos(aRadianes(a1)) * Math.cos(aRadianes(a2)) * Math.sin(dLon / 2) ** 2;
  // min(1, …) protege de un √ apenas > 1 por redondeo en puntos antipodales.
  return 2 * RADIO_TIERRA_KM * Math.asin(Math.min(1, Math.sqrt(h)));
}

/** ¿Es un número finito (no NaN, no Infinity, no '' ni null)? Acepta texto numérico. */
function numeroFinito(valor) {
  if (valor === null || valor === undefined || valor === '' || typeof valor === 'boolean') return false;
  if (typeof valor !== 'number' && typeof valor !== 'string') return false;
  return Number.isFinite(Number(valor));
}

/** Latitud/longitud con forma de coordenada real del planeta. */
function coordenadasValidas(latitud, longitud) {
  if (!numeroFinito(latitud) || !numeroFinito(longitud)) return false;
  const lat = Number(latitud);
  const lon = Number(longitud);
  return lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;
}

/** ¿El punto cae dentro del radio configurado alrededor del centro? (borde incluido) */
function dentroDeZonaDelivery({ latitud, longitud, latitudCentro, longitudCentro, radioKm }) {
  if (!coordenadasValidas(latitud, longitud) || !coordenadasValidas(latitudCentro, longitudCentro)) return false;
  const radio = Number(radioKm);
  if (!Number.isFinite(radio) || radio <= 0) return false;
  return distanciaKm(latitud, longitud, latitudCentro, longitudCentro) <= radio;
}

/**
 * `tipoEntrega` del body tal como se usa: ausente/vacío → 'RECOJO' (así
 * todo cliente con la página vieja en caché sigue igual), y en mayúsculas.
 * Devuelve null si viene algo que no es ninguno de los dos valores, para
 * que quien llama lo rechace con 400 en vez de adivinar.
 */
function normalizarTipoEntrega(tipoEntrega) {
  if (tipoEntrega === undefined || tipoEntrega === null || String(tipoEntrega).trim() === '') {
    return TIPO_ENTREGA_RECOJO;
  }
  const limpio = String(tipoEntrega).trim().toUpperCase();
  return TIPOS_ENTREGA.includes(limpio) ? limpio : null;
}

/** Dirección escrita tal como se guarda: espacios colapsados, sin bordes. */
function normalizarDireccion(direccion) {
  if (typeof direccion !== 'string') return '';
  return direccion.replace(/\s+/g, ' ').trim();
}

/**
 * Valida un pedido con delivery. Puro: la configuración (centro y radio)
 * llega ya leída.
 *
 * Devuelve `{ valido: true, direccion, latitud, longitud, distanciaKm }`
 * con los valores normalizados listos para la base, o
 * `{ valido: false, motivo, fueraDeZona }` con un mensaje en español para
 * mostrarle al cliente. `fueraDeZona: true` distingue "tu dirección está
 * lejos" (la página ofrece recoger en tienda) de "te faltó un dato".
 */
function validarDelivery({ tiendaSlug, hayPanPorUnidad, direccion, latitud, longitud, latitudCentro, longitudCentro, radioKm }) {
  if (!SLUGS_DELIVERY.includes(String(tiendaSlug || '').trim()) || !hayPanPorUnidad) {
    return {
      valido: false,
      fueraDeZona: false,
      motivo: 'El delivery solo está disponible para pan de agua y pan francés por ahora.',
    };
  }

  const direccionLimpia = normalizarDireccion(direccion);
  if (direccionLimpia.length < LARGO_MINIMO_DIRECCION) {
    return {
      valido: false,
      fueraDeZona: false,
      motivo: 'Escribe tu dirección completa y una referencia para que el repartidor pueda encontrarte.',
    };
  }
  if (direccionLimpia.length > LARGO_MAXIMO_DIRECCION) {
    return {
      valido: false,
      fueraDeZona: false,
      motivo: `La dirección y la referencia no pueden pasar de ${LARGO_MAXIMO_DIRECCION} caracteres.`,
    };
  }

  if (!coordenadasValidas(latitud, longitud)) {
    return {
      valido: false,
      fueraDeZona: false,
      motivo: 'Marca en el mapa el lugar exacto de entrega.',
    };
  }

  const distancia = distanciaKm(latitud, longitud, latitudCentro, longitudCentro);
  if (!dentroDeZonaDelivery({ latitud, longitud, latitudCentro, longitudCentro, radioKm })) {
    return {
      valido: false,
      fueraDeZona: true,
      motivo: 'Por ahora solo hacemos delivery dentro de Pisco y tu ubicación queda fuera de la zona de reparto. Puedes hacer el pedido para recogerlo en tienda.',
    };
  }

  return {
    valido: true,
    direccion: direccionLimpia,
    latitud: Number(Number(latitud).toFixed(7)),
    longitud: Number(Number(longitud).toFixed(7)),
    distanciaKm: Number(distancia.toFixed(2)),
  };
}

/** Lee UNA clave de Configuraciones como número; `porDefecto` si falta, no es número o la consulta falla. */
async function leerNumeroConfigurado(pool, clave, porDefecto) {
  if (!pool) return porDefecto;
  try {
    const result = await pool
      .request()
      .input('Clave', clave)
      .query('SELECT Valor FROM Configuraciones WHERE Clave = @Clave');
    const valor = result.recordset[0]?.Valor;
    if (valor === undefined || valor === null || String(valor).trim() === '') return porDefecto;
    const numero = Number(String(valor).trim());
    return Number.isFinite(numero) ? numero : porDefecto;
  } catch (err) {
    console.warn(`No se pudo leer ${clave}, se usa el valor por defecto (${porDefecto}):`, err.message);
    return porDefecto;
  }
}

/**
 * Costo del envío en soles, de `COSTO_DELIVERY_PANADERIA`, sin caché. Cae a
 * [COSTO_DELIVERY_POR_DEFECTO] si la clave falta, la consulta falla o el
 * valor es negativo/basura. Redondeado al céntimo.
 */
async function obtenerCostoDelivery(pool) {
  const costo = await leerNumeroConfigurado(pool, CLAVE_COSTO_DELIVERY, COSTO_DELIVERY_POR_DEFECTO);
  if (costo < 0) return COSTO_DELIVERY_POR_DEFECTO;
  return Number(costo.toFixed(2));
}

/** Centro y radio de la zona de reparto, sin caché. Cada valor cae a su default por separado. */
async function obtenerZonaDelivery(pool) {
  const [latitudCentro, longitudCentro, radioKm] = await Promise.all([
    leerNumeroConfigurado(pool, CLAVE_LATITUD_CENTRO, LATITUD_CENTRO_POR_DEFECTO),
    leerNumeroConfigurado(pool, CLAVE_LONGITUD_CENTRO, LONGITUD_CENTRO_POR_DEFECTO),
    leerNumeroConfigurado(pool, CLAVE_RADIO_KM, RADIO_KM_POR_DEFECTO),
  ]);
  return {
    latitudCentro: coordenadasValidas(latitudCentro, longitudCentro) ? latitudCentro : LATITUD_CENTRO_POR_DEFECTO,
    longitudCentro: coordenadasValidas(latitudCentro, longitudCentro) ? longitudCentro : LONGITUD_CENTRO_POR_DEFECTO,
    radioKm: radioKm > 0 ? radioKm : RADIO_KM_POR_DEFECTO,
  };
}

module.exports = {
  TIPO_ENTREGA_RECOJO,
  TIPO_ENTREGA_DELIVERY,
  TIPOS_ENTREGA,
  SLUGS_DELIVERY,
  CLAVE_COSTO_DELIVERY,
  CLAVE_LATITUD_CENTRO,
  CLAVE_LONGITUD_CENTRO,
  CLAVE_RADIO_KM,
  COSTO_DELIVERY_POR_DEFECTO,
  LATITUD_CENTRO_POR_DEFECTO,
  LONGITUD_CENTRO_POR_DEFECTO,
  RADIO_KM_POR_DEFECTO,
  RADIO_TIERRA_KM,
  LARGO_MINIMO_DIRECCION,
  LARGO_MAXIMO_DIRECCION,
  distanciaKm,
  coordenadasValidas,
  dentroDeZonaDelivery,
  normalizarTipoEntrega,
  normalizarDireccion,
  validarDelivery,
  obtenerCostoDelivery,
  obtenerZonaDelivery,
};
