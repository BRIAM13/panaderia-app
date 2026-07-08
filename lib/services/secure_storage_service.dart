import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Guarda tokens y preferencias de sesión en el llavero nativo del
/// dispositivo (Android Keystore vía EncryptedSharedPreferences / iOS
/// Keychain), nunca en texto plano ni en SharedPreferences comunes.
class SecureStorageService {
  SecureStorageService()
    : _storage = const FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      );

  final FlutterSecureStorage _storage;

  static const _keyAccessToken = 'access_token';
  static const _keyRefreshToken = 'refresh_token';
  static const _keyNombreUsuario = 'nombre_usuario';
  static const _keyRecordarme = 'remember_me';
  static const _keyBiometriaActiva = 'biometrics_enabled';

  Future<void> guardarSesion({
    required String accessToken,
    required String refreshToken,
    required String nombreUsuario,
  }) async {
    // Escrituras secuenciales a propósito: en web, flutter_secure_storage
    // crea de forma perezosa una clave AES la primera vez que se escribe
    // algo; escribir varias claves en paralelo (Future.wait) puede hacer
    // que esa inicialización se dispare más de una vez a la vez y corrompa
    // el cifrado (lecturas posteriores fallan con "OperationError").
    await _storage.write(key: _keyAccessToken, value: accessToken);
    await _storage.write(key: _keyRefreshToken, value: refreshToken);
    await _storage.write(key: _keyNombreUsuario, value: nombreUsuario);
  }

  Future<void> actualizarAccessToken(String accessToken) {
    return _storage.write(key: _keyAccessToken, value: accessToken);
  }

  Future<String?> obtenerAccessToken() => _storage.read(key: _keyAccessToken);

  Future<String?> obtenerRefreshToken() => _storage.read(key: _keyRefreshToken);

  Future<String?> obtenerNombreUsuario() =>
      _storage.read(key: _keyNombreUsuario);

  Future<void> establecerRecordarme(bool valor) {
    return _storage.write(key: _keyRecordarme, value: valor.toString());
  }

  Future<bool> obtenerRecordarme() async {
    final valor = await _storage.read(key: _keyRecordarme);
    // Si nunca se guardó la preferencia (primer inicio de sesión de todos),
    // se asume "recordarme" activado, igual que el valor por defecto del
    // switch en la pantalla de login.
    if (valor == null) return true;
    return valor == 'true';
  }

  Future<void> establecerBiometriaActiva(bool valor) {
    return _storage.write(key: _keyBiometriaActiva, value: valor.toString());
  }

  Future<bool> obtenerBiometriaActiva() async {
    final valor = await _storage.read(key: _keyBiometriaActiva);
    return valor == 'true';
  }

  /// Borra únicamente la sesión (tokens), preservando preferencias como
  /// "recordarme" o la activación de biometría.
  Future<void> limpiarSesion() async {
    await _storage.delete(key: _keyAccessToken);
    await _storage.delete(key: _keyRefreshToken);
  }

  /// Cierre de sesión completo: borra todo, incluida la preferencia de
  /// biometría (se debe volver a pedir consentimiento si inicia sesión de
  /// nuevo en el futuro).
  Future<void> limpiarTodo() => _storage.deleteAll();
}
