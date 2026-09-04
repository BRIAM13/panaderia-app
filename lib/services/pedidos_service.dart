import '../models/pedido_model.dart';
import 'api_client.dart';
import 'secure_storage_service.dart';

// `Pedido`, `ItemPedido`, `PedidoResultado` y `PedidoClienteResumen` viven
// en models/pedido_model.dart (los comparten Hamburguesas, Panadería,
// Horneados y el hub del cliente). Se reexportan acá para que las pantallas
// que ya importaban este servicio no necesiten un import extra.
export '../models/pedido_model.dart';

/// Una línea del carrito que el PERSONAL está por registrar: el precio lo
/// negocia el vendedor en pantalla, así que va explícito (a diferencia de
/// [NuevoItemAutoservicio], donde siempre sale del catálogo).
class NuevoItemPedido {
  const NuevoItemPedido({
    required this.idProducto,
    required this.producto,
    required this.tipoPedido,
    required this.cantidad,
    required this.precioUnitario,
  });

  final int idProducto;

  /// Solo para mostrar la línea en el carrito antes de enviarla — no se
  /// manda al backend, que resuelve el nombre por [idProducto].
  final String producto;

  /// 'UNIDADES' | 'PAQUETES'.
  final String tipoPedido;
  final int cantidad;
  final double precioUnitario;

  double get subtotal => precioUnitario * cantidad;

  Map<String, dynamic> toJson() => {
    'idProducto': idProducto,
    'tipoPedido': tipoPedido,
    'cantidad': cantidad,
    'precioUnitario': precioUnitario,
  };
}

/// Una línea del carrito de un CLIENTE (autoservicio): sin precio — el
/// backend lo toma del catálogo, nadie está ahí para negociarlo.
class NuevoItemAutoservicio {
  const NuevoItemAutoservicio({
    required this.idProducto,
    required this.producto,
    required this.cantidad,
    required this.precioUnitario,
    required this.esPaquete,
  });

  final int idProducto;

  /// Nombre y precio de catálogo: solo para pintar el carrito y su total
  /// antes de enviar. El backend recalcula el precio, nunca confía en este.
  final String producto;
  final double precioUnitario;
  final bool esPaquete;
  final int cantidad;

  double get subtotal => precioUnitario * cantidad;

  Map<String, dynamic> toJson() => {'idProducto': idProducto, 'cantidad': cantidad};
}

/// Un producto del catálogo de autoservicio — mismo catálogo que ve un
/// visitante sin cuenta en la página web (GET /publico/catalogo), reusado
/// acá porque no necesita token y evita duplicar la lista de productos con
/// precio fijo en dos lugares.
class ProductoAutoservicio {
  const ProductoAutoservicio({
    required this.idProducto,
    required this.nombre,
    required this.precioUnitario,
    required this.esPaquete,
  });

  factory ProductoAutoservicio.fromJson(Map<String, dynamic> json) =>
      ProductoAutoservicio(
        idProducto: json['idProducto'] as int,
        nombre: json['nombre'] as String,
        precioUnitario: (json['precioUnitario'] as num).toDouble(),
        esPaquete: json['esPaquete'] as bool? ?? false,
      );

  final int idProducto;
  final String nombre;

  /// Precio del paquete de 12 (pan de hamburguesa) o de la unidad (resto del
  /// catálogo) — ver [esPaquete].
  final double precioUnitario;

  /// true: se vende por paquete de 12 a precio fijo (pan de hamburguesa), no
  /// por unidad suelta como el resto del catálogo.
  final bool esPaquete;
}

class PedidosService {
  PedidosService({ApiClient? apiClient, SecureStorageService? secureStorage})
    : _api = apiClient ?? const ApiClient(),
      _storage = secureStorage ?? SecureStorageService();

  final ApiClient _api;
  final SecureStorageService _storage;

  /// Personal: registra un pedido con uno o varios productos. Todos los
  /// productos deben ser de la misma tienda — el backend lo rechaza con 400
  /// si no (ver crearPedido en pedidosController.js).
  Future<PedidoResultado> crear({
    required int idCliente,
    required List<NuevoItemPedido> items,
    DateTime? fechaEntrega,
    String? notas,
  }) async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.post('/pedidos', {
      'idCliente': idCliente,
      'items': items.map((i) => i.toJson()).toList(),
      'fechaEntrega': fechaEntrega?.toUtc().toIso8601String(),
      'notas': notas,
    }, token: token);
    return PedidoResultado.fromJson(data);
  }

  /// Pedidos de UNA tienda de catálogo simple (Hamburguesas o Panadería) —
  /// Horneados tiene su propio servicio dedicado (`HorneadosService`).
  Future<List<Pedido>> listar({required int idTienda}) async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.get('/pedidos?idTienda=$idTienda', token: token);
    final lista = data['pedidos'] as List<dynamic>? ?? const [];
    return lista
        .map((e) => Pedido.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Autoservicio (rol CLIENTE): solo sus propios pedidos. Los rechazados
  /// ya vienen excluidos desde el backend.
  Future<List<Pedido>> misPedidos() async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.get('/pedidos/mis-pedidos', token: token);
    final lista = data['pedidos'] as List<dynamic>? ?? const [];
    return lista
        .map((e) => Pedido.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Autoservicio (rol CLIENTE): el propio cliente registra su pedido con
  /// uno o varios productos. El precio siempre sale del catálogo del
  /// producto elegido — nadie lo negocia; la tienda y el tipo de pedido
  /// (paquete/unidad) se derivan en el backend a partir de cada
  /// `idProducto`, no hace falta enviarlos. Nace como "solicitado", a la
  /// espera de que el personal lo confirme.
  Future<PedidoResultado> crearComoCliente({
    required List<NuevoItemAutoservicio> items,
    DateTime? fechaEntrega,
    String? notas,
  }) async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.post('/pedidos/mi-pedido', {
      'items': items.map((i) => i.toJson()).toList(),
      'fechaEntrega': fechaEntrega?.toUtc().toIso8601String(),
      'notas': notas,
    }, token: token);
    return PedidoResultado.fromJson(data);
  }

  /// Catálogo de autoservicio (mismo que ve un visitante sin cuenta en la
  /// página web) — sin token: cualquier cliente autenticado lo ve igual que
  /// uno anónimo, no hay nada sensible en un catálogo de precios públicos.
  Future<List<ProductoAutoservicio>> catalogoAutoservicio() async {
    final data = await _api.get('/publico/catalogo');
    final lista = data['productos'] as List<dynamic>? ?? const [];
    return lista
        .map((e) => ProductoAutoservicio.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Personal: acepta un pedido solicitado por un cliente.
  Future<void> aprobar(int idPedido) async {
    final token = await _storage.obtenerAccessToken();
    await _api.put('/pedidos/$idPedido/aprobar', const {}, token: token);
  }

  /// Personal: rechaza un pedido solicitado (ej. no hay stock).
  Future<void> rechazar(int idPedido) async {
    final token = await _storage.obtenerAccessToken();
    await _api.put('/pedidos/$idPedido/rechazar', const {}, token: token);
  }

  /// Personal: marca un pedido confirmado como entregado, indicando si se
  /// pagó al momento o quedó como deuda.
  Future<void> entregar(int idPedido, {required bool pagado}) async {
    final token = await _storage.obtenerAccessToken();
    await _api.put('/pedidos/$idPedido/entregar', {
      'pagado': pagado,
    }, token: token);
  }

  /// Personal: cancela un pedido (SOLICITADO o PENDIENTE) de su tienda —
  /// ej. ya se había confirmado pero por algún motivo no se puede cumplir.
  /// Distinto de [cancelarMiPedido], que es el autoservicio del cliente.
  Future<void> cancelar(int idPedido) async {
    final token = await _storage.obtenerAccessToken();
    await _api.put('/pedidos/$idPedido/cancelar', const {}, token: token);
  }

  /// Personal: pedidos entregados con deuda pendiente, de UNA tienda de
  /// catálogo simple (Hamburguesas o Panadería).
  Future<List<Pedido>> listarDeudas({required int idTienda}) async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.get(
      '/pedidos/deudas?idTienda=$idTienda',
      token: token,
    );
    final lista = data['pedidos'] as List<dynamic>? ?? const [];
    return lista
        .map((e) => Pedido.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Personal: salda una deuda manualmente (efectivo/Yape confirmado en
  /// persona) — el pago real por distintos medios llega más adelante.
  Future<void> marcarDeudaPagada(int idPedido) async {
    final token = await _storage.obtenerAccessToken();
    await _api.put(
      '/pedidos/$idPedido/marcar-deuda-pagada',
      const {},
      token: token,
    );
  }

  /// Autoservicio (rol CLIENTE): cancela un pedido propio, siempre que
  /// todavía no haya sido entregado (SOLICITADO o PENDIENTE).
  Future<void> cancelarMiPedido(int idPedido) async {
    final token = await _storage.obtenerAccessToken();
    await _api.put(
      '/pedidos/mis-pedidos/$idPedido/cancelar',
      const {},
      token: token,
    );
  }
}
