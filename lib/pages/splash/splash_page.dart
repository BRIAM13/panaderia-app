import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../models/usuario_sesion.dart';
import '../../services/auth_service.dart';
import '../../services/biometric_service.dart';
import '../../services/version_service.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/page_transitions.dart';
import '../actualizacion/actualizacion_requerida_page.dart';
import '../auth/login_page.dart';
import '../hub/home_page.dart';

/// Punto de entrada real de la app: decide en silencio si hay una sesión
/// que se pueda restaurar (con o sin huella) antes de mostrar el login.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  final _authService = AuthService();
  final _biometricService = BiometricService();
  final _versionService = VersionService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    // Se revisa antes que cualquier otra cosa (incluso antes de mirar si hay
    // sesión guardada): si el backend ya no es compatible con esta versión,
    // no tiene sentido intentar restaurar sesión ni mostrar el login.
    final actualizacion = await _versionService.verificar();
    if (actualizacion.actualizacionRequerida) {
      _irAActualizacionRequerida(actualizacion.urlDescarga);
      return;
    }

    final storage = _authService.storage;
    final recordarme = await storage.obtenerRecordarme();

    if (!recordarme) {
      _irALogin();
      return;
    }

    final biometriaActiva = await storage.obtenerBiometriaActiva();

    if (biometriaActiva) {
      final hardwareDisponible = await _biometricService.esDisponible();
      if (hardwareDisponible) {
        final autenticado = await _biometricService.autenticar(
          razon: 'Inicia sesión en Panadería Ronceros',
        );
        if (!autenticado) {
          _irALogin();
          return;
        }
      }
    }

    try {
      final usuario = await _authService.revalidarSesion();
      _irAHome(usuario);
    } catch (_) {
      _irALogin();
    }
  }

  void _irAActualizacionRequerida(String urlDescarga) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      SlideUpFadeRoute(
        builder: (_) => ActualizacionRequeridaPage(urlDescarga: urlDescarga),
      ),
    );
  }

  void _irALogin() {
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(SlideUpFadeRoute(builder: (_) => const LoginPage()));
  }

  void _irAHome(UsuarioSesion usuario) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      SlideUpFadeRoute(builder: (_) => HomePage(usuario: usuario)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppLoadingIndicator(
              size: 72,
            ).animate().fadeIn(duration: 300.ms),
            const SizedBox(height: 20),
            Text(
              'Panadería Ronceros',
              style: theme.textTheme.titleLarge,
            ).animate().fadeIn(delay: 100.ms, duration: 300.ms),
          ],
        ),
      ),
    );
  }
}
