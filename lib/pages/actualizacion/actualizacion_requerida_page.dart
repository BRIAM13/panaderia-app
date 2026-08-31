import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_theme.dart';
import '../../widgets/premium_button.dart';

/// Id real de la app en Play Store — debe coincidir con `applicationId` en
/// android/app/build.gradle.kts.
const _idPaquete = 'com.corporacionronceros.panaderia_app';

/// Pantalla de bloqueo total: se muestra en vez del login/home cuando el
/// backend indica que la versión instalada quedó por debajo de la mínima
/// permitida (ver VersionService/SplashPage). No hay forma de saltarla —
/// ni botón "Atrás" ni "Más tarde" — porque el punto es forzar la
/// actualización antes de dejar usar el resto de la app.
///
/// Ahora que la app vive en Play Store, actualizar es simplemente mandar a
/// la ficha de la app ahí — Play Store se encarga de descargar e instalar
/// la actualización, y de mantener actualizada a cualquiera que la tenga
/// instalada desde ahí sin que la app tenga que hacer nada más. (Una
/// versión anterior de esta pantalla descargaba e instalaba el APK ella
/// misma, necesario mientras la única forma de distribuir era el enlace
/// directo — con Play Store ya no hace falta esa complejidad, y evita
/// fricción con sus políticas sobre apps que se autoactualizan por fuera
/// de la tienda.)
class ActualizacionRequeridaPage extends StatefulWidget {
  const ActualizacionRequeridaPage({super.key, required this.urlDescarga});

  /// Enlace de Play Store (o el que el backend indique como respaldo) —
  /// ver VERSION_MINIMA_ANDROID/URL_DESCARGA_APK en Configuraciones.
  final String urlDescarga;

  @override
  State<ActualizacionRequeridaPage> createState() =>
      _ActualizacionRequeridaPageState();
}

class _ActualizacionRequeridaPageState
    extends State<ActualizacionRequeridaPage> {
  bool _abriendo = false;
  String? _error;

  Future<void> _irAPlayStore() async {
    setState(() {
      _abriendo = true;
      _error = null;
    });
    try {
      // market:// abre directo la app de Play Store (mejor experiencia);
      // si no está disponible (ej. no hay Play Store en el dispositivo),
      // cae al enlace web normal.
      final uriTienda = Uri.parse('market://details?id=$_idPaquete');
      var abierto = await launchUrl(uriTienda, mode: LaunchMode.externalApplication);
      if (!abierto) {
        final uriWeb = Uri.parse(widget.urlDescarga);
        abierto = await launchUrl(uriWeb, mode: LaunchMode.externalApplication);
      }
      if (!abierto && mounted) {
        setState(() => _error = 'No se pudo abrir Play Store.');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo abrir Play Store.');
    } finally {
      if (mounted) setState(() => _abriendo = false);
    }
  }

  /// Grupo B (pantalla de bloqueo, una sola acción): no hay contenido que
  /// repartir en columnas — es un mensaje y un botón. En ventana ancha el
  /// bloque NO se estira: se queda en una tarjeta centrada de 460 px sobre
  /// el fondo de marca a pantalla completa, con el ícono duotone grande
  /// como protagonista. Mismo árbol en celular y en escritorio (solo el
  /// techo de ancho cambia lo que se ve, no la estructura).
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primary, AppColors.secondary],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                            width: 112,
                            height: 112,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.18),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.4),
                                width: 1.6,
                              ),
                            ),
                            child: const PhosphorIcon(
                              PhosphorIconsDuotone.cloudArrowDown,
                              color: Colors.white,
                              size: 56,
                              duotoneSecondaryOpacity: 0.35,
                            ),
                          )
                          .animate()
                          .fadeIn(duration: 350.ms)
                          .scale(
                            begin: const Offset(0.85, 0.85),
                            end: const Offset(1, 1),
                            curve: Curves.easeOutBack,
                          ),
                      const SizedBox(height: 16),
                      Text(
                        'ACTUALIZACIÓN DISPONIBLE',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.6,
                          color: Colors.white.withValues(alpha: 0.75),
                        ),
                      ).animate().fadeIn(delay: 80.ms, duration: 300.ms),
                      const SizedBox(height: 10),
                      Text(
                        'Necesitas la última versión',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ).animate().fadeIn(delay: 120.ms, duration: 300.ms),
                      const SizedBox(height: 12),
                      Text(
                        'Hay una nueva versión de la app con correcciones '
                        'importantes. Actualiza desde Play Store para seguir '
                        'usándola.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: Colors.white.withValues(alpha: 0.92),
                          height: 1.5,
                        ),
                      ).animate().fadeIn(delay: 160.ms, duration: 300.ms),
                      const SizedBox(height: 32),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 340),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.2),
                                    blurRadius: 24,
                                    offset: const Offset(0, 12),
                                  ),
                                ],
                              ),
                              child: PremiumButton(
                                label: 'Actualizar en Play Store',
                                icono: PhosphorIconsRegular.googlePlayLogo,
                                cargando: _abriendo,
                                onPressed: _irAPlayStore,
                              ),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 14),
                              Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ).animate().fadeIn(delay: 220.ms, duration: 300.ms).moveY(begin: 14, end: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
