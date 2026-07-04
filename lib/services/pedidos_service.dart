import '../models/cliente_model.dart';
import 'api_client.dart';
import 'secure_storage_service.dart';

/// Datos mínimos del cliente que trae la respuesta de creación de un
/// pedido — suficientes para armar el resumen post-registro sin tener que
/// volver a pedir la lista completa de clientes.
class PedidoClienteResumen {
  const PedidoClienteResumen({
    required this.dni,
    required this.nombres,
    required this.apellidoPaterno,
    required this.apellidoMaterno,
    required this.descripcionNegocio,
  });

  factory PedidoClienteResumen.fromJson(Map<String, dynamic> json) =>
      PedidoClienteResumen(
        dni: json['dni'] as String?,
        nombres: json['nombres'] as String? ?? '',
        apellidoPaterno: json['apellidoPaterno'] as String? ?? '',
        apellidoMaterno: json['apellidoMaterno'] as String?,
        descripcionNegocio: json['descripcionNegocio'] as String?,
      );

  final String? dni;
  final String nombres;
  final String apellidoPaterno;
  final String? apellidoMaterno;
  final String? descripcionNegocio;

  /// RUC (persona natural o jurídica) muestra solo la razón social; DNI o
  /// sin documento muestran nombre completo con apellidos — misma regla
  /// que [Cliente.nombreParaMostrar].
  String get nombreParaMostrar {
    final esRuc =
        tipoDocumentoDesde(dni) == TipoClienteDocumento.rucPersonaNatural ||
        tipoDocumentoDesde(dni) == TipoClienteDocumento.rucPersonaJuridica;
    if (esRuc) return nombres;
    return [
      nombres,
      apellidoPaterno,
      apellidoMaterno,
    ].where((s) => s != null && s.trim().isNotEmpty).join(' ');
  }

  String? get nombreComercial =>
      (descripcionNegocio != null && descripcionNegocio!.trim().isNotEmpty)
      ? descripcionNegocio
      : null;
}

class PedidoResultado {
  const PedidoResultado({
    required this.idPedido,
    required this.precioUnitario,
    required this.total,
    required this.fechaEntrega,
    required this.fechaCreacion,
    required this.cliente,
  });

  factory PedidoResultado.fromJson(Map<String, dynamic> json) =>
      PedidoResultado(
        idPedido: json['idPedido'] as int,
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
  final double precioUnitario;
  final double total;
  final DateTime? fechaEntrega;
  final DateTime fechaCreacion;
  final PedidoClienteResumen cliente;
}

class PedidosService {
  PedidosService({ApiClient? apiClient, SecureStorageService? secureStorage})
    : _api = apiClient ?? const ApiClient(),
      _storage = secureStorage ?? SecureStorageService();

  final ApiClient _api;
  final SecureStorageService _storage;

  Future<PedidoResultado> crear({
    required int idCliente,
    required String tipoPedido,
    required int cantidad,
    required double precioUnitario,
    DateTime? fechaEntrega,
    String? notas,
  }) async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.post('/pedidos', {
      'idCliente': idCliente,
      'tipoPedido': tipoPedido,
      'cantidad': cantidad,
      'precioUnitario': precioUnitario,
      'fechaEntrega': fechaEntrega?.toUtc().toIso8601String(),
      'notas': notas,
    }, token: token);
    return PedidoResultado.fromJson(data);
  }

  Future<List<Pedido>> listar() async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.get('/pedidos', token: token);
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

  /// Autoservicio (rol CLIENTE): el propio cliente registra su pedido. El
  /// precio siempre sale del catálogo de la tienda — nadie lo negocia. Nace
  /// como "solicitado", a la espera de que el personal lo confirme.
  Future<PedidoResultado> crearComoCliente({
    required int idTienda,
    required String tipoPedido,
    required int cantidad,
    DateTime? fechaEntrega,
    String? notas,
  }) async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.post('/pedidos/mi-pedido', {
      'idTienda': idTienda,
      'tipoPedido': tipoPedido,
      'cantidad': cantidad,
      'fechaEntrega': fechaEntrega?.toUtc().toIso8601String(),
      'notas': notas,
    }, token: token);
    return PedidoResultado.fromJson(data);
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

  /// Personal: pedidos entregados con deuda pendiente, de sus tiendas.
  Future<List<Pedido>> listarDeudas() async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.get('/pedidos/deudas', token: token);
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

/// Un pedido ya registrado, tal como lo devuelve `GET /pedidos`.
class Pedido {
  const Pedido({
    required this.idPedido,
    required this.idCliente,
    required this.idTienda,
    required this.tienda,
    required this.tipoPedido,
    required this.cantidad,
    required this.precioUnitario,
    required this.total,
    required this.fechaEntrega,
    required this.estado,
    required this.estadoPago,
    required this.fechaEntregaReal,
    required this.notas,
    required this.fechaCreacion,
    required this.cliente,
    required this.producto,
    required this.vendedor,
  });

  factory Pedido.fromJson(Map<String, dynamic> json) => Pedido(
    idPedido: json['idPedido'] as int,
    idCliente: json['idCliente'] as int,
    idTienda: json['idTienda'] as int?,
    tienda: json['tienda'] as String?,
    tipoPedido: json['tipoPedido'] as String,
    cantidad: json['cantidad'] as int,
    precioUnitario: (json['precioUnitario'] as num).toDouble(),
    total: (json['total'] as num).toDouble(),
    fechaEntrega: json['fechaEntrega'] != null
        ? DateTime.parse(json['fechaEntrega'] as String).toLocal()
        : null,
    estado: json['estado'] as String,
    estadoPago: json['estadoPago'] as String?,
    fechaEntregaReal: json['fechaEntregaReal'] != null
        ? DateTime.parse(json['fechaEntregaReal'] as String).toLocal()
        : null,
    notas: json['notas'] as String?,
    fechaCreacion: DateTime.parse(json['fechaCreacion'] as String).toLocal(),
    cliente: PedidoClienteResumen.fromJson(
      json['cliente'] as Map<String, dynamic>,
    ),
    producto: json['producto'] as String,
    // null si lo registró el propio cliente (autoservicio), no el personal.
    vendedor: json['vendedor'] as String?,
  );

  final int idPedido;
  final int idCliente;
  final int? idTienda;
  final String? tienda;
  final String tipoPedido;
  final int cantidad;
  final double precioUnitario;
  final double total;
  final DateTime? fechaEntrega;
  // 'SOLICITADO' | 'PENDIENTE' | 'RECHAZADO' | 'ENTREGADO' | 'CANCELADO'
  final String estado;
  // 'PAGADO' | 'DEUDA' | null (null hasta que esté ENTREGADO)
  final String? estadoPago;
  final DateTime? fechaEntregaReal;
  final String? notas;
  final DateTime fechaCreacion;
  final PedidoClienteResumen cliente;
  final String producto;
  final String? vendedor;

  bool get esSolicitado => estado == 'SOLICITADO';
  bool get esEntregado => estado == 'ENTREGADO';
  bool get esDeuda => estadoPago == 'DEUDA';

  /// Ya se resolvió (entregado, rechazado o cancelado) — no necesita más
  /// acción ni debe agruparse por fecha programada (ver Historial en
  /// ListaPedidosPorSeccion). Solo SOLICITADO/PENDIENTE siguen "activos".
  bool get esFinalizado =>
      estado == 'ENTREGADO' || estado == 'RECHAZADO' || estado == 'CANCELADO';

  /// El cliente puede cancelarlo mientras no se haya entregado todavía.
  bool get sePuedeCancelar => estado == 'SOLICITADO' || estado == 'PENDIENTE';
}
