import '../models/pedido_model.dart';
import 'api_client.dart';
import 'secure_storage_service.dart';

// Horneados devuelve los mismos `Pedido`/`PedidoResultado` que el resto de
// las tiendas (ver la nota de la clase de abajo): se reexportan para que
// sus pantallas no necesiten un import extra.
export '../models/pedido_model.dart';

/// Una línea del carrito de Horneados que el vendedor está por registrar.
/// A diferencia de las otras tiendas, acá no se elige un producto de un
/// catálogo (Horneados tiene uno solo, placeholder): lo que distingue a
/// cada línea son sus atributos propios y su precio, que el vendedor
/// negocia en el momento.
class NuevoItemHorneado {
  const NuevoItemHorneado({
    required this.carne,
    required this.presentacion,
    required this.cantidad,
    required this.aplicaAderezo,
    this.tipoAderezo,
    required this.precioHorneado,
    this.precioAderezo,
  });

  final String carne;
  final String presentacion;
  final int cantidad;
  final bool aplicaAderezo;

  /// 'CRIOLLO' | 'ORIENTAL' — solo cuando [aplicaAderezo].
  final String? tipoAderezo;
  final double precioHorneado;
  final double? precioAderezo;

  /// Lo que cuesta una unidad de esta línea: el horneado más el aderezo si
  /// aplica (misma cuenta que hace el backend, replicada acá solo para
  /// mostrar el total del carrito antes de enviarlo).
  double get precioUnitario =>
      precioHorneado + (aplicaAderezo ? (precioAderezo ?? 0) : 0);

  double get subtotal => precioUnitario * cantidad;

  Map<String, dynamic> toJson() => {
    'carne': carne,
    'presentacion': presentacion,
    'cantidad': cantidad,
    'aplicaAderezo': aplicaAderezo,
    'tipoAderezo': aplicaAderezo ? tipoAderezo : null,
    'precioHorneado': precioHorneado,
    'precioAderezo': aplicaAderezo ? precioAderezo : null,
  };
}

/// Horneados usa el MISMO shape de pedido que el resto de las tiendas: sus
/// campos propios (carne, presentación, aderezo) viven en cada
/// [ItemPedido], no en un objeto aparte. Por eso ya no existen
/// `PedidoHorneado`/`PedidoHorneadoResultado`.
class HorneadosService {
  HorneadosService({ApiClient? apiClient, SecureStorageService? secureStorage})
    : _api = apiClient ?? const ApiClient(),
      _storage = secureStorage ?? SecureStorageService();

  final ApiClient _api;
  final SecureStorageService _storage;

  /// [campo]: 'CARNE' o 'PRESENTACION'. Sin [q]: las más usadas
  /// recientemente. Con [q]: solo las que empiezan con ese texto.
  Future<List<String>> sugerencias(String campo, {String q = ''}) async {
    final token = await _storage.obtenerAccessToken();
    final query = q.trim().isEmpty
        ? '?campo=$campo'
        : '?campo=$campo&q=${Uri.encodeQueryComponent(q.trim())}';
    final data = await _api.get('/horneados/sugerencias$query', token: token);
    final lista = data['sugerencias'] as List<dynamic>? ?? const [];
    return lista.map((e) => e.toString()).toList();
  }

  /// Registra un pedido de Horneados con una o varias líneas — cada una con
  /// su propia carne, presentación y aderezo.
  Future<PedidoResultado> crearPedido({
    required int idCliente,
    required List<NuevoItemHorneado> items,
    DateTime? fechaEntrega,
    String? notas,
  }) async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.post('/horneados/pedidos', {
      'idCliente': idCliente,
      'items': items.map((i) => i.toJson()).toList(),
      'fechaEntrega': fechaEntrega?.toUtc().toIso8601String(),
      'notas': notas,
    }, token: token);
    return PedidoResultado.fromJson(data);
  }

  Future<List<Pedido>> listarPedidos() async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.get('/horneados/pedidos', token: token);
    final lista = data['pedidos'] as List<dynamic>? ?? const [];
    return lista
        .map((e) => Pedido.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Pedido>> listarDeudas() async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.get('/horneados/deudas', token: token);
    final lista = data['pedidos'] as List<dynamic>? ?? const [];
    return lista
        .map((e) => Pedido.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
