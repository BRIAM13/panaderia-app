import '../models/tienda_model.dart';
import '../models/tienda_resumen_model.dart';
import 'api_client.dart';
import 'secure_storage_service.dart';

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

  /// Días con al menos un pedido entregado en esta tienda — para restringir
  /// el selector de fecha del Dashboard a días con datos reales.
  Future<List<DateTime>> fechasConVentas(int idTienda) async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.get(
      '/tiendas/$idTienda/fechas-con-ventas',
      token: token,
    );
    final lista = data['fechas'] as List<dynamic>? ?? const [];
    return lista.map((e) => DateTime.parse(e as String)).toList();
  }

  String _formatoFecha(DateTime fecha) {
    final anio = fecha.year.toString().padLeft(4, '0');
    final mes = fecha.month.toString().padLeft(2, '0');
    final dia = fecha.day.toString().padLeft(2, '0');
    return '$anio-$mes-$dia';
  }
}
