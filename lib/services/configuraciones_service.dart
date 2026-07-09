import 'api_client.dart';
import 'secure_storage_service.dart';

/// Una configuración clave-valor tal como la devuelve
/// `GET /configuraciones/:clave` — incluye cuándo fue la última vez que se
/// actualizó, útil para mostrar "hace cuánto se cambió" en pantallas como
/// la del token de apiperu.dev.
class ConfiguracionValor {
  const ConfiguracionValor({required this.valor, this.fechaActualizacion});

  factory ConfiguracionValor.fromJson(Map<String, dynamic> json) =>
      ConfiguracionValor(
        valor: json['valor'] as String,
        fechaActualizacion: json['fechaActualizacion'] != null
            ? DateTime.parse(json['fechaActualizacion'] as String)
            : null,
      );

  final String valor;
  final DateTime? fechaActualizacion;
}

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

  Future<ConfiguracionValor> obtenerConDetalle(String clave) async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.get('/configuraciones/$clave', token: token);
    return ConfiguracionValor.fromJson(data);
  }

  Future<void> actualizar(String clave, String valor) async {
    final token = await _storage.obtenerAccessToken();
    await _api.put('/configuraciones/$clave', {'valor': valor}, token: token);
  }
}
