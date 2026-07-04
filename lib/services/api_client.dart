import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

/// Excepción con el mensaje ya listo para mostrar al usuario, tal como lo
/// entrega el backend (`{ mensaje, errores? }`).
class ApiException implements Exception {
  ApiException(this.mensaje, {this.statusCode, this.errores, this.tipo});

  final String mensaje;
  final int? statusCode;
  final List<String>? errores;

  /// Código de error específico que algunos endpoints agregan al JSON (ej.
  /// 'COOLDOWN', 'AUTORIZACION_REQUERIDA') para que la UI reaccione distinto
  /// a un error genérico — ver flujos de verificación en Mi Perfil.
  final String? tipo;

  @override
  String toString() => mensaje;
}

/// Resuelve la URL base del backend según la plataforma.
///
/// IMPORTANTE: para probar en un celular físico conectado por Wi-Fi, ni
/// "localhost" ni "10.0.2.2" apuntan a esta PC. Ejecuta la app con:
/// `flutter run --dart-define=API_BASE_URL=http://IP_LAN_DE_TU_PC:4000/api`
class ApiConfig {
  ApiConfig._();

  static const String _override = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    if (_override.isNotEmpty) return _override;
    if (kIsWeb) return 'http://localhost:4000/api';
    if (Platform.isAndroid) {
      return 'http://10.0.2.2:4000/api'; // emulador Android
    }
    return 'http://localhost:4000/api';
  }
}

/// Cliente HTTP delgado: arma la URL, serializa JSON y traduce errores del
/// backend a [ApiException] con el mensaje ya listo para la UI.
class ApiClient {
  const ApiClient();

  Uri _uri(String path) => Uri.parse('${ApiConfig.baseUrl}$path');

  Map<String, String> _headers({String? token}) => {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) async {
    final http.Response respuesta;
    try {
      respuesta = await http
          .post(
            _uri(path),
            headers: _headers(token: token),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw ApiException(
        'No se pudo conectar con el servidor. Verifica tu conexión.',
      );
    }
    return _procesarRespuesta(respuesta);
  }

  Future<Map<String, dynamic>> get(String path, {String? token}) async {
    final http.Response respuesta;
    try {
      respuesta = await http
          .get(_uri(path), headers: _headers(token: token))
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw ApiException(
        'No se pudo conectar con el servidor. Verifica tu conexión.',
      );
    }
    return _procesarRespuesta(respuesta);
  }

  Future<Map<String, dynamic>> put(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) async {
    final http.Response respuesta;
    try {
      respuesta = await http
          .put(
            _uri(path),
            headers: _headers(token: token),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw ApiException(
        'No se pudo conectar con el servidor. Verifica tu conexión.',
      );
    }
    return _procesarRespuesta(respuesta);
  }

  Future<Map<String, dynamic>> delete(String path, {String? token}) async {
    final http.Response respuesta;
    try {
      respuesta = await http
          .delete(_uri(path), headers: _headers(token: token))
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw ApiException(
        'No se pudo conectar con el servidor. Verifica tu conexión.',
      );
    }
    return _procesarRespuesta(respuesta);
  }

  Map<String, dynamic> _procesarRespuesta(http.Response respuesta) {
    Map<String, dynamic> data = const {};
    if (respuesta.body.isNotEmpty) {
      try {
        data = jsonDecode(respuesta.body) as Map<String, dynamic>;
      } catch (_) {
        data = const {};
      }
    }

    if (respuesta.statusCode >= 200 && respuesta.statusCode < 300) {
      return data;
    }

    final errores = (data['errores'] as List<dynamic>?)
        ?.map((e) => e.toString())
        .toList();
    throw ApiException(
      (data['mensaje'] as String?) ?? 'Ocurrió un error inesperado.',
      statusCode: respuesta.statusCode,
      errores: errores,
      tipo: data['tipo'] as String?,
    );
  }
}
