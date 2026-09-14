const {
  CLAVE_DESCUENTO_NUEVO,
  CLAVE_DESCUENTO_FRECUENTE,
  CLAVE_DESCUENTO_VIP,
  CLAVE_TIENDAS_HABILITADAS,
  PORCENTAJES_POR_DEFECTO,
  parsearTiendasHabilitadas,
  porcentajeDeSegmento,
  aplicarDescuento,
  obtenerConfiguracionDescuentos,
  calcularDescuentoCliente,
} = require('../utils/descuentosCliente');

// Mismos valores que siembra scripts/seed_descuentos_clientes.js.
const CONFIGURACIONES_SEMBRADAS = {
  DESCUENTO_SEGMENTO_NUEVO: '5',
  DESCUENTO_SEGMENTO_REGULAR: '5',
  DESCUENTO_SEGMENTO_EN_RIESGO: '5',
  DESCUENTO_SEGMENTO_FRECUENTE: '10',
  DESCUENTO_SEGMENTO_VIP: '15',
  DESCUENTOS_TIENDAS_HABILITADAS: 'panaderia',
};

/**
 * Pool de mentira con la misma superficie que usa el código
 * (`pool.request().input().query()`), para poder probar las dos funciones
 * que sí tocan la base sin levantar ninguna — igual de determinista que las
 * pruebas puras del resto del directorio.
 *
 * `configuraciones` es el contenido de la tabla Configuraciones y es un
 * objeto MUTABLE a propósito: cambiarlo entre dos llamadas es exactamente
 * lo que hace el dueño desde la app, y así se comprueba que no haya caché.
 *
 * `historial` es la fila que devolvería el agregado sobre Pedidos; null
 * simula un cliente que no tiene ni un pedido (el agregado igual devuelve
 * una fila, pero con NULLs).
 */
function crearPoolFalso({ configuraciones, historial = null }) {
  const consultas = [];
  const pool = {
    consultas,
    request() {
      const request = {
        input: () => request,
        async query(texto) {
          consultas.push(texto);
          if (/FROM\s+Pedidos/i.test(texto)) {
            return {
              recordset: [
                historial ?? { PedidosEntregados: null, TotalGastado: 0, UltimaCompra: null },
              ],
            };
          }
          // Configuraciones: se devuelven solo las claves que la consulta
          // pide Y que existen en la tabla simulada, igual que la real.
          const pedidas = [...texto.matchAll(/'([A-Z_]+)'/g)].map((m) => m[1]);
          return {
            recordset: pedidas
              .filter((clave) => configuraciones[clave] !== undefined)
              .map((clave) => ({ Clave: clave, Valor: configuraciones[clave] })),
          };
        },
      };
      return request;
    },
  };
  return pool;
}

/** Fila de Pedidos con `dias` días desde la última compra entregada. */
function historialCon({ pedidosEntregados, totalGastado, dias }) {
  return {
    PedidosEntregados: pedidosEntregados,
    TotalGastado: totalGastado,
    UltimaCompra: new Date(Date.now() - dias * 86400000).toISOString(),
  };
}

describe('parsearTiendasHabilitadas', () => {
  test('separa por coma y limpia espacios', () => {
    expect([...parsearTiendasHabilitadas('panaderia, horneados')]).toEqual(['panaderia', 'horneados']);
  });

  test('un valor vacío o ausente no habilita ninguna tienda (falla cerrado)', () => {
    expect(parsearTiendasHabilitadas('').size).toBe(0);
    expect(parsearTiendasHabilitadas(null).size).toBe(0);
    expect(parsearTiendasHabilitadas(undefined).size).toBe(0);
  });

  test('las comas de más no habilitan una tienda sin nombre', () => {
    expect([...parsearTiendasHabilitadas('panaderia,,  ,')]).toEqual(['panaderia']);
  });
});

describe('porcentajeDeSegmento', () => {
  test('devuelve el porcentaje configurado para el segmento', () => {
    expect(porcentajeDeSegmento(PORCENTAJES_POR_DEFECTO, 'VIP')).toBe(15);
    expect(porcentajeDeSegmento(PORCENTAJES_POR_DEFECTO, 'FRECUENTE')).toBe(10);
    expect(porcentajeDeSegmento(PORCENTAJES_POR_DEFECTO, 'NUEVO')).toBe(5);
  });

  test('un segmento desconocido o nulo no descuenta nada, en vez de romper', () => {
    expect(porcentajeDeSegmento(PORCENTAJES_POR_DEFECTO, 'INVENTADO')).toBe(0);
    expect(porcentajeDeSegmento(PORCENTAJES_POR_DEFECTO, null)).toBe(0);
  });
});

describe('aplicarDescuento', () => {
  test('sin descuento, el total es el subtotal tal cual', () => {
    expect(aplicarDescuento(37.5, 0)).toBe(37.5);
  });

  test('descuenta el porcentaje y redondea a 2 decimales', () => {
    expect(aplicarDescuento(100, 15)).toBe(85);
    expect(aplicarDescuento(33.33, 10)).toBe(30);
    expect(aplicarDescuento(17.5, 5)).toBe(16.63);
  });
});

describe('obtenerConfiguracionDescuentos', () => {
  test('lee los 5 porcentajes y la lista de tiendas de Configuraciones', async () => {
    const pool = crearPoolFalso({ configuraciones: { ...CONFIGURACIONES_SEMBRADAS } });
    const config = await obtenerConfiguracionDescuentos(pool);

    expect(config.porcentajePorSegmento).toEqual({
      NUEVO: 5,
      REGULAR: 5,
      EN_RIESGO: 5,
      FRECUENTE: 10,
      VIP: 15,
    });
    expect([...config.tiendasHabilitadas]).toEqual(['panaderia']);
  });

  test('sin las claves sembradas, cae a los porcentajes por defecto y a ninguna tienda', async () => {
    const pool = crearPoolFalso({ configuraciones: {} });
    const config = await obtenerConfiguracionDescuentos(pool);

    expect(config.porcentajePorSegmento).toEqual(PORCENTAJES_POR_DEFECTO);
    // Falla cerrado: sin la clave, no se descuenta en ninguna tienda.
    expect(config.tiendasHabilitadas.size).toBe(0);
  });
});

describe('calcularDescuentoCliente', () => {
  test('una tienda que no está en la lista habilitada no descuenta nada', async () => {
    const pool = crearPoolFalso({ configuraciones: { ...CONFIGURACIONES_SEMBRADAS } });
    const resultado = await calcularDescuentoCliente({ pool, idCliente: 7, tiendaSlug: 'hamburguesas' });

    expect(resultado).toEqual({ aplica: false, segmento: null, porcentaje: 0 });
  });

  test('sin tienda (o con una vacía) tampoco descuenta', async () => {
    const pool = crearPoolFalso({ configuraciones: { ...CONFIGURACIONES_SEMBRADAS } });
    expect(await calcularDescuentoCliente({ pool, idCliente: 7, tiendaSlug: null })).toEqual({
      aplica: false,
      segmento: null,
      porcentaje: 0,
    });
    expect(await calcularDescuentoCliente({ pool, idCliente: 7, tiendaSlug: '  ' })).toEqual({
      aplica: false,
      segmento: null,
      porcentaje: 0,
    });
  });

  test('con la lista de tiendas vacía, ni siquiera Panadería descuenta', async () => {
    const pool = crearPoolFalso({
      configuraciones: { ...CONFIGURACIONES_SEMBRADAS, DESCUENTOS_TIENDAS_HABILITADAS: '' },
    });
    const resultado = await calcularDescuentoCliente({ pool, idCliente: 7, tiendaSlug: 'panaderia' });

    expect(resultado.aplica).toBe(false);
    expect(resultado.porcentaje).toBe(0);
  });

  // El acuerdo con el dueño: quien pide por primera vez TAMBIÉN se lleva su
  // descuento — nunca 0% para un primerizo.
  test('un cliente que todavía no existe en la base (sin IdCliente) recibe el porcentaje de NUEVO', async () => {
    const pool = crearPoolFalso({ configuraciones: { ...CONFIGURACIONES_SEMBRADAS } });
    const resultado = await calcularDescuentoCliente({ pool, idCliente: null, tiendaSlug: 'panaderia' });

    expect(resultado).toEqual({ aplica: true, segmento: 'NUEVO', porcentaje: 5 });
    // Y ni se consultó Pedidos: no hay historial que buscar.
    expect(pool.consultas.some((c) => /FROM\s+Pedidos/i.test(c))).toBe(false);
  });

  test('un cliente que existe pero nunca recibió un pedido también es NUEVO', async () => {
    const pool = crearPoolFalso({ configuraciones: { ...CONFIGURACIONES_SEMBRADAS }, historial: null });
    const resultado = await calcularDescuentoCliente({ pool, idCliente: 42, tiendaSlug: 'panaderia' });

    expect(resultado).toEqual({ aplica: true, segmento: 'NUEVO', porcentaje: 5 });
  });

  test('un cliente que pasó el umbral de gasto es VIP y se lleva el porcentaje VIP', async () => {
    const pool = crearPoolFalso({
      configuraciones: { ...CONFIGURACIONES_SEMBRADAS },
      historial: historialCon({ pedidosEntregados: 3, totalGastado: 350, dias: 2 }),
    });
    const resultado = await calcularDescuentoCliente({ pool, idCliente: 42, tiendaSlug: 'panaderia' });

    expect(resultado).toEqual({ aplica: true, segmento: 'VIP', porcentaje: 15 });
  });

  test('un cliente con muchos pedidos pero poco gasto es FRECUENTE', async () => {
    const pool = crearPoolFalso({
      configuraciones: { ...CONFIGURACIONES_SEMBRADAS },
      historial: historialCon({ pedidosEntregados: 6, totalGastado: 60, dias: 1 }),
    });
    const resultado = await calcularDescuentoCliente({ pool, idCliente: 42, tiendaSlug: 'panaderia' });

    expect(resultado).toEqual({ aplica: true, segmento: 'FRECUENTE', porcentaje: 10 });
  });

  // Lo que hace que la pantalla de la app sirva de algo: cambiar el valor en
  // Configuraciones tiene que verse en la llamada SIGUIENTE, sin reiniciar
  // el servidor ni esperar a que expire ninguna caché.
  test('cambiar un porcentaje en Configuraciones se refleja en la llamada siguiente (sin caché)', async () => {
    const configuraciones = { ...CONFIGURACIONES_SEMBRADAS };
    const pool = crearPoolFalso({
      configuraciones,
      historial: historialCon({ pedidosEntregados: 3, totalGastado: 350, dias: 2 }),
    });

    expect((await calcularDescuentoCliente({ pool, idCliente: 42, tiendaSlug: 'panaderia' })).porcentaje).toBe(15);

    configuraciones[CLAVE_DESCUENTO_VIP] = '20';
    expect((await calcularDescuentoCliente({ pool, idCliente: 42, tiendaSlug: 'panaderia' })).porcentaje).toBe(20);
  });

  test('habilitar una tienda nueva desde la app aplica de inmediato', async () => {
    const configuraciones = { ...CONFIGURACIONES_SEMBRADAS };
    const pool = crearPoolFalso({ configuraciones });

    expect((await calcularDescuentoCliente({ pool, idCliente: null, tiendaSlug: 'horneados' })).aplica).toBe(false);

    configuraciones[CLAVE_TIENDAS_HABILITADAS] = 'panaderia, horneados';
    const resultado = await calcularDescuentoCliente({ pool, idCliente: null, tiendaSlug: 'horneados' });
    expect(resultado).toEqual({ aplica: true, segmento: 'NUEVO', porcentaje: 5 });
  });

  test('poner un porcentaje en 0 desde la app deja al segmento sin descuento, sin romper nada', async () => {
    const configuraciones = { ...CONFIGURACIONES_SEMBRADAS, [CLAVE_DESCUENTO_NUEVO]: '0' };
    const pool = crearPoolFalso({ configuraciones });
    const resultado = await calcularDescuentoCliente({ pool, idCliente: null, tiendaSlug: 'panaderia' });

    // `aplica` sigue en true (la tienda SÍ está habilitada); lo que vale 0
    // es el porcentaje de ese segmento en particular.
    expect(resultado).toEqual({ aplica: true, segmento: 'NUEVO', porcentaje: 0 });
  });

  test('un porcentaje escrito mal en Configuraciones cae al valor por defecto en vez de romper', async () => {
    const configuraciones = { ...CONFIGURACIONES_SEMBRADAS, [CLAVE_DESCUENTO_FRECUENTE]: 'diez por ciento' };
    const pool = crearPoolFalso({
      configuraciones,
      historial: historialCon({ pedidosEntregados: 6, totalGastado: 60, dias: 1 }),
    });
    const resultado = await calcularDescuentoCliente({ pool, idCliente: 42, tiendaSlug: 'panaderia' });

    expect(resultado.porcentaje).toBe(PORCENTAJES_POR_DEFECTO.FRECUENTE);
  });
});
