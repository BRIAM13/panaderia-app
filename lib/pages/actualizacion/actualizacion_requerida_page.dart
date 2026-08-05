import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../theme/app_theme.dart';
import '../../widgets/premium_button.dart';

/// Debe coincidir con `applicationId` en android/app/build.gradle.kts —
/// mismo authority declarado en el `<provider>` FileProvider del
/// AndroidManifest.
const _fileProviderAuthority = 'com.corporacionronceros.panaderia_app.fileprovider';

/// Pantalla de bloqueo total: se muestra en vez del login/home cuando el
/// backend indica que la versión instalada quedó por debajo de la mínima
/// permitida (ver VersionService/SplashPage). No hay forma de saltarla —
/// ni botón "Atrás" ni "Más tarde" — porque el punto es forzar la
/// actualización antes de dejar usar el resto de la app.
///
/// A diferencia de una versión anterior (que solo abría el navegador y
/// dejaba a la persona descargar/instalar a mano), acá el APK se descarga
/// DENTRO de la app, con progreso real, y al terminar se abre directo el
/// instalador del sistema — un solo toque. Lo único que Android sigue
/// pidiendo aparte (y no se puede evitar, es una protección del sistema)
/// es autorizar una vez "instalar apps desconocidas" para esta app.
class ActualizacionRequeridaPage extends StatefulWidget {
  const ActualizacionRequeridaPage({super.key, required this.urlDescarga});

  /// Debe ser la URL directa del archivo .apk, no una página web — se
  /// descarga tal cual con una petición HTTP normal.
  final String urlDescarga;

  @override
  State<ActualizacionRequeridaPage> createState() =>
      _ActualizacionRequeridaPageState();
}

class _ActualizacionRequeridaPageState
    extends State<ActualizacionRequeridaPage> {
  bool _descargando = false;
  double? _progreso; // null = indeterminado (aún no se sabe el tamaño total)
  String? _error;

  Future<void> _descargarEInstalar() async {
    setState(() {
      _descargando = true;
      _progreso = null;
      _error = null;
    });

    try {
      final uri = Uri.parse(widget.urlDescarga);
      final cliente = http.Client();
      final peticion = http.Request('GET', uri);
      final respuesta = await cliente.send(peticion);

      if (respuesta.statusCode != 200) {
        throw Exception('El servidor respondió ${respuesta.statusCode}');
      }

      final total = respuesta.contentLength;
      // El nombre debe quedar directo en la raíz de la caché (sin
      // subcarpetas) — así coincide con el <cache-path path="."/> declarado
      // en res/xml/file_paths.xml, que es lo que arma la URI de abajo.
      final carpetaTemporal = await getTemporaryDirectory();
      final archivo = File('${carpetaTemporal.path}/actualizacion.apk');
      final sink = archivo.openWrite();

      var recibido = 0;
      await for (final trozo in respuesta.stream) {
        sink.add(trozo);
        recibido += trozo.length;
        if (total != null && total > 0 && mounted) {
          setState(() => _progreso = recibido / total);
        }
      }
      await sink.close();
      cliente.close();

      if (!mounted) return;

      // content:// (no file://): Android 7+ bloquea pasar un file:// URI
      // crudo entre apps — el FileProvider (ver AndroidManifest) expone la
      // carpeta de caché bajo el nombre "actualizaciones", así que la URI
      // sigue ese mismo esquema.
      final intent = AndroidIntent(
        action: 'action_view',
        data: 'content://$_fileProviderAuthority/actualizaciones/actualizacion.apk',
        type: 'application/vnd.android.package-archive',
        flags: [
          Flag.FLAG_ACTIVITY_NEW_TASK,
          Flag.FLAG_GRANT_READ_URI_PERMISSION,
        ],
      );
      await intent.launch();

      // FLAG_ACTIVITY_NEW_TASK abre el instalador en una tarea aparte, sin
      // tocar esta — si esta instancia (la que pedía actualizar) se queda
      // viva, Android la deja como una tarea aparte en Recientes.
      // `exit(0)` (probado antes) mata el proceso de golpe, sin pasar por
      // el cierre normal de la actividad — la tarea queda huérfana en
      // Recientes (sin proceso, pero visible igual). SystemNavigator.pop()
      // sí pasa por Activity.finish(), que al ser la única actividad de su
      // tarea, hace que Android remueva la tarea completa de Recientes.
      await SystemNavigator.pop();
    } on PlatformException {
      if (mounted) {
        setState(
          () => _error =
              'No se pudo abrir el instalador. Puede que debas autorizar '
              '"instalar apps desconocidas" para esta app en Ajustes.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'No se pudo descargar la actualización. Revisa tu conexión e intenta de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => _descargando = false);
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
                            padding: const EdgeInsets.all(16),
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
                            child: Column(
                              children: [
                                if (_descargando) ...[
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: LinearProgressIndicator(
                                      value: _progreso,
                                      minHeight: 8,
                                      backgroundColor: AppColors.surfaceMuted,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _progreso != null
                                        ? 'Descargando… ${(_progreso! * 100).toStringAsFixed(0)}%'
                                        : 'Descargando…',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                ],
                                PremiumButton(
                                  label: _descargando
                                      ? 'Descargando…'
                                      : 'Descargar e instalar',
                                  icono: Icons.download_rounded,
                                  cargando: _descargando,
                                  onPressed: _descargarEInstalar,
                                ),
                              ],
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
