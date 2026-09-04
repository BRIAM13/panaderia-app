import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../models/usuario_sesion.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/biometric_service.dart';
import '../../services/version_service.dart';
import '../../widgets/credito_desarrollador.dart';
import '../../widgets/mascota_video.dart';
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

  /// Grupo B (pantalla de entrada, una sola acción): no hay nada que
  /// repartir en columnas — un splash es una marca y un indicador de
  /// espera. El trabajo acá es de jerarquía y aire: el ícono decorativo
  /// grande (duotone) sobre el indicador, el nombre con peso fuerte y una
  /// línea de contexto discreta debajo, todo centrado con entrada
  /// escalonada. Idéntico en celular y en escritorio a propósito.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Sin saludo acá: esta pantalla suele estar en camino menos de
            // un segundo (cuando hay sesión guardada) — un saludo de varios
            // segundos se vería cortado a mitad de gesto casi siempre. El
            // reposo solo ya comunica "vivo, cargando" de sobra. `moveY`
            // hace que "suba" a su lugar (no solo que aparezca creciendo),
            // en la misma dirección en la que el sello de abajo "baja" al
            // suyo — las dos entradas se leen como un solo momento, no dos
            // animaciones sueltas.
            const MascotaVideo(width: 136, height: 180)
                .animate()
                .fadeIn(duration: 450.ms)
                .moveY(
                  begin: 26,
                  end: 0,
                  curve: Curves.easeOutCubic,
                  duration: 450.ms,
                )
                .scale(
                  begin: const Offset(0.82, 0.82),
                  end: const Offset(1, 1),
                  curve: Curves.easeOutBack,
                ),
            const SizedBox(height: 24),
            Text(
                  'Panadería Ronceros',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    height: 1.1,
                  ),
                )
                .animate()
                .fadeIn(delay: 160.ms, duration: 320.ms)
                .moveY(begin: 8, end: 0),
            const SizedBox(height: 6),
            Text(
                  'Preparando tu sesión…',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: AppColors.secondary,
                  ),
                )
                .animate()
                .fadeIn(delay: 240.ms, duration: 320.ms)
                .moveY(begin: 6, end: 0),
            const SizedBox(height: 36),
            // Entra "bajando" a su lugar (begin negativo = arranca más
            // arriba), justo lo opuesto al personaje que sube desde abajo
            // — convergen hacia sus posiciones finales en vez de aparecer
            // cada uno por su lado.
            const CreditoDesarrollador()
                .animate()
                .fadeIn(delay: 320.ms, duration: 380.ms)
                .moveY(
                  begin: -18,
                  end: 0,
                  delay: 320.ms,
                  duration: 380.ms,
                  curve: Curves.easeOutCubic,
                ),
          ],
        ),
      ),
    );
  }
}
