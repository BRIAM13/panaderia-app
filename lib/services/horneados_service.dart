import 'api_client.dart';
import 'pedidos_service.dart';
import 'secure_storage_service.dart';

/// Resultado de registrar un pedido de Horneados — igual espíritu que
/// [PedidoResultado] pero con los campos propios de este rubro (carne,
/// presentación, aderezo) que `Pedidos` no tiene dónde guardar.
class PedidoHorneadoResultado {
  const PedidoHorneadoResultado({
    required this.idPedido,
    required this.numeroPedidoDia,
    required this.carne,
    required this.presentacion,
    required this.cantidad,
    required this.aplicaAderezo,
    required this.tipoAderezo,
    required this.precioHorneado,
    required this.precioAderezo,
    required this.precioUnitario,
    required this.total,
    required this.fechaEntrega,
    required this.fechaCreacion,
    required this.cliente,
  });

  factory PedidoHorneadoResultado.fromJson(Map<String, dynamic> json) =>
      PedidoHorneadoResultado(
        idPedido: json['idPedido'] as int,
        numeroPedidoDia: json['numeroPedidoDia'] as int? ?? 0,
        carne: json['carne'] as String,
        presentacion: json['presentacion'] as String,
        cantidad: json['cantidad'] as int,
        aplicaAderezo: json['aplicaAderezo'] as bool? ?? false,
        tipoAderezo: json['tipoAderezo'] as String?,
        precioHorneado: (json['precioHorneado'] as num).toDouble(),
        precioAderezo: (json['precioAderezo'] as num?)?.toDouble(),
        precioUnitario: (json['precioUnitario'] as num).toDouble(),
        total: (json['total'] as num).toDouble(),
        fechaEntrega: json['fechaEntrega'] != null
            ? DateTime.parse(json['fechaEntrega'] as String).toLocal()
            : null,
        fechaCreacion: DateTime.parse(
          json['fechaCreacion'] as String,
        ).toLocal(),
        cliente: PedidoClienteResumen.fromJson(
          json['cliente'] as Map<String, dynamic>,
        ),
      );

  final int idPedido;
  final int numeroPedidoDia;
  final String carne;
  final String presentacion;
  final int cantidad;
  final bool aplicaAderezo;
  final String? tipoAderezo;
  final double precioHorneado;
  final double? precioAderezo;
  final double precioUnitario;
  final double total;
  final DateTime? fechaEntrega;
  final DateTime fechaCreacion;
  final PedidoClienteResumen cliente;
}

/// Un pedido de Horneados ya registrado, tal como lo devuelve
/// `GET /horneados/pedidos` o `/horneados/deudas` — el backend fusiona las
/// columnas normales de `Pedidos` (mismo shape que [Pedido]) con el detalle
/// propio de este rubro, así que acá se separan de nuevo en dos objetos:
/// [pedido] para todo lo genérico (estado, cliente, fechas, acciones vía
/// [PedidosService], que ya son válidas para cualquier tienda) y los campos
/// sueltos para lo que solo tiene sentido en Horneados.
class PedidoHorneado {
  const PedidoHorneado({
    required this.pedido,
    this.carne,
    this.presentacion,
    this.aplicaAderezo = false,
    this.tipoAderezo,
    this.precioAderezo,
  });

  factory PedidoHorneado.fromJson(Map<String, dynamic> json) =>
      PedidoHorneado(
        pedido: Pedido.fromJson(json),
        carne: json['carne'] as String?,
        presentacion: json['presentacion'] as String?,
        aplicaAderezo: json['aplicaAderezo'] as bool? ?? false,
        tipoAderezo: json['tipoAderezo'] as String?,
        precioAderezo: (json['precioAderezo'] as num?)?.toDouble(),
      );

  final Pedido pedido;
  final String? carne;
  final String? presentacion;
  final bool aplicaAderezo;
  final String? tipoAderezo;
  final double? precioAderezo;
}

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

  Future<PedidoHorneadoResultado> crearPedido({
    required int idCliente,
    required String carne,
    required String presentacion,
    required int cantidad,
    required bool aplicaAderezo,
    String? tipoAderezo,
    required double precioHorneado,
    double? precioAderezo,
    DateTime? fechaEntrega,
    String? notas,
  }) async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.post('/horneados/pedidos', {
      'idCliente': idCliente,
      'carne': carne,
      'presentacion': presentacion,
      'cantidad': cantidad,
      'aplicaAderezo': aplicaAderezo,
      'tipoAderezo': aplicaAderezo ? tipoAderezo : null,
      'precioHorneado': precioHorneado,
      'precioAderezo': aplicaAderezo ? precioAderezo : null,
      'fechaEntrega': fechaEntrega?.toUtc().toIso8601String(),
      'notas': notas,
    }, token: token);
    return PedidoHorneadoResultado.fromJson(data);
  }

  Future<List<PedidoHorneado>> listarPedidos() async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.get('/horneados/pedidos', token: token);
    final lista = data['pedidos'] as List<dynamic>? ?? const [];
    return lista
        .map((e) => PedidoHorneado.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<PedidoHorneado>> listarDeudas() async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.get('/horneados/deudas', token: token);
    final lista = data['pedidos'] as List<dynamic>? ?? const [];
    return lista
        .map((e) => PedidoHorneado.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
