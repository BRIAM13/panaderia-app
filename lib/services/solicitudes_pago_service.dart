import '../models/solicitud_pago_model.dart';
import 'api_client.dart';
import 'secure_storage_service.dart';

class SolicitudesPagoService {
  SolicitudesPagoService({
    ApiClient? apiClient,
    SecureStorageService? secureStorage,
  }) : _api = apiClient ?? const ApiClient(),
       _storage = secureStorage ?? SecureStorageService();

  final ApiClient _api;
  final SecureStorageService _storage;

  /// Autoservicio (rol CLIENTE): sus propias deudas (pedidos entregados sin
  /// pagar), junto con si ya tienen una solicitud de pago activa.
  Future<List<Deuda>> misDeudas() async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.get('/solicitudes-pago/mis-deudas', token: token);
    final lista = data['deudas'] as List<dynamic>? ?? const [];
    return lista.map((e) => Deuda.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Autoservicio (rol CLIENTE): junta 1+ deudas en una sola solicitud de
  /// pago de un solo uso, con un código de referencia único.
  Future<SolicitudPagoCreada> crear({
    required int idMedioPago,
    required List<int> idsPedidos,
  }) async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.post('/solicitudes-pago', {
      'idMedioPago': idMedioPago,
      'idsPedidos': idsPedidos,
    }, token: token);
    return SolicitudPagoCreada.fromJson(data);
  }

  /// Autoservicio (rol CLIENTE): marca que ya transfirió/yapeó.
  Future<void> reportar(int idSolicitudPago) async {
    final token = await _storage.obtenerAccessToken();
    await _api.put(
      '/solicitudes-pago/$idSolicitudPago/reportar',
      const {},
      token: token,
    );
  }

  /// Personal: solicitudes de pago (generadas o reportadas) de sus tiendas.
  Future<List<SolicitudPagoPendiente>> listarPendientes() async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.get('/solicitudes-pago/pendientes', token: token);
    final lista = data['solicitudes'] as List<dynamic>? ?? const [];
    return lista
        .map((e) => SolicitudPagoPendiente.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Personal: confirma el pago — marca todos los pedidos que cubre como
  /// PAGADO de una vez.
  Future<void> confirmar(int idSolicitudPago) async {
    final token = await _storage.obtenerAccessToken();
    await _api.put(
      '/solicitudes-pago/$idSolicitudPago/confirmar',
      const {},
      token: token,
    );
  }

  /// Personal: rechaza un pago reportado que no pudo verificar.
  Future<void> rechazar(int idSolicitudPago) async {
    final token = await _storage.obtenerAccessToken();
    await _api.put(
      '/solicitudes-pago/$idSolicitudPago/rechazar',
      const {},
      token: token,
    );
  }
}
