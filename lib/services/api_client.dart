import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import 'secure_storage_service.dart';

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

  // Azure SQL (oferta gratuita) pausa la base de datos sola tras un rato de
  // inactividad, y la primera consulta tras eso puede tardar bastante en
  // "despertarla" — 15s no alcanzaba y la app mostraba "no se pudo conectar"
  // aunque el servidor sí estaba respondiendo, solo que lento. Se amplía
  // para dar tiempo a ese primer despertar sin fallar de más.
  static const _timeoutHttp = Duration(seconds: 45);

  Uri _uri(String path) => Uri.parse('${ApiConfig.baseUrl}$path');

  Map<String, String> _headers({String? token}) => {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) => _conRenovacionDeToken(
    token,
    (t) => http
        .post(_uri(path), headers: _headers(token: t), body: jsonEncode(body))
        .timeout(_timeoutHttp),
  );

  Future<Map<String, dynamic>> get(String path, {String? token}) =>
      _conRenovacionDeToken(
        token,
        (t) => http
            .get(_uri(path), headers: _headers(token: t))
            .timeout(_timeoutHttp),
      );

  Future<Map<String, dynamic>> put(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) => _conRenovacionDeToken(
    token,
    (t) => http
        .put(_uri(path), headers: _headers(token: t), body: jsonEncode(body))
        .timeout(_timeoutHttp),
  );

  Future<Map<String, dynamic>> delete(String path, {String? token}) =>
      _conRenovacionDeToken(
        token,
        (t) => http
            .delete(_uri(path), headers: _headers(token: t))
            .timeout(_timeoutHttp),
      );

  /// Ejecuta la petición y, si el backend responde 401 (el middleware de
  /// auth solo usa 401 para "token ausente/inválido/vencido" — los permisos
  /// insuficientes son 403, ver authMiddleware.js), intenta renovar el
  /// access token con el refresh token guardado y reintenta UNA vez con el
  /// token nuevo. Así el usuario nunca ve un error ni tiene que volver a
  /// loguearse mientras el refresh token (7 días) siga vigente — antes de
  /// esto, un access token vencido (1h) rompía silenciosamente cualquier
  /// pantalla hasta que el usuario cerrara y volviera a iniciar sesión.
  Future<Map<String, dynamic>> _conRenovacionDeToken(
    String? token,
    Future<http.Response> Function(String? token) peticion,
  ) async {
    http.Response respuesta = await _ejecutar(() => peticion(token));

    if (respuesta.statusCode == 401 && token != null) {
      final nuevoToken = await _renovarAccessToken();
      if (nuevoToken != null) {
        respuesta = await _ejecutar(() => peticion(nuevoToken));
      }
    }

    return _procesarRespuesta(respuesta);
  }

  Future<http.Response> _ejecutar(
    Future<http.Response> Function() peticion,
  ) async {
    try {
      return await peticion();
    } catch (_) {
      throw ApiException(
        'No se pudo conectar con el servidor. Verifica tu conexión.',
      );
    }
  }

  /// Instancia propia (no se guarda como campo para que `ApiClient` se
  /// mantenga `const`, como esperan todos sus constructores en los demás
  /// servicios) — solo se usa en el camino poco frecuente de renovar token.
  Future<String?> _renovarAccessToken() async {
    final storage = SecureStorageService();
    final refreshToken = await storage.obtenerRefreshToken();
    if (refreshToken == null) return null;

    try {
      final respuesta = await http
          .post(
            _uri('/auth/refresh-token'),
            headers: _headers(),
            body: jsonEncode({'refreshToken': refreshToken}),
          )
          .timeout(_timeoutHttp);

      if (respuesta.statusCode != 200) return null;

      final data = jsonDecode(respuesta.body) as Map<String, dynamic>;
      final nuevoAccessToken = data['accessToken'] as String?;
      if (nuevoAccessToken == null) return null;

      await storage.actualizarAccessToken(nuevoAccessToken);
      return nuevoAccessToken;
    } catch (_) {
      return null;
    }
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
