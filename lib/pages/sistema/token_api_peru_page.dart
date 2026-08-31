import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../services/api_client.dart';
import '../../services/configuraciones_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/escritorio.dart';
import '../../widgets/estado_error.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/premium_button.dart';

const _claveTokenApiPeru = 'API_PERU_TOKEN';

/// Naranja de advertencia usado en toda la app para "ojo con esto" (ni
/// error rojo ni éxito verde).
const _ambar = Color(0xFFEA8C1B);

/// Edición del token de apiperu.dev (consulta real de DNI/RUC) — SOLO
/// SUPERADMIN puede ver o tocar esta pantalla (el backend además exige
/// SUPERADMIN en el propio endpoint, ver CLAVES_SOLO_SUPERADMIN en
/// configuracionesController.js: ni un ADMIN puede leer ni escribir esta
/// configuración por API directa). El token vive en la tabla
/// Configuraciones — al guardarlo, el backend lo relee de la BD en la
/// siguiente consulta, sin necesitar redeploy ni tocar nada en Render.
///
/// Escritorio (>= Breakpoints.escritorio, vía `esEscritorio`): la
/// explicación y el aviso del tope de 100 validaciones se van a un panel
/// propio a la izquierda, y el campo del token queda solo en su panel a la
/// derecha, con techo de ancho para que el input no mida 1500 px. Por
/// debajo de ese umbral el árbol de widgets es idéntico al de siempre.
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

  String get _textoUltimaActualizacion =>
      'Última actualización: '
      '${DateFormat("d 'de' MMMM, h:mm a", 'es').format(_ultimaActualizacion!.toLocal())}';

  @override
  Widget build(BuildContext context) {
    final escritorio = esEscritorio(context);

    return Scaffold(
      appBar: escritorio
          ? appBarGestion(
              context,
              titulo: 'Token de apiperu.dev',
              subtitulo: 'Consulta de DNI/RUC · solo Super Administrador',
            )
          : AppBar(title: const Text('Token de apiperu.dev')),
      body: SafeArea(
        child: _cargando
            ? const Center(child: AppLoadingIndicator())
            : _error != null && _tokenController.text.isEmpty
            ? EstadoError(mensaje: _error!, onReintentar: _cargar)
            : escritorio
            ? _construirEscritorio(context)
            : _construirFormulario(context),
      ),
    );
  }

  // ---------------------------------------------------------------- común

  /// Campo del token — mismo widget en ambas ramas para no duplicar la
  /// lógica de mostrar/ocultar ni el validador.
  Widget _campoToken() {
    return TextFormField(
      controller: _tokenController,
      obscureText: !_tokenVisible,
      maxLines: 1,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
      decoration: InputDecoration(
        labelText: 'Token',
        prefixIcon: const PhosphorIcon(PhosphorIconsRegular.key),
        suffixIcon: IconButton(
          tooltip: _tokenVisible ? 'Ocultar token' : 'Mostrar token',
          icon: PhosphorIcon(
            _tokenVisible
                ? PhosphorIconsRegular.eyeSlash
                : PhosphorIconsRegular.eye,
          ),
          onPressed: () => setState(() => _tokenVisible = !_tokenVisible),
        ),
      ),
      validator: (v) =>
          (v == null || v.trim().isEmpty) ? 'Ingresa el token' : null,
    );
  }

  List<Widget> _mensajes(ColorScheme scheme) => [
    if (_error != null) ...[
      const SizedBox(height: 12),
      Text(
        _error!,
        style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600),
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
  ];

  // ------------------------------------------------------------- celular

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
                  child: PhosphorIcon(
                    PhosphorIconsRegular.keyhole,
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
            _AvisoTope(theme: theme).animate().fadeIn(
              delay: 160.ms,
              duration: 250.ms,
            ),
            if (_ultimaActualizacion != null) ...[
              const SizedBox(height: 10),
              Text(
                _textoUltimaActualizacion,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ).animate().fadeIn(delay: 190.ms, duration: 250.ms),
            ],
            const SizedBox(height: 20),
            _campoToken().animate().fadeIn(delay: 220.ms, duration: 250.ms),
            ..._mensajes(scheme),
            const SizedBox(height: 20),
            PremiumButton(
              label: 'Guardar cambios',
              icono: PhosphorIconsRegular.check,
              cargando: _guardando,
              onPressed: _guardar,
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------- escritorio

  Widget _construirEscritorio(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
      child: ContenidoCentrado(
        anchoMaximo: 1040,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const EncabezadoEscritorio(
              anteTitulo: 'INTEGRACIONES',
              titulo: 'Token de consulta DNI/RUC',
              subtitulo:
                  'Credencial de apiperu.dev que el servidor usa para traer '
                  'datos reales de RENIEC/SUNAT.',
            ),
            const SizedBox(height: espacioEscritorio),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 4,
                    child:
                        PanelEscritorio(
                              titulo: 'Para qué sirve',
                              subtitulo: 'Y cuándo hay que renovarlo',
                              icono: PhosphorIconsRegular.info,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Lo usa el servidor para pedirle a '
                                    'apiperu.dev los datos reales de '
                                    'RENIEC/SUNAT al registrar clientes o '
                                    'trabajadores. Solo tú (Super '
                                    'Administrador) puedes verlo o cambiarlo.',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      height: 1.5,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  _AvisoTope(theme: theme),
                                ],
                              ),
                            )
                            .animate(delay: 60.ms)
                            .fadeIn(duration: 320.ms)
                            .moveY(
                              begin: 12,
                              end: 0,
                              curve: Curves.easeOutCubic,
                            ),
                  ),
                  const SizedBox(width: espacioEscritorio),
                  Expanded(
                    flex: 5,
                    child:
                        PanelEscritorio(
                              titulo: 'Token activo',
                              subtitulo: _ultimaActualizacion != null
                                  ? _textoUltimaActualizacion
                                  : 'Todavía sin registrar',
                              icono: PhosphorIconsRegular.keyhole,
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _campoToken(),
                                    ..._mensajes(scheme),
                                    const SizedBox(height: 24),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: SizedBox(
                                        width: 240,
                                        child: PremiumButton(
                                          label: 'Guardar cambios',
                                          icono: PhosphorIconsRegular.check,
                                          cargando: _guardando,
                                          onPressed: _guardar,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .animate(delay: 120.ms)
                            .fadeIn(duration: 320.ms)
                            .moveY(
                              begin: 12,
                              end: 0,
                              curve: Curves.easeOutCubic,
                            ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Aviso del tope de 100 validaciones por token — el dato que más veces se
/// olvida y el que explica por qué de pronto las búsquedas "dejan de
/// funcionar".
class _AvisoTope extends StatelessWidget {
  const _AvisoTope({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _ambar.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PhosphorIcon(
            PhosphorIconsRegular.warningCircle,
            size: 18,
            color: _ambar,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Cada token de apiperu.dev tiene un tope de 100 '
              'validaciones. Cuando se agote, las búsquedas de '
              'DNI/RUC dejan de traer datos reales (caen al modo '
              'simulado) — genera uno nuevo en apiperu.dev y '
              'pégalo aquí.',
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
