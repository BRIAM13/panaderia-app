import '../models/usuario_sesion.dart';
import 'api_client.dart';
import 'secure_storage_service.dart';

/// Orquesta las llamadas de autenticación contra el backend y su
/// persistencia en el almacenamiento seguro del dispositivo.
class AuthService {
  AuthService({ApiClient? apiClient, SecureStorageService? secureStorage})
    : _api = apiClient ?? const ApiClient(),
      _storage = secureStorage ?? SecureStorageService();

  final ApiClient _api;
  final SecureStorageService _storage;

  SecureStorageService get storage => _storage;

  Future<UsuarioSesion> login({
    required String nombreUsuario,
    required String password,
    required bool recordarme,
  }) async {
    final data = await _api.post('/auth/login', {
      'nombreUsuario': nombreUsuario,
      'password': password,
    });

    final usuario = UsuarioSesion.fromJson(
      data['usuario'] as Map<String, dynamic>,
    );

    await _storage.guardarSesion(
      accessToken: data['accessToken'] as String,
      refreshToken: data['refreshToken'] as String,
      nombreUsuario: usuario.nombreUsuario,
    );
    await _storage.establecerRecordarme(recordarme);

    return usuario;
  }

  /// Cambio de contraseña obligatorio del primer ingreso (clave temporal =
  /// DNI) — a propósito no pide la contraseña actual, ver comentario en el
  /// backend (authController.cambiarPassword).
  Future<void> cambiarPassword({required String passwordNueva}) async {
    final token = await _storage.obtenerAccessToken();
    await _api.post('/auth/cambiar-password', {
      'passwordNueva': passwordNueva,
    }, token: token);
  }

  /// Revalida la sesión guardada (usada en el auto-login biométrico) y
  /// devuelve el perfil actualizado. Si el access token expiró, intenta
  /// renovarlo con el refresh token antes de rendirse.
  Future<UsuarioSesion> revalidarSesion() async {
    var token = await _storage.obtenerAccessToken();
    if (token == null) {
      throw ApiException('No hay una sesión guardada.');
    }

    try {
      final data = await _api.get('/auth/perfil', token: token);
      return UsuarioSesion.fromJson(data['usuario'] as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (e.statusCode != 401) rethrow;
    }

    // El access token expiró: intentar renovarlo con el refresh token.
    final refreshToken = await _storage.obtenerRefreshToken();
    if (refreshToken == null) {
      throw ApiException('La sesión expiró, inicia sesión nuevamente.');
    }

    final refresh = await _api.post('/auth/refresh-token', {
      'refreshToken': refreshToken,
    });
    token = refresh['accessToken'] as String;
    await _storage.actualizarAccessToken(token);

    final data = await _api.get('/auth/perfil', token: token);
    return UsuarioSesion.fromJson(data['usuario'] as Map<String, dynamic>);
  }

  Future<void> cerrarSesion({bool olvidarDispositivo = false}) async {
    if (olvidarDispositivo) {
      await _storage.limpiarTodo();
    } else {
      await _storage.limpiarSesion();
      await _storage.establecerRecordarme(false);
    }
  }
}
