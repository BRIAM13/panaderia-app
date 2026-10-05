const {
  distanciaKm,
  coordenadasValidas,
  dentroDeZonaDelivery,
  normalizarTipoEntrega,
  validarDelivery,
  obtenerCostoDelivery,
  obtenerZonaDelivery,
  COSTO_DELIVERY_POR_DEFECTO,
  LATITUD_CENTRO_POR_DEFECTO,
  LONGITUD_CENTRO_POR_DEFECTO,
  RADIO_KM_POR_DEFECTO,
} = require('../utils/delivery');

/** La panadería (coordenadas reales confirmadas por el dueño, 2026-10-05). */
const PANADERIA = { lat: -13.706622640097475, lon: -76.20123704674447 };
const ZONA = { latitudCentro: PANADERIA.lat, longitudCentro: PANADERIA.lon, radioKm: 8 };

/** Grados de latitud equivalentes a `km` hacia el norte/sur (1° = π·6371/180 km). */
const gradosLatitud = (km) => km / ((Math.PI * 6371) / 180);

describe('distanciaKm (Haversine)', () => {
  test('caso de referencia publicado: BNA (Nashville) → LAX', () => {
    // Rosetta Code, "Haversine formula": (36.12, -86.67) → (33.94, -118.40)
    // da 2887.2599506071106 km con R = 6372.8. Con R = 6371 (el de acá) la
    // misma fórmula da ese valor escalado por 6371/6372.8.
    const esperado = (2887.2599506071106 * 6371) / 6372.8;
    expect(distanciaKm(36.12, -86.67, 33.94, -118.4)).toBeCloseTo(esperado, 6);
  });

  test('1° de latitud sobre un meridiano = π·R/180 ≈ 111.195 km', () => {
    expect(distanciaKm(0, 0, 1, 0)).toBeCloseTo((Math.PI * 6371) / 180, 9);
    expect(distanciaKm(0, 0, 1, 0)).toBeCloseTo(111.195, 3);
  });

  test('ecuador → polo = un cuarto de circunferencia (≈ 10007.54 km)', () => {
    expect(distanciaKm(0, 0, 90, 0)).toBeCloseTo((Math.PI * 6371) / 2, 6);
  });

  test('1° de longitud sobre el ecuador mide lo mismo que 1° de latitud', () => {
    expect(distanciaKm(0, 0, 0, 1)).toBeCloseTo(distanciaKm(0, 0, 1, 0), 9);
  });

  test('es simétrica y vale 0 para el mismo punto', () => {
    const ida = distanciaKm(PANADERIA.lat, PANADERIA.lon, -13.72, -76.18);
    const vuelta = distanciaKm(-13.72, -76.18, PANADERIA.lat, PANADERIA.lon);
    expect(ida).toBeCloseTo(vuelta, 12);
    expect(distanciaKm(PANADERIA.lat, PANADERIA.lon, PANADERIA.lat, PANADERIA.lon)).toBe(0);
  });

  test('acepta texto numérico (el body JSON puede traerlo así)', () => {
    expect(distanciaKm('0', '0', '1', '0')).toBeCloseTo(111.195, 3);
  });

  test('basura da NaN, nunca un número que pase por "cerca"', () => {
    expect(Number.isNaN(distanciaKm('abc', 0, 1, 0))).toBe(true);
  });
});

describe('coordenadasValidas', () => {
  test('rango geográfico real', () => {
    expect(coordenadasValidas(-13.7, -76.2)).toBe(true);
    expect(coordenadasValidas(90, 180)).toBe(true);
    expect(coordenadasValidas(-90, -180)).toBe(true);
    expect(coordenadasValidas(90.0001, 0)).toBe(false);
    expect(coordenadasValidas(0, -180.0001)).toBe(false);
  });

  test('rechaza NaN, Infinity, vacío, null, booleanos y objetos', () => {
    for (const malo of [NaN, Infinity, -Infinity, '', null, undefined, true, false, {}, [], 'abc']) {
      expect(coordenadasValidas(malo, -76.2)).toBe(false);
      expect(coordenadasValidas(-13.7, malo)).toBe(false);
    }
  });
});

describe('dentroDeZonaDelivery', () => {
  test('la propia panadería está dentro', () => {
    expect(dentroDeZonaDelivery({ latitud: PANADERIA.lat, longitud: PANADERIA.lon, ...ZONA })).toBe(true);
  });

  test('7.9 km al norte entra, 8.1 km no', () => {
    expect(
      dentroDeZonaDelivery({ latitud: PANADERIA.lat + gradosLatitud(7.9), longitud: PANADERIA.lon, ...ZONA }),
    ).toBe(true);
    expect(
      dentroDeZonaDelivery({ latitud: PANADERIA.lat + gradosLatitud(8.1), longitud: PANADERIA.lon, ...ZONA }),
    ).toBe(false);
  });

  test('Ica ciudad (~70 km) y Lima quedan fuera', () => {
    expect(dentroDeZonaDelivery({ latitud: -14.0678, longitud: -75.7286, ...ZONA })).toBe(false);
    expect(dentroDeZonaDelivery({ latitud: -12.0464, longitud: -77.0428, ...ZONA })).toBe(false);
  });

  test('un radio inválido (0, negativo, basura) no deja pasar a nadie', () => {
    for (const radioKm of [0, -5, 'mucho', NaN]) {
      expect(dentroDeZonaDelivery({ latitud: PANADERIA.lat, longitud: PANADERIA.lon, ...ZONA, radioKm })).toBe(false);
    }
  });
});

describe('normalizarTipoEntrega', () => {
  test('ausente o vacío es RECOJO (compatibilidad con la página vieja)', () => {
    for (const v of [undefined, null, '', '   ']) expect(normalizarTipoEntrega(v)).toBe('RECOJO');
  });

  test('acepta los dos valores, sin importar mayúsculas ni espacios', () => {
    expect(normalizarTipoEntrega('DELIVERY')).toBe('DELIVERY');
    expect(normalizarTipoEntrega(' delivery ')).toBe('DELIVERY');
    expect(normalizarTipoEntrega('recojo')).toBe('RECOJO');
  });

  test('cualquier otra cosa es null (el controlador responde 400)', () => {
    for (const v of ['ENVIO', 'true', 1, {}]) expect(normalizarTipoEntrega(v)).toBeNull();
  });
});

describe('validarDelivery', () => {
  const base = {
    tiendaSlug: 'panaderia',
    hayPanPorUnidad: true,
    direccion: '  Av. San Martín 123,   frente al mercado ',
    latitud: PANADERIA.lat + gradosLatitud(2),
    longitud: PANADERIA.lon,
    ...ZONA,
  };

  test('dentro de zona y con todos los datos: válido, normalizado', () => {
    const r = validarDelivery(base);
    expect(r.valido).toBe(true);
    expect(r.direccion).toBe('Av. San Martín 123, frente al mercado');
    expect(r.distanciaKm).toBeCloseTo(2, 2);
    // Cabe en DECIMAL(10,7).
    expect(r.latitud).toBe(Number(base.latitud.toFixed(7)));
  });

  test('hamburguesa (o tienda desconocida, o sin pan por unidad) no califica', () => {
    for (const extra of [{ tiendaSlug: 'hamburguesas' }, { tiendaSlug: null }, { hayPanPorUnidad: false }]) {
      const r = validarDelivery({ ...base, ...extra });
      expect(r.valido).toBe(false);
      expect(r.fueraDeZona).toBe(false);
      expect(r.motivo).toBe('El delivery solo está disponible para pan de agua y pan francés por ahora.');
    }
  });

  test('fuera de zona: rechazo con fueraDeZona = true y ofrece recoger', () => {
    const r = validarDelivery({ ...base, latitud: -14.0678, longitud: -75.7286 });
    expect(r.valido).toBe(false);
    expect(r.fueraDeZona).toBe(true);
    expect(r.motivo).toMatch(/solo hacemos delivery dentro de Pisco/);
    expect(r.motivo).toMatch(/recogerlo en tienda/);
  });

  test('sin dirección, o una demasiado corta o larga, se rechaza', () => {
    for (const direccion of [undefined, null, '', '   ', 'casa', 123, 'x'.repeat(301)]) {
      const r = validarDelivery({ ...base, direccion });
      expect(r.valido).toBe(false);
      expect(r.fueraDeZona).toBe(false);
    }
    expect(validarDelivery({ ...base, direccion: 'x'.repeat(300) }).valido).toBe(true);
  });

  test('sin pin, o con un pin imposible, se rechaza pidiendo marcarlo', () => {
    for (const coords of [{ latitud: null }, { longitud: undefined }, { latitud: 'abc' }, { latitud: 91 }, { longitud: 200 }]) {
      const r = validarDelivery({ ...base, ...coords });
      expect(r.valido).toBe(false);
      expect(r.fueraDeZona).toBe(false);
      expect(r.motivo).toMatch(/Marca en el mapa/);
    }
  });
});

/** Un pool falso que contesta `SELECT Valor FROM Configuraciones WHERE Clave = @Clave`. */
function poolCon(config, { fallar = false } = {}) {
  const leidas = [];
  return {
    leidas,
    request() {
      const params = {};
      return {
        input(nombre, valor) {
          params[nombre] = valor;
          return this;
        },
        async query() {
          if (fallar) throw new Error('se cayó la base');
          leidas.push(params.Clave);
          return { recordset: params.Clave in config ? [{ Valor: config[params.Clave] }] : [] };
        },
      };
    },
  };
}

describe('obtenerCostoDelivery', () => {
  test('lee COSTO_DELIVERY_PANADERIA', async () => {
    expect(await obtenerCostoDelivery(poolCon({ COSTO_DELIVERY_PANADERIA: '5.50' }))).toBe(5.5);
  });

  test('sin caché: un cambio aplica en la llamada siguiente', async () => {
    const config = { COSTO_DELIVERY_PANADERIA: '4' };
    const pool = poolCon(config);
    expect(await obtenerCostoDelivery(pool)).toBe(4);
    config.COSTO_DELIVERY_PANADERIA = '6';
    expect(await obtenerCostoDelivery(pool)).toBe(6);
  });

  test('clave ausente, basura, negativa o base caída → S/ 4 por defecto, sin tirar el pedido', async () => {
    expect(COSTO_DELIVERY_POR_DEFECTO).toBe(4);
    expect(await obtenerCostoDelivery(poolCon({}))).toBe(4);
    expect(await obtenerCostoDelivery(poolCon({ COSTO_DELIVERY_PANADERIA: 'cuatro' }))).toBe(4);
    expect(await obtenerCostoDelivery(poolCon({ COSTO_DELIVERY_PANADERIA: '-1' }))).toBe(4);
    expect(await obtenerCostoDelivery(poolCon({}, { fallar: true }))).toBe(4);
    expect(await obtenerCostoDelivery(null)).toBe(4);
  });

  test('envío gratis (0) es un valor válido, no cae al default', async () => {
    expect(await obtenerCostoDelivery(poolCon({ COSTO_DELIVERY_PANADERIA: '0' }))).toBe(0);
  });
});

describe('obtenerZonaDelivery', () => {
  test('lee las tres claves', async () => {
    const zona = await obtenerZonaDelivery(
      poolCon({ DELIVERY_LATITUD_CENTRO: '-13.7', DELIVERY_LONGITUD_CENTRO: '-76.2', DELIVERY_RADIO_KM: '5' }),
    );
    expect(zona).toEqual({ latitudCentro: -13.7, longitudCentro: -76.2, radioKm: 5 });
  });

  test('sin claves o con la base caída usa la panadería real y 8 km', async () => {
    for (const pool of [poolCon({}), poolCon({}, { fallar: true })]) {
      expect(await obtenerZonaDelivery(pool)).toEqual({
        latitudCentro: -13.706622640097475,
        longitudCentro: -76.20123704674447,
        radioKm: 8,
      });
    }
    expect(LATITUD_CENTRO_POR_DEFECTO).toBe(PANADERIA.lat);
    expect(LONGITUD_CENTRO_POR_DEFECTO).toBe(PANADERIA.lon);
    expect(RADIO_KM_POR_DEFECTO).toBe(8);
  });

  test('un radio 0 o negativo cae a 8 km (nunca deja la zona vacía por error de tipeo)', async () => {
    expect((await obtenerZonaDelivery(poolCon({ DELIVERY_RADIO_KM: '0' }))).radioKm).toBe(8);
    expect((await obtenerZonaDelivery(poolCon({ DELIVERY_RADIO_KM: '-3' }))).radioKm).toBe(8);
  });
});
