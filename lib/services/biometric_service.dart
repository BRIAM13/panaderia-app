import 'package:local_auth/local_auth.dart';

/// Envoltorio delgado sobre `local_auth`. En plataformas sin soporte
/// (web, desktop sin sensor) [esDisponible] simplemente devuelve `false`,
/// así el resto de la app no necesita distinguir por plataforma.
class BiometricService {
  BiometricService() : _auth = LocalAuthentication();

  final LocalAuthentication _auth;

  Future<bool> esDisponible() async {
    try {
      final soportado = await _auth.isDeviceSupported();
      final puedeChequear = await _auth.canCheckBiometrics;
      return soportado && puedeChequear;
    } catch (_) {
      return false;
    }
  }

  Future<bool> autenticar({
    String razon = 'Confirma tu identidad para continuar',
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: razon,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
