import '../models/producto_model.dart';
import 'api_client.dart';
import 'secure_storage_service.dart';

class ProductosService {
  ProductosService({ApiClient? apiClient, SecureStorageService? secureStorage})
    : _api = apiClient ?? const ApiClient(),
      _storage = secureStorage ?? SecureStorageService();

  final ApiClient _api;
  final SecureStorageService _storage;

  Future<List<Producto>> listar() async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.get('/productos', token: token);
    final lista = data['productos'] as List<dynamic>? ?? const [];
    return lista
        .map((e) => Producto.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
