import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_theme.dart';
import '../../widgets/premium_button.dart';

/// Pantalla de bloqueo total: se muestra en vez del login/home cuando el
/// backend indica que la versión instalada quedó por debajo de la mínima
/// permitida (ver VersionService/SplashPage). No hay forma de saltarla —
/// ni botón "Atrás" ni "Más tarde" — porque el punto es forzar la
/// actualización antes de dejar usar el resto de la app.
class ActualizacionRequeridaPage extends StatefulWidget {
  const ActualizacionRequeridaPage({super.key, required this.urlDescarga});

  final String urlDescarga;

  @override
  State<ActualizacionRequeridaPage> createState() =>
      _ActualizacionRequeridaPageState();
}

class _ActualizacionRequeridaPageState
    extends State<ActualizacionRequeridaPage> {
  bool _abriendo = false;
  String? _error;

  Future<void> _descargar() async {
    setState(() {
      _abriendo = true;
      _error = null;
    });
    try {
      final uri = Uri.parse(widget.urlDescarga);
      final abierto = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!abierto && mounted) {
        setState(() => _error = 'No se pudo abrir el enlace de descarga.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo abrir el enlace de descarga.');
      }
    } finally {
      if (mounted) setState(() => _abriendo = false);
    }
  }

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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.18),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.4),
                              width: 1.6,
                            ),
                          ),
                          child: const Icon(
                            Icons.system_update_rounded,
                            color: Colors.white,
                            size: 46,
                          ),
                        )
                        .animate()
                        .fadeIn(duration: 350.ms)
                        .scale(
                          begin: const Offset(0.85, 0.85),
                          end: const Offset(1, 1),
                          curve: Curves.easeOutBack,
                        ),
                    const SizedBox(height: 28),
                    Text(
                      'Actualización requerida',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ).animate().fadeIn(delay: 100.ms, duration: 300.ms),
                    const SizedBox(height: 12),
                    Text(
                      'Hay una nueva versión de la app con correcciones '
                      'importantes. Actualiza para seguir usándola.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                    ).animate().fadeIn(delay: 150.ms, duration: 300.ms),
                    const SizedBox(height: 32),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 340),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 4,
                            ),
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
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: PremiumButton(
                                label: 'Descargar actualización',
                                icono: Icons.download_rounded,
                                cargando: _abriendo,
                                onPressed: _descargar,
                              ),
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
    );
  }
}
