import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import '../../services/api_client.dart';
import '../../services/configuraciones_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/estado_error.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/premium_button.dart';

const _claveTokenApiPeru = 'API_PERU_TOKEN';

/// Edición del token de apiperu.dev (consulta real de DNI/RUC) — SOLO
/// SUPERADMIN puede ver o tocar esta pantalla (el backend además exige
/// SUPERADMIN en el propio endpoint, ver CLAVES_SOLO_SUPERADMIN en
/// configuracionesController.js: ni un ADMIN puede leer ni escribir esta
/// configuración por API directa). El token vive en la tabla
/// Configuraciones — al guardarlo, el backend lo relee de la BD en la
/// siguiente consulta, sin necesitar redeploy ni tocar nada en Render.
class TokenApiPeruPage extends StatefulWidget {
  const TokenApiPeruPage({super.key});

  @override
  State<TokenApiPeruPage> createState() => _TokenApiPeruPageState();
}

class _TokenApiPeruPageState extends State<TokenApiPeruPage> {
  final _formKey = GlobalKey<FormState>();
  final _tokenController = TextEditingController();
  final _configuracionesService = ConfiguracionesService();

  bool _cargando = true;
  bool _guardando = false;
  bool _tokenVisible = false;
  String? _error;
  String? _mensajeExito;
  DateTime? _ultimaActualizacion;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final config = await _configuracionesService.obtenerConDetalle(
        _claveTokenApiPeru,
      );
      setState(() {
        _tokenController.text = config.valor;
        _ultimaActualizacion = config.fechaActualizacion;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(() => _error = 'No se pudo cargar el token actual.');
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
      final nuevoValor = _tokenController.text.trim();
      await _configuracionesService.actualizar(_claveTokenApiPeru, nuevoValor);
      setState(() {
        _ultimaActualizacion = DateTime.now();
        _mensajeExito =
            'Token actualizado. Las próximas consultas de DNI/RUC ya lo usan.';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Token de apiperu.dev')),
      body: SafeArea(
        child: _cargando
            ? const Center(child: AppLoadingIndicator())
            : _error != null && _tokenController.text.isEmpty
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
                    Icons.vpn_key_rounded,
                    color: scheme.primary,
                    size: 32,
                  ),
                )
                .animate()
                .fadeIn(duration: 300.ms)
                .scale(begin: const Offset(0.85, 0.85), end: const Offset(1, 1)),
            const SizedBox(height: 16),
            Text(
              'Token de consulta DNI/RUC',
              style: theme.textTheme.titleLarge,
            ).animate().fadeIn(delay: 80.ms, duration: 250.ms),
            const SizedBox(height: 6),
            Text(
              'Lo usa el servidor para pedirle a apiperu.dev los datos '
              'reales de RENIEC/SUNAT al registrar clientes o trabajadores. '
              'Solo tú (Super Administrador) puedes verlo o cambiarlo.',
              style: theme.textTheme.bodyMedium,
            ).animate().fadeIn(delay: 120.ms, duration: 250.ms),
            const SizedBox(height: 16),
            Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEA8C1B).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: Color(0xFFEA8C1B),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Cada token de apiperu.dev tiene un tope de 100 '
                          'validaciones. Cuando se agote, las búsquedas de '
                          'DNI/RUC dejan de traer datos reales (caen al modo '
                          'simulado) — genera uno nuevo en apiperu.dev y '
                          'pégalo aquí.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
                .animate()
                .fadeIn(delay: 160.ms, duration: 250.ms),
            if (_ultimaActualizacion != null) ...[
              const SizedBox(height: 10),
              Text(
                'Última actualización: '
                '${DateFormat("d 'de' MMMM, h:mm a", 'es').format(_ultimaActualizacion!.toLocal())}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ).animate().fadeIn(delay: 190.ms, duration: 250.ms),
            ],
            const SizedBox(height: 20),
            TextFormField(
              controller: _tokenController,
              obscureText: !_tokenVisible,
              maxLines: 1,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Token',
                prefixIcon: const Icon(Icons.key_outlined),
                suffixIcon: IconButton(
                  tooltip: _tokenVisible ? 'Ocultar token' : 'Mostrar token',
                  icon: Icon(
                    _tokenVisible
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                  ),
                  onPressed: () =>
                      setState(() => _tokenVisible = !_tokenVisible),
                ),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Ingresa el token' : null,
            ).animate().fadeIn(delay: 220.ms, duration: 250.ms),
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
