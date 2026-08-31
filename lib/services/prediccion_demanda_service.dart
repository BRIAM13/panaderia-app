import '../models/prediccion_demanda_model.dart';
import 'api_client.dart';
import 'secure_storage_service.dart';

/// El microservicio de predicción todavía no está desplegado (o está caído,
/// o tardó demasiado). Se distingue de un [ApiException] cualquiera porque
/// NO es un error del que el usuario tenga que preocuparse ni algo que
/// reintentar sirva: la pantalla lo muestra como un estado vacío explicativo
/// ("se activará cuando el servidor esté desplegado"), no como una falla en
/// rojo con botón de reintentar.
class PrediccionNoDisponibleException implements Exception {
  PrediccionNoDisponibleException(this.mensaje);

  final String mensaje;

  @override
  String toString() => mensaje;
}

class PrediccionDemandaService {
  PrediccionDemandaService({
    ApiClient? apiClient,
    SecureStorageService? secureStorage,
  }) : _api = apiClient ?? const ApiClient(),
       _storage = secureStorage ?? SecureStorageService();

  final ApiClient _api;
  final SecureStorageService _storage;

  /// Predicción para [fechas] (una consulta, varias fechas — el
  /// microservicio acepta hasta 90). Exclusivo ADMIN/SUPERADMIN, el backend
  /// también lo exige.
  ///
  /// Lanza [PrediccionNoDisponibleException] si el backend responde 503, que
  /// es hoy el caso normal mientras `ML_SERVICE_URL` no esté configurada.
  Future<PrediccionDemanda> predecir({
    required int idTienda,
    required int idProducto,
    required List<DateTime> fechas,
  }) async {
    final token = await _storage.obtenerAccessToken();
    final query = fechas.map(_formatoFecha).join(',');
    try {
      final data = await _api.get(
        '/prediccion-demanda/$idTienda/$idProducto?fechas=$query',
        token: token,
      );
      return PrediccionDemanda.fromJson(data);
    } on ApiException catch (e) {
      if (e.statusCode == 503) {
        throw PrediccionNoDisponibleException(e.mensaje);
      }
      rethrow;
    }
  }

  /// Los próximos [dias] días a partir de mañana — planificar la producción
  /// de hoy ya no sirve de nada a la hora en que se mira este panel.
  static List<DateTime> proximosDias(int dias) {
    final hoy = DateTime.now();
    return List.generate(
      dias,
      (i) => DateTime(hoy.year, hoy.month, hoy.day + 1 + i),
    );
  }

  String _formatoFecha(DateTime fecha) {
    final anio = fecha.year.toString().padLeft(4, '0');
    final mes = fecha.month.toString().padLeft(2, '0');
    final dia = fecha.day.toString().padLeft(2, '0');
    return '$anio-$mes-$dia';
  }
}
