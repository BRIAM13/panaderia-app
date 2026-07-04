import 'api_client.dart';
import 'secure_storage_service.dart';

/// Resultado de la consulta de RENIEC por DNI. [esApiReal] indica si vino
/// de apiperu.dev (dispara la clonación automática de usuario) o del
/// simulador local de respaldo.
class DniLookupResult {
  const DniLookupResult({
    required this.dni,
    required this.nombres,
    required this.apellidoPaterno,
    required this.apellidoMaterno,
    required this.esApiReal,
  });

  factory DniLookupResult.fromJson(Map<String, dynamic> json) =>
      DniLookupResult(
        dni: json['dni'] as String,
        nombres: json['nombres'] as String,
        apellidoPaterno: json['apellidoPaterno'] as String,
        apellidoMaterno: json['apellidoMaterno'] as String,
        esApiReal: json['fuente'] == 'API_REAL',
      );

  final String dni;
  final String nombres;
  final String apellidoPaterno;
  final String apellidoMaterno;
  final bool esApiReal;
}

/// Resultado de la consulta de SUNAT por RUC (real o simulada).
///
/// [tipoContribuyente] se deriva del propio número de RUC, no de la API:
/// prefijo '10' -> persona natural con negocio, '20' -> persona jurídica.
class RucLookupResult {
  const RucLookupResult({
    required this.ruc,
    required this.razonSocial,
    required this.nombreComercial,
    required this.direccion,
    required this.estado,
    required this.condicion,
    required this.esApiReal,
  });

  factory RucLookupResult.fromJson(Map<String, dynamic> json) =>
      RucLookupResult(
        ruc: json['ruc'] as String,
        razonSocial: json['razonSocial'] as String,
        nombreComercial: (json['nombreComercial'] as String?) ?? '',
        direccion: json['direccion'] as String,
        estado: json['estado'] as String,
        condicion: json['condicion'] as String,
        esApiReal: json['fuente'] == 'API_REAL',
      );

  final String ruc;
  final String razonSocial;
  final String nombreComercial;
  final String direccion;
  final String estado;
  final String condicion;
  final bool esApiReal;

  TipoContribuyenteRuc get tipoContribuyente {
    if (ruc.startsWith('10')) return TipoContribuyenteRuc.personaNatural;
    if (ruc.startsWith('20')) return TipoContribuyenteRuc.personaJuridica;
    return TipoContribuyenteRuc.desconocido;
  }
}

enum TipoContribuyenteRuc { personaNatural, personaJuridica, desconocido }

/// Consulta los endpoints de RENIEC (DNI) y SUNAT (RUC) del backend, que a
/// su vez intentan apiperu.dev real y caen a un simulador si no responde.
class ExternalLookupService {
  ExternalLookupService({
    ApiClient? apiClient,
    SecureStorageService? secureStorage,
  }) : _api = apiClient ?? const ApiClient(),
       _storage = secureStorage ?? SecureStorageService();

  final ApiClient _api;
  final SecureStorageService _storage;

  Future<DniLookupResult> buscarPorDni(String dni) async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.post('/external/dni', {'dni': dni}, token: token);
    return DniLookupResult.fromJson(data);
  }

  Future<RucLookupResult> buscarPorRuc(String ruc) async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.post('/external/ruc', {'ruc': ruc}, token: token);
    return RucLookupResult.fromJson(data);
  }
}
