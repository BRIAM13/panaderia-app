const { rellenarVentasPorHora, calcularVariacionMensual } = require('../controllers/tiendasController');

describe('rellenarVentasPorHora', () => {
  test('siempre devuelve las 24 horas del día, en orden', () => {
    const serie = rellenarVentasPorHora([]);
    expect(serie).toHaveLength(24);
    expect(serie.map((h) => h.hora)).toEqual([...Array(24).keys()]);
  });

  test('sin ventas, todas las horas quedan en 0 (no faltan del arreglo)', () => {
    const serie = rellenarVentasPorHora([]);
    expect(serie.every((h) => h.cantidad === 0 && h.total === 0)).toBe(true);
  });

  test('ubica cada fila en su hora y rellena el resto con 0', () => {
    const serie = rellenarVentasPorHora([
      { Hora: 8, Cantidad: 3, Total: 45.5 },
      { Hora: 19, Cantidad: 1, Total: 12 },
    ]);
    expect(serie[8]).toEqual({ hora: 8, cantidad: 3, total: 45.5 });
    expect(serie[19]).toEqual({ hora: 19, cantidad: 1, total: 12 });
    expect(serie[0]).toEqual({ hora: 0, cantidad: 0, total: 0 });
    expect(serie[23]).toEqual({ hora: 23, cantidad: 0, total: 0 });
  });

  test('acepta las horas 0 y 23 (los bordes del día)', () => {
    const serie = rellenarVentasPorHora([
      { Hora: 0, Cantidad: 2, Total: 20 },
      { Hora: 23, Cantidad: 5, Total: 100 },
    ]);
    expect(serie[0].cantidad).toBe(2);
    expect(serie[23].total).toBe(100);
  });

  test('convierte a número lo que la base devuelva como texto', () => {
    // Según el driver/columna, un SUM puede llegar como string — el gráfico
    // de Flutter espera números, no "45.50".
    const serie = rellenarVentasPorHora([{ Hora: '10', Cantidad: '4', Total: '80.25' }]);
    expect(serie[10]).toEqual({ hora: 10, cantidad: 4, total: 80.25 });
  });

  test('un SUM nulo cuenta como 0, no como NaN', () => {
    const serie = rellenarVentasPorHora([{ Hora: 7, Cantidad: 0, Total: null }]);
    expect(serie[7].total).toBe(0);
  });

  test('tolera que no llegue ninguna fila (undefined)', () => {
    expect(rellenarVentasPorHora(undefined)).toHaveLength(24);
  });
});

describe('calcularVariacionMensual', () => {
  test('crecimiento: mes actual por encima del mismo tramo del mes anterior', () => {
    expect(
      calcularVariacionMensual({ totalMesActual: 1230, totalMesAnteriorMismoTramo: 1000 }),
    ).toBeCloseTo(23, 5);
  });

  test('caída: devuelve porcentaje negativo', () => {
    expect(
      calcularVariacionMensual({ totalMesActual: 800, totalMesAnteriorMismoTramo: 1000 }),
    ).toBeCloseTo(-20, 5);
  });

  test('sin cambio devuelve 0', () => {
    expect(
      calcularVariacionMensual({ totalMesActual: 500, totalMesAnteriorMismoTramo: 500 }),
    ).toBe(0);
  });

  test('null (no 0 ni -100%) cuando el tramo anterior no vendió nada', () => {
    // Dividir por cero no da "+∞%": da una comparación que no existe, y la
    // UI la muestra como "sin datos".
    expect(calcularVariacionMensual({ totalMesActual: 900, totalMesAnteriorMismoTramo: 0 })).toBeNull();
    expect(calcularVariacionMensual({ totalMesActual: 900, totalMesAnteriorMismoTramo: null })).toBeNull();
    expect(calcularVariacionMensual({ totalMesActual: 900, totalMesAnteriorMismoTramo: undefined })).toBeNull();
  });

  test('un tramo anterior negativo (dato corrupto) tampoco se compara', () => {
    expect(calcularVariacionMensual({ totalMesActual: 100, totalMesAnteriorMismoTramo: -50 })).toBeNull();
  });

  test('mes actual en 0 contra un tramo anterior con ventas es -100%', () => {
    expect(
      calcularVariacionMensual({ totalMesActual: 0, totalMesAnteriorMismoTramo: 400 }),
    ).toBeCloseTo(-100, 5);
  });
});
