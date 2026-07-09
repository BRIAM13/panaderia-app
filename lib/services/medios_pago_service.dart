import '../models/medio_pago_model.dart';
import 'api_client.dart';
import 'secure_storage_service.dart';

class MedioPagoInput {
  const MedioPagoInput({
    required this.tipo,
    required this.titular,
    required this.numeroDestino,
    this.cci,
    this.nombreBanco,
    this.notas,
    this.imagenQrBase64,
  });

  final String tipo;
  final String titular;
  final String numeroDestino;
  final String? cci;
  final String? nombreBanco;
  final String? notas;

  /// QR real (descargado de la app de Yape/Plin) en base64 — null si no se
  /// cambió/subió ninguno.
  final String? imagenQrBase64;

  Map<String, dynamic> toJson() => {
    'tipo': tipo,
    'titular': titular,
    'numeroDestino': numeroDestino,
    'cci': cci,
    'nombreBanco': nombreBanco,
    'notas': notas,
    'imagenQrBase64': imagenQrBase64,
  };
}

class MediosPagoService {
  MediosPagoService({ApiClient? apiClient, SecureStorageService? secureStorage})
    : _api = apiClient ?? const ApiClient(),
      _storage = secureStorage ?? SecureStorageService();

  final ApiClient _api;
  final SecureStorageService _storage;

  /// Cualquier usuario autenticado (incluido CLIENTE) puede ver los medios
  /// de pago activos de una tienda — los necesita para elegir cómo pagar.
  Future<List<MedioPago>> listarActivos(int idTienda) async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.get(
      '/medios-pago?idTienda=$idTienda',
      token: token,
    );
    final lista = data['mediosPago'] as List<dynamic>? ?? const [];
    return lista
        .map((e) => MedioPago.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Vista de gestión (ADMIN/SUPERADMIN de esa tienda): incluye también los
  /// desactivados, para poder reactivarlos.
  Future<List<MedioPago>> listarPorTienda(int idTienda) async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.get('/medios-pago/tienda/$idTienda', token: token);
    final lista = data['mediosPago'] as List<dynamic>? ?? const [];
    return lista
        .map((e) => MedioPago.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> crear(int idTienda, MedioPagoInput input) async {
    final token = await _storage.obtenerAccessToken();
    await _api.post('/medios-pago', {
      'idTienda': idTienda,
      ...input.toJson(),
    }, token: token);
  }

  Future<void> actualizar(int idMedioPago, MedioPagoInput input) async {
    final token = await _storage.obtenerAccessToken();
    await _api.put('/medios-pago/$idMedioPago', input.toJson(), token: token);
  }

  Future<void> cambiarEstado(int idMedioPago, {required bool activo}) async {
    final token = await _storage.obtenerAccessToken();
    await _api.put('/medios-pago/$idMedioPago/estado', {
      'activo': activo,
    }, token: token);
  }
}
