const { instalarMockMysql, crearRes, crearReq } = require('./helpers/mysqlMock');

/**
 * Pedidos con varios productos (carrito). Se mockea `mysql2/promise`, no
 * `config/db.js`, para que el shim que traduce T-SQL (OUTPUT INSERTED,
 * ISNULL…) corra de verdad — es donde se rompería algo sin que ningún test
 * se entere.
 *
 * Todos los casos usan rol SUPERADMIN: tiene acceso implícito a cualquier
 * tienda, así que no hace falta simular TrabajadorTiendas para probar lo
 * que estos tests sí miran (las líneas, el total y la transacción).
 */
const CLIENTE = {
  IdCliente: 5,
  DescripcionNegocio: 'BODEGA LA ESQUINA',
  DNI: '12345678',
  Nombres: 'JUAN',
  ApellidoPaterno: 'PEREZ',
  ApellidoMaterno: 'GOMEZ',
};

// Catálogo de mentira: los dos primeros son de la tienda 1, el tercero de
// la 2 — para poder armar un carrito "mezclado" y ver que se rechaza.
const CATALOGO = {
  3: { IdProducto: 3, ProductoNombre: 'PAN FRANCES', Nombre: 'PAN FRANCES', PrecioUnitario: 0.35, IdTienda: 1, Slug: 'panaderia', TiendaNombre: 'Panadería' },
  7: { IdProducto: 7, ProductoNombre: 'PAN DE AGUA', Nombre: 'PAN DE AGUA', PrecioUnitario: 0.4, IdTienda: 1, Slug: 'panaderia', TiendaNombre: 'Panadería' },
  9: { IdProducto: 9, ProductoNombre: 'PAN DE HAMBURGUESA', Nombre: 'PAN DE HAMBURGUESA', PrecioUnitario: 12, IdTienda: 2, Slug: 'hamburguesas', TiendaNombre: 'Hamburguesas' },
};

/**
 * Deja el mock listo para el camino feliz de creación: trabajador, cliente,
 * catálogo, correlativo del día e inserts. Cada test agrega/ajusta lo suyo
 * ANTES de llamar acá cuando necesita ganarle a una regla genérica.
 */
function prepararMockBase(mock, { catalogo = CATALOGO } = {}) {
  mock.responder(/FROM Trabajadores/i, [{ IdTrabajador: 7 }]);
  mock.responder(/FROM Clientes c/i, [CLIENTE]);
  // El producto se busca por parámetro: la consulta es idéntica en cada
  // vuelta del bucle, lo que cambia es el `?`.
  mock.responder(/FROM Productos p/i, (_texto, valores) => {
    const producto = catalogo[valores[0]];
    return producto ? [producto] : [];
  });
  mock.responder(/PRECIO_PAQUETE/i, [{ Valor: '15.00' }]);
  mock.responder(/INSERT INTO ContadoresPedidosDiarios/i, { insertId: 1, affectedRows: 1 });
  mock.responder(/FROM ContadoresPedidosDiarios/i, [{ Ultimo: 42 }]);
  mock.responderInsert(/INSERT INTO Pedidos/i, 900);
  mock.responderInsert(/INSERT INTO PedidoItems/i, 5001);
  // El SELECT de vuelta que hace el shim para resolver INSERTED.FechaCreacion.
  mock.responder(/SELECT `FechaCreacion` FROM `Pedidos`/i, [{ FechaCreacion: new Date('2026-09-02T15:00:00Z') }]);
  mock.responder(/FROM DispositivosNotificacion|FROM Personas p/i, []);
  return mock;
}

/** Los valores con los que se llamó a cada INSERT INTO PedidoItems. */
function itemsInsertados(mock) {
  return mock.consultasQueMatcheen(/INSERT INTO PedidoItems/i).map((c) => c.valores);
}

/** El @Total con el que se insertó la cabecera. */
function totalDeLaCabecera(mock) {
  const consulta = mock.consultasQueMatcheen(/INSERT INTO Pedidos/i)[0];
  // El shim reemplaza los @Param por `?` en el orden en que aparecen en el
  // texto, así que se ubica el índice de @Total leyendo el propio SQL.
  const nombres = [...consulta.texto.matchAll(/\?/g)];
  return { valores: consulta.valores, cantidadParametros: nombres.length };
}

describe('crearPedido (personal) — carrito', () => {
  let mock;
  let pedidosController;

  beforeEach(() => {
    jest.resetModules();
    mock = instalarMockMysql();
    prepararMockBase(mock);
    pedidosController = require('../controllers/pedidosController');
  });

  test('con un solo ítem: una línea y el total es su subtotal', async () => {
    const req = crearReq({
      usuario: { rol: 'SUPERADMIN' },
      body: {
        idCliente: 5,
        items: [{ idProducto: 3, tipoPedido: 'UNIDADES', cantidad: 100, precioUnitario: 0.35 }],
      },
    });
    const res = crearRes();
    await pedidosController.crearPedido(req, res, (e) => {
      throw e;
    });

    expect(res.statusCode).toBe(201);
    expect(res.body.total).toBe(35);
    expect(res.body.items).toHaveLength(1);
    expect(res.body.items[0]).toMatchObject({
      idProducto: 3,
      producto: 'PAN FRANCES',
      cantidad: 100,
      precioUnitario: 0.35,
      subtotal: 35,
    });
    expect(itemsInsertados(mock)).toHaveLength(1);
    expect(mock.transaccion.commit).toBe(1);
    expect(mock.transaccion.rollback).toBe(0);
  });

  test('con varios ítems: un INSERT por línea y el total es la suma', async () => {
    const req = crearReq({
      usuario: { rol: 'SUPERADMIN' },
      body: {
        idCliente: 5,
        items: [
          { idProducto: 3, tipoPedido: 'UNIDADES', cantidad: 100, precioUnitario: 0.35 }, // 35.00
          { idProducto: 7, tipoPedido: 'UNIDADES', cantidad: 50, precioUnitario: 0.4 }, // 20.00
        ],
      },
    });
    const res = crearRes();
    await pedidosController.crearPedido(req, res, (e) => {
      throw e;
    });

    expect(res.statusCode).toBe(201);
    expect(res.body.total).toBe(55);
    expect(res.body.items).toHaveLength(2);
    expect(res.body.items.map((i) => i.subtotal)).toEqual([35, 20]);
    expect(itemsInsertados(mock)).toHaveLength(2);
    // La cabecera se inserta UNA sola vez, por más líneas que tenga.
    expect(mock.contar(/INSERT INTO Pedidos/i)).toBe(1);
    expect(totalDeLaCabecera(mock).valores).toContain(55);
    expect(mock.transaccion.commit).toBe(1);
  });

  test('productoResumen junta producto y cantidad de cada línea', async () => {
    const req = crearReq({
      usuario: { rol: 'SUPERADMIN' },
      body: {
        idCliente: 5,
        items: [
          { idProducto: 3, tipoPedido: 'UNIDADES', cantidad: 100, precioUnitario: 0.35 },
          { idProducto: 7, tipoPedido: 'UNIDADES', cantidad: 50, precioUnitario: 0.4 },
        ],
      },
    });
    const res = crearRes();
    await pedidosController.crearPedido(req, res, (e) => {
      throw e;
    });

    expect(res.body.productoResumen).toBe('PAN FRANCES x100, PAN DE AGUA x50');
  });

  test('ítems de dos tiendas distintas: 400 y ni un solo INSERT', async () => {
    const req = crearReq({
      usuario: { rol: 'SUPERADMIN' },
      body: {
        idCliente: 5,
        items: [
          { idProducto: 3, tipoPedido: 'UNIDADES', cantidad: 100, precioUnitario: 0.35 }, // tienda 1
          { idProducto: 9, tipoPedido: 'PAQUETES', cantidad: 2, precioUnitario: 15 }, // tienda 2
        ],
      },
    });
    const res = crearRes();
    await pedidosController.crearPedido(req, res, (e) => {
      throw e;
    });

    expect(res.statusCode).toBe(400);
    expect(res.body.mensaje).toMatch(/misma tienda/i);
    expect(mock.contar(/INSERT INTO Pedidos/i)).toBe(0);
    expect(mock.contar(/INSERT INTO PedidoItems/i)).toBe(0);
    expect(mock.transaccion.rollback).toBe(1);
    expect(mock.transaccion.commit).toBe(0);
  });

  test('un producto inválido a mitad del carrito: rollback, 400 y no 500', async () => {
    const req = crearReq({
      usuario: { rol: 'SUPERADMIN' },
      body: {
        idCliente: 5,
        items: [
          { idProducto: 3, tipoPedido: 'UNIDADES', cantidad: 100, precioUnitario: 0.35 },
          { idProducto: 999, tipoPedido: 'UNIDADES', cantidad: 10, precioUnitario: 1 }, // no existe
          { idProducto: 7, tipoPedido: 'UNIDADES', cantidad: 50, precioUnitario: 0.4 },
        ],
      },
    });
    const res = crearRes();
    const next = jest.fn();
    await pedidosController.crearPedido(req, res, next);

    expect(res.statusCode).toBe(400);
    // Un producto dado de baja es un error del pedido, no una falla del
    // servidor: nunca debe llegar al manejador de errores (que responde 500).
    expect(next).not.toHaveBeenCalled();
    expect(mock.transaccion.rollback).toBe(1);
    expect(mock.transaccion.commit).toBe(0);
    expect(mock.contar(/INSERT INTO PedidoItems/i)).toBe(0);
    // El tercer ítem ni siquiera se consulta: se corta en el que falló.
    expect(mock.contar(/FROM Productos p/i)).toBe(2);
  });

  test('si el INSERT de una línea revienta, hace rollback y no commit', async () => {
    jest.resetModules();
    mock = instalarMockMysql();
    // La regla del error va PRIMERO para ganarle a la genérica de inserts.
    mock.responderConError(/INSERT INTO PedidoItems/i, 'ER_LOCK_DEADLOCK');
    prepararMockBase(mock);
    pedidosController = require('../controllers/pedidosController');

    const req = crearReq({
      usuario: { rol: 'SUPERADMIN' },
      body: {
        idCliente: 5,
        items: [{ idProducto: 3, tipoPedido: 'UNIDADES', cantidad: 100, precioUnitario: 0.35 }],
      },
    });
    const res = crearRes();
    const next = jest.fn();
    await pedidosController.crearPedido(req, res, next);

    // Una caída real de la base sí es un 500: se delega a next(err).
    expect(next).toHaveBeenCalled();
    expect(mock.transaccion.rollback).toBe(1);
    expect(mock.transaccion.commit).toBe(0);
  });

  test('cliente inexistente: 404 sin tocar el catálogo', async () => {
    jest.resetModules();
    mock = instalarMockMysql();
    mock.responder(/FROM Clientes c/i, []);
    prepararMockBase(mock);
    pedidosController = require('../controllers/pedidosController');

    const req = crearReq({
      usuario: { rol: 'SUPERADMIN' },
      body: {
        idCliente: 404,
        items: [{ idProducto: 3, tipoPedido: 'UNIDADES', cantidad: 100, precioUnitario: 0.35 }],
      },
    });
    const res = crearRes();
    await pedidosController.crearPedido(req, res, (e) => {
      throw e;
    });

    expect(res.statusCode).toBe(404);
    expect(mock.contar(/FROM Productos p/i)).toBe(0);
    expect(mock.transaccion.rollback).toBe(1);
  });
});

describe('crearMiPedido (autoservicio del cliente) — carrito', () => {
  let mock;
  let pedidosController;

  beforeEach(() => {
    jest.resetModules();
    mock = instalarMockMysql();
    prepararMockBase(mock);
    pedidosController = require('../controllers/pedidosController');
  });

  test('el precio sale del catálogo, no del body, y suma bien', async () => {
    const req = crearReq({
      usuario: { rol: 'CLIENTE', idPersona: 3 },
      body: {
        items: [
          { idProducto: 3, cantidad: 100, precioUnitario: 999 }, // el 999 debe ignorarse
          { idProducto: 7, cantidad: 50 },
        ],
      },
    });
    const res = crearRes();
    await pedidosController.crearMiPedido(req, res, (e) => {
      throw e;
    });

    expect(res.statusCode).toBe(201);
    // 100 * 0.35 + 50 * 0.40 = 55, no lo que mandó el cliente.
    expect(res.body.total).toBe(55);
    expect(res.body.items.map((i) => i.precioUnitario)).toEqual([0.35, 0.4]);
    expect(itemsInsertados(mock)).toHaveLength(2);
    expect(mock.transaccion.commit).toBe(1);
  });

  test('el mínimo de 50 unidades se valida POR LÍNEA, no sobre el carrito', async () => {
    const req = crearReq({
      usuario: { rol: 'CLIENTE', idPersona: 3 },
      body: {
        items: [
          { idProducto: 3, cantidad: 60 }, // ok
          { idProducto: 7, cantidad: 10 }, // por debajo del mínimo
        ],
      },
    });
    const res = crearRes();
    await pedidosController.crearMiPedido(req, res, (e) => {
      throw e;
    });

    // 60 + 10 = 70 supera el mínimo sumando, pero la segunda línea no llega
    // a 50 unidades de SU producto: se rechaza igual.
    expect(res.statusCode).toBe(400);
    expect(res.body.mensaje).toMatch(/PAN DE AGUA/);
    expect(mock.contar(/INSERT INTO PedidoItems/i)).toBe(0);
    expect(mock.transaccion.rollback).toBe(1);
  });

  test('los paquetes de hamburguesa usan el precio de Configuraciones', async () => {
    const req = crearReq({
      usuario: { rol: 'CLIENTE', idPersona: 3 },
      body: { items: [{ idProducto: 9, cantidad: 2 }] },
    });
    const res = crearRes();
    await pedidosController.crearMiPedido(req, res, (e) => {
      throw e;
    });

    expect(res.statusCode).toBe(201);
    // PRECIO_PAQUETE = 15, no los 12 de Productos.PrecioUnitario.
    expect(res.body.items[0].precioUnitario).toBe(15);
    expect(res.body.items[0].tipoPedido).toBe('PAQUETES');
    expect(res.body.total).toBe(30);
  });

  test('carrito de dos tiendas distintas: 400 y rollback', async () => {
    const req = crearReq({
      usuario: { rol: 'CLIENTE', idPersona: 3 },
      body: {
        items: [
          { idProducto: 3, cantidad: 100 },
          { idProducto: 9, cantidad: 2 },
        ],
      },
    });
    const res = crearRes();
    await pedidosController.crearMiPedido(req, res, (e) => {
      throw e;
    });

    expect(res.statusCode).toBe(400);
    expect(res.body.mensaje).toMatch(/misma tienda/i);
    expect(mock.contar(/INSERT INTO Pedidos/i)).toBe(0);
    expect(mock.transaccion.rollback).toBe(1);
  });
});

describe('crearPedidoHorneado — carrito con atributos por línea', () => {
  let mock;
  let horneadosController;

  beforeEach(() => {
    jest.resetModules();
    mock = instalarMockMysql();
    prepararMockBase(mock);
    // Horneados no elige producto: usa el placeholder de su propia tienda,
    // resuelto una sola vez por request.
    mock.responder(/Nombre = 'Horneados'/i, [{ IdTienda: 3, IdProducto: 50, ProductoNombre: 'HORNEADO' }]);
    horneadosController = require('../controllers/horneadosController');
  });

  function itemHorneado(extra = {}) {
    return {
      carne: 'pollo',
      presentacion: 'entero',
      cantidad: 2,
      aplicaAderezo: false,
      precioHorneado: 20,
      ...extra,
    };
  }

  test('una línea: precio unitario = horneado (+ aderezo si aplica)', async () => {
    const req = crearReq({
      usuario: { rol: 'SUPERADMIN' },
      body: { idCliente: 5, items: [itemHorneado({ aplicaAderezo: true, tipoAderezo: 'CRIOLLO', precioAderezo: 3 })] },
    });
    const res = crearRes();
    await horneadosController.crearPedidoHorneado(req, res, (e) => {
      throw e;
    });

    expect(res.statusCode).toBe(201);
    expect(res.body.items[0].precioUnitario).toBe(23); // 20 + 3
    expect(res.body.total).toBe(46); // 23 * 2
    expect(mock.transaccion.commit).toBe(1);
  });

  test('dos líneas con carnes distintas: cada una guarda su propio detalle', async () => {
    const req = crearReq({
      usuario: { rol: 'SUPERADMIN' },
      body: {
        idCliente: 5,
        items: [
          itemHorneado({ carne: 'pollo', presentacion: 'entero', cantidad: 2, precioHorneado: 20 }),
          itemHorneado({
            carne: 'chancho',
            presentacion: 'trozado',
            cantidad: 1,
            precioHorneado: 30,
            aplicaAderezo: true,
            tipoAderezo: 'ORIENTAL',
            precioAderezo: 5,
          }),
        ],
      },
    });
    const res = crearRes();
    await horneadosController.crearPedidoHorneado(req, res, (e) => {
      throw e;
    });

    expect(res.statusCode).toBe(201);
    expect(mock.contar(/INSERT INTO PedidoItems/i)).toBe(2);
    // Un detalle por LÍNEA, no uno por pedido: es todo el punto del cambio.
    expect(mock.contar(/INSERT INTO PedidosHorneadosDetalle/i)).toBe(2);
    expect(res.body.items.map((i) => i.carne)).toEqual(['POLLO', 'CHANCHO']);
    expect(res.body.items.map((i) => i.tipoAderezo)).toEqual([null, 'ORIENTAL']);
    // 20*2 + 35*1
    expect(res.body.total).toBe(75);
    expect(mock.transaccion.commit).toBe(1);
  });

  test('el detalle se cuelga de IdPedidoItem, nunca más de IdPedido', async () => {
    const req = crearReq({
      usuario: { rol: 'SUPERADMIN' },
      body: { idCliente: 5, items: [itemHorneado()] },
    });
    const res = crearRes();
    await horneadosController.crearPedidoHorneado(req, res, () => {});

    const detalle = mock.consultasQueMatcheen(/INSERT INTO PedidosHorneadosDetalle/i)[0];
    expect(detalle.texto).toMatch(/IdPedidoItem/);
    expect(detalle.texto).not.toMatch(/\bIdPedido\b\s*,/);
  });

  test('carne repetida en dos líneas guarda la sugerencia una sola vez', async () => {
    const req = crearReq({
      usuario: { rol: 'SUPERADMIN' },
      body: {
        idCliente: 5,
        items: [
          itemHorneado({ carne: 'pollo', presentacion: 'entero' }),
          itemHorneado({ carne: 'pollo', presentacion: 'trozado' }),
        ],
      },
    });
    const res = crearRes();
    await horneadosController.crearPedidoHorneado(req, res, () => {});

    expect(res.statusCode).toBe(201);
    // 1 carne única + 2 presentaciones únicas = 3 sugerencias.
    expect(mock.contar(/INSERT IGNORE INTO SugerenciasCampo/i)).toBe(3);
  });

  test('cliente inexistente: 404 y rollback', async () => {
    jest.resetModules();
    mock = instalarMockMysql();
    mock.responder(/FROM Clientes c/i, []);
    prepararMockBase(mock);
    mock.responder(/Nombre = 'Horneados'/i, [{ IdTienda: 3, IdProducto: 50, ProductoNombre: 'HORNEADO' }]);
    horneadosController = require('../controllers/horneadosController');

    const req = crearReq({
      usuario: { rol: 'SUPERADMIN' },
      body: { idCliente: 404, items: [itemHorneado()] },
    });
    const res = crearRes();
    await horneadosController.crearPedidoHorneado(req, res, (e) => {
      throw e;
    });

    expect(res.statusCode).toBe(404);
    expect(mock.transaccion.rollback).toBe(1);
    expect(mock.transaccion.commit).toBe(0);
  });
});

describe('lectura de pedidos con sus líneas', () => {
  let mock;
  let pedidosController;

  beforeEach(() => {
    jest.resetModules();
    mock = instalarMockMysql();
    pedidosController = require('../controllers/pedidosController');
  });

  test('mapearFilaPedido arma items y productoResumen a partir de las líneas', () => {
    const pedido = pedidosController.mapearFilaPedido(
      {
        IdPedido: 900,
        NumeroPedidoDia: 42,
        IdCliente: 5,
        IdTienda: 1,
        TiendaNombre: 'Panadería',
        Total: 55,
        Estado: 'PENDIENTE',
        FechaCreacion: new Date('2026-09-02T15:00:00Z'),
      },
      [
        {
          IdPedidoItem: 1, IdPedido: 900, IdProducto: 3, ProductoNombre: 'PAN FRANCES',
          TipoPedido: 'UNIDADES', Cantidad: 100, PrecioUnitario: 0.35, Subtotal: 35,
          Carne: null, Presentacion: null, AplicaAderezo: null, TipoAderezo: null, PrecioAderezo: null,
        },
        {
          IdPedidoItem: 2, IdPedido: 900, IdProducto: 7, ProductoNombre: 'PAN DE AGUA',
          TipoPedido: 'UNIDADES', Cantidad: 50, PrecioUnitario: 0.4, Subtotal: 20,
          Carne: null, Presentacion: null, AplicaAderezo: null, TipoAderezo: null, PrecioAderezo: null,
        },
      ],
    );

    expect(pedido.items).toHaveLength(2);
    expect(pedido.productoResumen).toBe('PAN FRANCES x100, PAN DE AGUA x50');
    expect(pedido.total).toBe(55);
    // Los campos de Horneados llegan null en una tienda de catálogo simple.
    expect(pedido.items[0].carne).toBeNull();
    expect(pedido.items[0].aplicaAderezo).toBeNull();
  });

  test('una línea de Horneados conserva sus atributos propios', () => {
    const pedido = pedidosController.mapearFilaPedido(
      {
        IdPedido: 901, NumeroPedidoDia: 1, IdCliente: 5, IdTienda: 3,
        TiendaNombre: 'Horneados', Total: 46, Estado: 'PENDIENTE',
        FechaCreacion: new Date('2026-09-02T15:00:00Z'),
      },
      [
        {
          IdPedidoItem: 9, IdPedido: 901, IdProducto: 50, ProductoNombre: 'HORNEADO',
          TipoPedido: 'UNIDADES', Cantidad: 2, PrecioUnitario: 23, Subtotal: 46,
          Carne: 'POLLO', Presentacion: 'ENTERO', AplicaAderezo: 1, TipoAderezo: 'CRIOLLO', PrecioAderezo: 3,
        },
      ],
    );

    expect(pedido.items[0]).toMatchObject({
      carne: 'POLLO',
      presentacion: 'ENTERO',
      aplicaAderezo: true, // 1 (tinyint de MariaDB) -> booleano
      tipoAderezo: 'CRIOLLO',
      precioAderezo: 3,
    });
    // El resumen usa la carne: "HORNEADO x2" no diría nada.
    expect(pedido.productoResumen).toBe('POLLO x2');
  });

  test('un pedido sin líneas no revienta: items vacío y resumen vacío', () => {
    const pedido = pedidosController.mapearFilaPedido({
      IdPedido: 902, NumeroPedidoDia: 2, IdCliente: 5, IdTienda: 1,
      Total: 0, Estado: 'PENDIENTE', FechaCreacion: new Date(),
    });
    expect(pedido.items).toEqual([]);
    expect(pedido.productoResumen).toBe('');
  });

  test('la auditoría solo aparece cuando se pide explícitamente', () => {
    const fila = {
      IdPedido: 903, NumeroPedidoDia: 3, IdCliente: 5, IdTienda: 1, Total: 10,
      Estado: 'ENTREGADO', FechaCreacion: new Date(),
      VendedorNombres: 'ANA', VendedorApellidoPaterno: 'LOPEZ', VendedorRol: 'ADMIN',
    };
    expect(pedidosController.mapearFilaPedido(fila, []).registradoPorRol).toBeUndefined();
    expect(pedidosController.mapearFilaPedido(fila, [], true).registradoPorRol).toBe('ADMIN');
  });

  test('obtenerItemsPorPedidos agrupa por IdPedido y no consulta si no hay pedidos', async () => {
    mock.responder(/FROM PedidoItems pi/i, [
      { IdPedidoItem: 1, IdPedido: 900, IdProducto: 3, ProductoNombre: 'PAN FRANCES', Cantidad: 100 },
      { IdPedidoItem: 2, IdPedido: 900, IdProducto: 7, ProductoNombre: 'PAN DE AGUA', Cantidad: 50 },
      { IdPedidoItem: 3, IdPedido: 901, IdProducto: 3, ProductoNombre: 'PAN FRANCES', Cantidad: 10 },
    ]);
    const { getPool } = require('../config/db');
    const pool = await getPool();

    const vacio = await pedidosController.obtenerItemsPorPedidos(pool, []);
    expect(vacio.size).toBe(0);
    expect(mock.contar(/FROM PedidoItems pi/i)).toBe(0);

    const mapa = await pedidosController.obtenerItemsPorPedidos(pool, [900, 901]);
    expect(mapa.get(900)).toHaveLength(2);
    expect(mapa.get(901)).toHaveLength(1);
    // Una sola consulta para todo el lote: nada de N+1.
    expect(mock.contar(/FROM PedidoItems pi/i)).toBe(1);
  });

  test('los IDs se interpolan como números, nunca como texto del request', async () => {
    mock.responder(/FROM PedidoItems pi/i, []);
    const { getPool } = require('../config/db');
    const pool = await getPool();

    await pedidosController.obtenerItemsPorPedidos(pool, ['1; DROP TABLE Pedidos', 2]);
    const consulta = mock.consultasQueMatcheen(/FROM PedidoItems pi/i)[0];
    expect(consulta.texto).not.toMatch(/DROP TABLE/i);
    expect(consulta.texto).toMatch(/IN \(NaN,2\)/);
  });
});
