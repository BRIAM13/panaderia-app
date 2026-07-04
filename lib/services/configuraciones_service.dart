import 'api_client.dart';
import 'secure_storage_service.dart';

class ConfiguracionesService {
  ConfiguracionesService({
    ApiClient? apiClient,
    SecureStorageService? secureStorage,
  }) : _api = apiClient ?? const ApiClient(),
       _storage = secureStorage ?? SecureStorageService();

  final ApiClient _api;
  final SecureStorageService _storage;

  Future<String> obtener(String clave) async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.get('/configuraciones/$clave', token: token);
    return data['valor'] as String;
  }

  Future<void> actualizar(String clave, String valor) async {
    final token = await _storage.obtenerAccessToken();
    await _api.put('/configuraciones/$clave', {'valor': valor}, token: token);
  }
}
