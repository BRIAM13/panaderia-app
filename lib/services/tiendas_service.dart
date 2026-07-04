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

  /// Resumen/dashboard de una tienda (ADMIN/SUPERADMIN de esa tienda).
  Future<TiendaResumen> resumen(int idTienda) async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.get('/tiendas/$idTienda/resumen', token: token);
    return TiendaResumen.fromJson(data);
  }
}
