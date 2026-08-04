import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../services/api_client.dart';
import '../../services/configuraciones_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/estado_error.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/premium_button.dart';

const _claveVersionMinima = 'VERSION_MINIMA_ANDROID';
const _claveUrlDescarga = 'URL_DESCARGA_APK';

/// Control de actualización obligatoria — SOLO SUPERADMIN. Al subir un APK
/// nuevo, sube acá la versión mínima que quieres exigir (ej. "1.1.0"):
/// cualquiera con una versión instalada MENOR verá la pantalla de
/// "Actualización requerida" al abrir la app (ver VersionService/
/// SplashPage) y no podrá continuar hasta actualizar.
class VersionAppPage extends StatefulWidget {
  const VersionAppPage({super.key});

  @override
  State<VersionAppPage> createState() => _VersionAppPageState();
}

class _VersionAppPageState extends State<VersionAppPage> {
  final _formKey = GlobalKey<FormState>();
  final _versionMinimaController = TextEditingController();
  final _urlDescargaController = TextEditingController();
  final _configuracionesService = ConfiguracionesService();

  bool _cargando = true;
  bool _guardando = false;
  String? _error;
  String? _mensajeExito;
  String? _versionInstalada;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _versionMinimaController.dispose();
    _urlDescargaController.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final info = await PackageInfo.fromPlatform();
      final versionMinima = await _configuracionesService.obtener(
        _claveVersionMinima,
      );
      final urlDescarga = await _configuracionesService.obtener(
        _claveUrlDescarga,
      );
      setState(() {
        _versionInstalada = info.version;
        _versionMinimaController.text = versionMinima;
        _urlDescargaController.text = urlDescarga;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(() => _error = 'No se pudo cargar la configuración actual.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _guardando = true;
      _error = null;
      _mensajeExito = null;
    });

    try {
      await _configuracionesService.actualizar(
        _claveVersionMinima,
        _versionMinimaController.text.trim(),
      );
      await _configuracionesService.actualizar(
        _claveUrlDescarga,
        _urlDescargaController.text.trim(),
      );
      setState(() {
        _mensajeExito =
            'Guardado. Quien abra la app con una versión menor a '
            '${_versionMinimaController.text.trim()} verá la pantalla de '
            'actualización obligatoria.';
      });
    } on ApiException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(
        () => _error = 'Ocurrió un error inesperado. Intenta nuevamente.',
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  String? _validarVersion(String? v) {
    final valor = v?.trim() ?? '';
    if (valor.isEmpty) return 'Ingresa la versión mínima';
    final valido = RegExp(r'^\d+\.\d+\.\d+$').hasMatch(valor);
    if (!valido) return 'Usa el formato 1.2.3';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Versión de la app')),
      body: SafeArea(
        child: _cargando
            ? const Center(child: AppLoadingIndicator())
            : _error != null && _versionMinimaController.text.isEmpty
            ? EstadoError(mensaje: _error!, onReintentar: _cargar)
            : _construirFormulario(context),
      ),
    );
  }

  Widget _construirFormulario(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.secondaryContainer,
                  ),
                  child: Icon(
                    Icons.system_update_rounded,
                    color: scheme.primary,
                    size: 32,
                  ),
                )
                .animate()
                .fadeIn(duration: 300.ms)
                .scale(begin: const Offset(0.85, 0.85), end: const Offset(1, 1)),
            const SizedBox(height: 16),
            Text(
              'Actualización obligatoria',
              style: theme.textTheme.titleLarge,
            ).animate().fadeIn(delay: 80.ms, duration: 250.ms),
            const SizedBox(height: 6),
            Text(
              'Cuando publiques un APK nuevo, sube acá la versión mínima '
              'que quieres exigir. Cualquiera con una versión instalada '
              'menor verá una pantalla de bloqueo pidiéndole actualizar, '
              'sin poder entrar a la app hasta hacerlo.',
              style: theme.textTheme.bodyMedium,
            ).animate().fadeIn(delay: 120.ms, duration: 250.ms),
            if (_versionInstalada != null) ...[
              const SizedBox(height: 10),
              Text(
                'Este dispositivo tiene instalada la versión $_versionInstalada.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ).animate().fadeIn(delay: 150.ms, duration: 250.ms),
            ],
            const SizedBox(height: 20),
            TextFormField(
              controller: _versionMinimaController,
              decoration: const InputDecoration(
                labelText: 'Versión mínima requerida',
                hintText: 'ej. 1.1.0',
                prefixIcon: Icon(Icons.tag_rounded),
              ),
              validator: _validarVersion,
            ).animate().fadeIn(delay: 180.ms, duration: 250.ms),
            const SizedBox(height: 16),
            TextFormField(
              controller: _urlDescargaController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Enlace de descarga',
                hintText: 'https://corporacionronceros.vercel.app/',
                prefixIcon: Icon(Icons.link_rounded),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Ingresa el enlace de descarga'
                  : null,
            ).animate().fadeIn(delay: 210.ms, duration: 250.ms),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(
                  color: scheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (_mensajeExito != null) ...[
              const SizedBox(height: 12),
              Text(
                _mensajeExito!,
                style: const TextStyle(
                  color: Color(0xFF16A34A),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 20),
            PremiumButton(
              label: 'Guardar cambios',
              icono: Icons.check_rounded,
              cargando: _guardando,
              onPressed: _guardar,
            ),
          ],
        ),
      ),
    );
  }
}
