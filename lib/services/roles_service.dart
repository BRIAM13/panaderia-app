import '../models/rol_model.dart';
import 'api_client.dart';
import 'secure_storage_service.dart';

class RolesService {
  RolesService({ApiClient? apiClient, SecureStorageService? secureStorage})
    : _api = apiClient ?? const ApiClient(),
      _storage = secureStorage ?? SecureStorageService();

  final ApiClient _api;
  final SecureStorageService _storage;

  /// Roles que el usuario autenticado puede asignar a otra persona (ver
  /// [RolAsignable]).
  Future<List<RolAsignable>> asignables() async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.get('/roles/asignables', token: token);
    final lista = data['roles'] as List<dynamic>? ?? const [];
    return lista
        .map((e) => RolAsignable.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
