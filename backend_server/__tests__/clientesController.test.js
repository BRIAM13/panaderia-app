const {
  calcularCalidadDato,
  calcularSegmento,
  esRucPersonaJuridica,
  resumirSegmentosClientes,
} = require('../controllers/clientesController');

// Mismos valores por defecto que usa el CRM en producción (ver
// Configuraciones: CLIENTES_DIAS_EN_RIESGO, CLIENTES_PEDIDOS_FRECUENTE,
// CLIENTES_UMBRAL_VIP_SOLES).
const CONFIG_DEFECTO = { diasEnRiesgo: 30, pedidosFrecuente: 5, umbralVipSoles: 200 };

describe('calcularCalidadDato', () => {
  test('sin DNI, la calidad es SIN_DNI sin importar el origen', () => {
    expect(calcularCalidadDato(null, 'RENIEC')).toBe('SIN_DNI');
    expect(calcularCalidadDato(undefined, 'MANUAL')).toBe('SIN_DNI');
  });

  test('con DNI validado por RENIEC, la calidad es RENIEC', () => {
    expect(calcularCalidadDato('12345678', 'RENIEC')).toBe('RENIEC');
  });

  test('con DNI pero origen distinto de RENIEC, la calidad es MANUAL', () => {
    expect(calcularCalidadDato('12345678', 'MANUAL')).toBe('MANUAL');
    expect(calcularCalidadDato('12345678', 'SUNAT')).toBe('MANUAL');
    expect(calcularCalidadDato('12345678', undefined)).toBe('MANUAL');
  });
});

describe('esRucPersonaJuridica', () => {
  test('un RUC de 11 dígitos que empieza con 20 es persona jurídica', () => {
    expect(esRucPersonaJuridica('20123456789')).toBe(true);
  });

  test('un RUC de 11 dígitos que empieza con 10 (persona natural) no es jurídica', () => {
    expect(esRucPersonaJuridica('10123456789')).toBe(false);
  });

  test('un DNI de 8 dígitos nunca es RUC de persona jurídica', () => {
    expect(esRucPersonaJuridica('12345678')).toBe(false);
  });

  test('valores no-string o vacíos no rompen la función', () => {
    expect(esRucPersonaJuridica(null)).toBe(false);
    expect(esRucPersonaJuridica(undefined)).toBe(false);
    expect(esRucPersonaJuridica('')).toBe(false);
  });
});

describe('calcularSegmento', () => {
  test('sin pedidos entregados, el cliente es NUEVO', () => {
    const agregado = { pedidosEntregados: 0, totalGastado: 0, diasDesdeUltimaCompra: null };
    expect(calcularSegmento(agregado, CONFIG_DEFECTO)).toBe('NUEVO');
  });

  test('con compras pero hace más días que el umbral de riesgo, el cliente está EN_RIESGO', () => {
    const agregado = { pedidosEntregados: 3, totalGastado: 50, diasDesdeUltimaCompra: 31 };
    expect(calcularSegmento(agregado, CONFIG_DEFECTO)).toBe('EN_RIESGO');
  });

  test('justo en el umbral de días, todavía NO se considera en riesgo', () => {
    const agregado = { pedidosEntregados: 3, totalGastado: 50, diasDesdeUltimaCompra: 30 };
    expect(calcularSegmento(agregado, CONFIG_DEFECTO)).not.toBe('EN_RIESGO');
  });

  test('gasto igual o mayor al umbral VIP prevalece sobre "frecuente"', () => {
    const agregado = { pedidosEntregados: 2, totalGastado: 200, diasDesdeUltimaCompra: 1 };
    expect(calcularSegmento(agregado, CONFIG_DEFECTO)).toBe('VIP');
  });

  test('suficientes pedidos entregados sin llegar al gasto VIP es FRECUENTE', () => {
    const agregado = { pedidosEntregados: 5, totalGastado: 80, diasDesdeUltimaCompra: 2 };
    expect(calcularSegmento(agregado, CONFIG_DEFECTO)).toBe('FRECUENTE');
  });

  test('con compras recientes pero sin llegar a ningún umbral, el cliente es REGULAR', () => {
    const agregado = { pedidosEntregados: 2, totalGastado: 40, diasDesdeUltimaCompra: 5 };
    expect(calcularSegmento(agregado, CONFIG_DEFECTO)).toBe('REGULAR');
  });

  test('EN_RIESGO tiene prioridad sobre VIP y FRECUENTE aunque el cliente gaste mucho', () => {
    const agregado = { pedidosEntregados: 10, totalGastado: 500, diasDesdeUltimaCompra: 60 };
    expect(calcularSegmento(agregado, CONFIG_DEFECTO)).toBe('EN_RIESGO');
  });
});

describe('resumirSegmentosClientes', () => {
  // Reloj fijo: el segmento EN_RIESGO depende de "hace cuántos días compró",
  // así que sin fijarlo la prueba cambiaría de resultado según el día.
  const AHORA = new Date('2026-03-01T12:00:00Z').getTime();
  const haceDias = (dias) => new Date(AHORA - dias * 86400000).toISOString();

  const FILAS = [
    // Nunca compró -> NUEVO (llega con LEFT JOIN, sin fila de Pedidos).
    { IdCliente: 1, DNI: '11111111', Nombres: 'ANA', ApellidoPaterno: 'PEREZ', ApellidoMaterno: 'DIAZ', Telefono: '900000001', PedidosEntregados: 0, TotalGastado: 0, UltimaCompra: null },
    // Compró hace 45 días -> EN_RIESGO pese a ser el que más gastó.
    { IdCliente: 2, DNI: '22222222', Nombres: 'BETO', ApellidoPaterno: 'SOTO', ApellidoMaterno: null, Telefono: null, PedidosEntregados: 8, TotalGastado: 900, UltimaCompra: haceDias(45) },
    // RUC de empresa: el nombre a mostrar es la razón social, sin apellidos.
    { IdCliente: 3, DNI: '20123456789', Nombres: 'PANIFICADORA SAC', ApellidoPaterno: '', ApellidoMaterno: null, Telefono: '900000003', PedidosEntregados: 4, TotalGastado: 300, UltimaCompra: haceDias(2) },
    { IdCliente: 4, DNI: '44444444', Nombres: 'DINA', ApellidoPaterno: 'LOPEZ', ApellidoMaterno: 'RUIZ', Telefono: '900000004', PedidosEntregados: 6, TotalGastado: 90, UltimaCompra: haceDias(3) },
    { IdCliente: 5, DNI: null, Nombres: 'EVA', ApellidoPaterno: 'MEZA', ApellidoMaterno: null, Telefono: null, PedidosEntregados: 1, TotalGastado: 20, UltimaCompra: haceDias(10) },
  ];

  test('cuenta cada segmento y deja en cero los que no tienen a nadie', () => {
    const { resumen, totalClientes } = resumirSegmentosClientes(FILAS, CONFIG_DEFECTO, AHORA);
    expect(resumen).toEqual({ NUEVO: 1, EN_RIESGO: 1, VIP: 1, FRECUENTE: 1, REGULAR: 1 });
    expect(totalClientes).toBe(5);
  });

  test('la lista de en riesgo trae solo a ese segmento, con su nombre y días sin comprar', () => {
    const { enRiesgo } = resumirSegmentosClientes(FILAS, CONFIG_DEFECTO, AHORA);
    expect(enRiesgo).toHaveLength(1);
    expect(enRiesgo[0]).toMatchObject({
      idCliente: 2,
      nombre: 'BETO SOTO',
      telefono: null,
      diasDesdeUltimaCompra: 45,
      segmento: 'EN_RIESGO',
    });
  });

  test('el top por gasto va de mayor a menor, excluye a quien nunca compró e incluye a los en riesgo', () => {
    const { topPorGasto } = resumirSegmentosClientes(FILAS, CONFIG_DEFECTO, AHORA);
    expect(topPorGasto.map((c) => c.idCliente)).toEqual([2, 3, 4, 5]);
    // Cliente con RUC: se muestra la razón social sola, no "NOMBRE APELLIDO".
    expect(topPorGasto[1].nombre).toBe('PANIFICADORA SAC');
  });
});
