import '../models/tienda_model.dart';
import '../models/tienda_resumen_model.dart';
import 'api_client.dart';
import 'pedidos_service.dart' show ProductoAutoservicio;
import 'secure_storage_service.dart';

/// Días con ventas y, de esos, cuáles tienen alguna deuda todavía
/// pendiente — ver [TiendasService.fechasConVentas].
class FechasConVentas {
  const FechasConVentas({required this.fechas, required this.fechasConDeuda});

  factory FechasConVentas.fromJson(Map<String, dynamic> json) {
    final fechas = json['fechas'] as List<dynamic>? ?? const [];
    final fechasConDeuda = json['fechasConDeuda'] as List<dynamic>? ?? const [];
    return FechasConVentas(
      fechas: fechas.map((e) => DateTime.parse(e as String)).toList(),
      fechasConDeuda: fechasConDeuda
          .map((e) => DateTime.parse(e as String))
          .toList(),
    );
  }

  final List<DateTime> fechas;
  final List<DateTime> fechasConDeuda;
}

class TiendasService {
  TiendasService({ApiClient? apiClient, SecureStorageService? secureStorage})
    : _api = apiClient ?? const ApiClient(),
      _storage = secureStorage ?? SecureStorageService();

  final ApiClient _api;
  final SecureStorageService _storage;

  /// Catálogo completo (para el Hub de la vista Trabajador y para que un
  /// CLIENTE elija dónde hacer su pedido).
  Future<List<Tienda>> listar() async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.get('/tiendas', token: token);
    final lista = data['tiendas'] as List<dynamic>? ?? const [];
    return lista
        .map((e) => Tienda.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Solo las tiendas donde el personal autenticado tiene acceso vigente
  /// (SUPERADMIN recibe todas sin necesitar asignación).
  Future<List<Tienda>> misTiendas() async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.get('/tiendas/mis-tiendas', token: token);
    final lista = data['tiendas'] as List<dynamic>? ?? const [];
    return lista
        .map((e) => Tienda.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Resumen/dashboard de una tienda — [fecha] elige qué día mostrar arriba
  /// (cobrado/deuda del día); por defecto es hoy.
  Future<TiendaResumen> resumen(int idTienda, {DateTime? fecha}) async {
    final token = await _storage.obtenerAccessToken();
    final query = fecha != null ? '?fecha=${_formatoFecha(fecha)}' : '';
    final data = await _api.get(
      '/tiendas/$idTienda/resumen$query',
      token: token,
    );
    return TiendaResumen.fromJson(data);
  }

  /// Días con al menos un pedido entregado en esta tienda (para restringir
  /// el selector de fecha del Historial de ventas a días con datos reales)
  /// y, por separado, los días que tienen alguna deuda todavía pendiente
  /// (para marcarlos con un aro en el calendario).
  Future<FechasConVentas> fechasConVentas(int idTienda) async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.get(
      '/tiendas/$idTienda/fechas-con-ventas',
      token: token,
    );
    return FechasConVentas.fromJson(data);
  }

  /// Catálogo de una tienda de catálogo simple (Hamburguesas o Panadería)
  /// para que el personal registre un pedido a nombre de un cliente — ver
  /// `NuevoPedidoPage`. Mismo shape que el catálogo público de la web.
  Future<List<ProductoAutoservicio>> listarProductos(int idTienda) async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.get('/tiendas/$idTienda/productos', token: token);
    final lista = data['productos'] as List<dynamic>? ?? const [];
    return lista
        .map((e) => ProductoAutoservicio.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Personal (ADMIN/SUPERADMIN): cambia el precio por unidad de un
  /// producto del catálogo de una tienda — ver `AjustePreciosPanaderiaPage`.
  Future<double> actualizarPrecioProducto({
    required int idTienda,
    required int idProducto,
    required double precioUnitario,
  }) async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.put(
      '/tiendas/$idTienda/productos/$idProducto',
      {'precioUnitario': precioUnitario},
      token: token,
    );
    return (data['precioUnitario'] as num).toDouble();
  }

  String _formatoFecha(DateTime fecha) {
    final anio = fecha.year.toString().padLeft(4, '0');
    final mes = fecha.month.toString().padLeft(2, '0');
    final dia = fecha.day.toString().padLeft(2, '0');
    return '$anio-$mes-$dia';
  }
}
