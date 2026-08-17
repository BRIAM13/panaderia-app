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
    required this.numeroPedidoDia,
    this.tienda,
    this.producto,
    this.tipoPedido,
    required this.precioUnitario,
    required this.total,
    required this.fechaEntrega,
    required this.fechaCreacion,
    required this.cliente,
  });

  factory PedidoResultado.fromJson(Map<String, dynamic> json) =>
      PedidoResultado(
        idPedido: json['idPedido'] as int,
        numeroPedidoDia: json['numeroPedidoDia'] as int? ?? 0,
        tienda: json['tienda'] as String?,
        producto: json['producto'] as String?,
        tipoPedido: json['tipoPedido'] as String?,
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

  /// Correlativo #1, #2... que empieza de nuevo cada día calendario (hora
  /// de Perú), independiente por tienda — es lo que se le muestra al
  /// personal/cliente ("Pedido #N"), nunca [idPedido] (la PK real, que
  /// sigue siendo lo único válido para llamar a /pedidos/:id/...).
  final int numeroPedidoDia;

  /// Solo vienen en la respuesta de [PedidosService.crearComoCliente] (ver
  /// crearMiPedido en pedidosController.js) — [PedidosService.crear] (el
  /// personal negociando en el momento) no los incluye.
  final String? tienda;
  final String? producto;
  final String? tipoPedido;
  final double precioUnitario;
  final double total;
  final DateTime? fechaEntrega;
  final DateTime fechaCreacion;
  final PedidoClienteResumen cliente;
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

  Future<PedidoResultado> crear({
    required int idCliente,
    required int idProducto,
    required String tipoPedido,
    required int cantidad,
    required double precioUnitario,
    DateTime? fechaEntrega,
    String? notas,
  }) async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.post('/pedidos', {
      'idCliente': idCliente,
      'idProducto': idProducto,
      'tipoPedido': tipoPedido,
      'cantidad': cantidad,
      'precioUnitario': precioUnitario,
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

  /// Autoservicio (rol CLIENTE): el propio cliente registra su pedido. El
  /// precio siempre sale del catálogo del producto elegido — nadie lo
  /// negocia; la tienda y el tipo de pedido (paquete/unidad) se derivan en
  /// el backend a partir de [idProducto], no hace falta enviarlos. Nace
  /// como "solicitado", a la espera de que el personal lo confirme.
  Future<PedidoResultado> crearComoCliente({
    required int idProducto,
    required int cantidad,
    DateTime? fechaEntrega,
    String? notas,
  }) async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.post('/pedidos/mi-pedido', {
      'idProducto': idProducto,
      'cantidad': cantidad,
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

/// Un pedido ya registrado, tal como lo devuelve `GET /pedidos`.
class Pedido {
  const Pedido({
    required this.idPedido,
    required this.numeroPedidoDia,
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
    this.registradoPorRol,
    this.aprobadoPor,
    this.canceladoPor,
    this.entregadoPor,
  });

  factory Pedido.fromJson(Map<String, dynamic> json) => Pedido(
    idPedido: json['idPedido'] as int,
    numeroPedidoDia: json['numeroPedidoDia'] as int? ?? 0,
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
    // Estos 4 solo vienen del backend si quien pide la lista es
    // ADMIN/SUPERADMIN (ver pedidosController.js) — para TRABAJADOR o el
    // propio cliente siempre llegan null.
    registradoPorRol: json['registradoPorRol'] as String?,
    aprobadoPor: json['aprobadoPor'] as String?,
    canceladoPor: json['canceladoPor'] as String?,
    entregadoPor: json['entregadoPor'] as String?,
  );

  final int idPedido;

  /// Correlativo #1, #2... que empieza de nuevo cada día calendario (hora
  /// de Perú), independiente por tienda — es lo que se muestra al personal/
  /// cliente ("Pedido #N"), nunca [idPedido] (la PK real que identifica el
  /// pedido en /pedidos/:id/...).
  final int numeroPedidoDia;
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

  /// Visibles solo para ADMIN/SUPERADMIN (el backend ya filtra esto, no
  /// hace falta repetir el chequeo de rol acá — si no corresponde, llegan
  /// null y la UI simplemente no muestra nada).
  final String? registradoPorRol;
  final String? aprobadoPor;
  final String? canceladoPor;
  final String? entregadoPor;

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
