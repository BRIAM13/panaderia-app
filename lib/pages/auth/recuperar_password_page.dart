import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../widgets/premium_button.dart';

/// "Olvidé mi contraseña": dos pasos, mismo diseño de tarjeta centrada que
/// [ChangePasswordPage] (ver ese archivo para el porqué del umbral de
/// escritorio compartido con el login).
///
/// Paso 1 pide el mismo identificador que el login (DNI/RUC) y el backend
/// SIEMPRE responde el mismo mensaje genérico, exista o no la cuenta — así
/// que acá no hay "cuenta no encontrada" que mostrar, solo se avanza al
/// paso 2 apenas el backend confirma que recibió la solicitud.
class RecuperarPasswordPage extends StatefulWidget {
  const RecuperarPasswordPage({super.key});

  @override
  State<RecuperarPasswordPage> createState() => _RecuperarPasswordPageState();
}

class _RecuperarPasswordPageState extends State<RecuperarPasswordPage> {
  final _formKeyPaso1 = GlobalKey<FormState>();
  final _formKeyPaso2 = GlobalKey<FormState>();
  final _usuarioController = TextEditingController();
  final _codigoController = TextEditingController();
  final _nuevaController = TextEditingController();
  final _confirmarController = TextEditingController();
  final _authService = AuthService();

  int _paso = 1;
  bool _cargando = false;
  bool _reenviando = false;
  String? _error;
  String? _aviso;

  @override
  void dispose() {
    _usuarioController.dispose();
    _codigoController.dispose();
    _nuevaController.dispose();
    _confirmarController.dispose();
    super.dispose();
  }

  Future<void> _solicitarCodigo() async {
    if (!_formKeyPaso1.currentState!.validate()) return;

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      await _authService.solicitarRecuperacionPassword(
        nombreUsuario: _usuarioController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _paso = 2;
        _aviso =
            'Si tu usuario existe y tiene un correo verificado, te llegará '
            'un código de 6 dígitos.';
      });
    } on ApiException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(
        () => _error = 'Ocurrió un error inesperado. Intenta nuevamente.',
      );
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _reenviarCodigo() async {
    setState(() {
      _reenviando = true;
      _error = null;
      _aviso = null;
    });

    try {
      await _authService.solicitarRecuperacionPassword(
        nombreUsuario: _usuarioController.text.trim(),
      );
      if (!mounted) return;
      setState(() => _aviso = 'Código reenviado, si tu cuenta lo permite.');
    } on ApiException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(
        () => _error = 'Ocurrió un error inesperado. Intenta nuevamente.',
      );
    } finally {
      if (mounted) setState(() => _reenviando = false);
    }
  }

  Future<void> _confirmarCambio() async {
    if (!_formKeyPaso2.currentState!.validate()) return;

    setState(() {
      _cargando = true;
      _error = null;
      _aviso = null;
    });

    try {
      await _authService.confirmarRecuperacionPassword(
        nombreUsuario: _usuarioController.text.trim(),
        codigo: _codigoController.text.trim(),
        passwordNueva: _nuevaController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Contraseña actualizada. Ya puedes iniciar sesión con ella.',
          ),
        ),
      );
    } on ApiException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(
        () => _error = 'Ocurrió un error inesperado. Intenta nuevamente.',
      );
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final anchoAmplio =
        MediaQuery.sizeOf(context).width >= Breakpoints.tablet;

    final formulario = _paso == 1
        ? _construirPaso1(theme, scheme)
        : _construirPaso2(theme, scheme);

    return Scaffold(
      appBar: AppBar(title: const Text('Recuperar contraseña')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: anchoAmplio
              ? Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Container(
                          padding: const EdgeInsets.fromLTRB(36, 40, 36, 40),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: AppColors.surfaceMuted,
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.07),
                                blurRadius: 40,
                                offset: const Offset(0, 18),
                              ),
                            ],
                          ),
                          child: formulario,
                        )
                        .animate()
                        .fadeIn(duration: 320.ms)
                        .moveY(begin: 14, end: 0, curve: Curves.easeOutCubic),
                  ),
                )
              : formulario,
        ),
      ),
    );
  }

  Widget _construirEncabezado(
    ThemeData theme, {
    required IconData icono,
    required String eyebrow,
    required String titulo,
    required String descripcion,
  }) {
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
              width: 84,
              height: 84,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.secondaryContainer,
              ),
              child: PhosphorIcon(icono, color: scheme.primary, size: 40),
            )
            .animate()
            .fadeIn(duration: 350.ms)
            .scale(
              begin: const Offset(0.85, 0.85),
              end: const Offset(1, 1),
              curve: Curves.easeOutBack,
            ),
        const SizedBox(height: 18),
        Text(
              eyebrow,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
                color: AppColors.secondary,
              ),
            )
            .animate()
            .fadeIn(delay: 60.ms, duration: 300.ms)
            .moveY(begin: 8, end: 0),
        const SizedBox(height: 8),
        Text(
              titulo,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1.15,
              ),
              textAlign: TextAlign.center,
            )
            .animate()
            .fadeIn(delay: 80.ms, duration: 300.ms)
            .moveY(begin: 8, end: 0),
        const SizedBox(height: 8),
        Text(
              descripcion,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              textAlign: TextAlign.center,
            )
            .animate()
            .fadeIn(delay: 120.ms, duration: 300.ms)
            .moveY(begin: 8, end: 0),
      ],
    );
  }

  Widget _construirAvisoYError(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Column(
      children: [
        if (_aviso != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PhosphorIcon(
                  PhosphorIconsRegular.info,
                  color: scheme.onPrimaryContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _aviso!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600),
          ),
        ],
      ],
    );
  }

  Widget _construirPaso1(ThemeData theme, ColorScheme scheme) {
    return Form(
      key: _formKeyPaso1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _construirEncabezado(
            theme,
            icono: PhosphorIconsDuotone.identificationCard,
            eyebrow: 'PASO 1 DE 2',
            titulo: '¿Cuál es tu usuario?',
            descripcion:
                'Ingresa tu DNI o RUC y, si tienes una cuenta con correo '
                'verificado, te enviaremos un código para restablecer tu '
                'contraseña.',
          ),
          const SizedBox(height: 28),
          TextFormField(
                controller: _usuarioController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _solicitarCodigo(),
                decoration: const InputDecoration(
                  labelText: 'Usuario (DNI o RUC)',
                  prefixIcon: PhosphorIcon(
                    PhosphorIconsRegular.identificationCard,
                  ),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Ingresa tu DNI o RUC'
                    : null,
              )
              .animate()
              .fadeIn(delay: 200.ms, duration: 300.ms)
              .moveY(begin: 8, end: 0),
          _construirAvisoYError(theme),
          const SizedBox(height: 20),
          PremiumButton(
                label: 'Enviar código',
                icono: PhosphorIconsRegular.paperPlaneTilt,
                cargando: _cargando,
                onPressed: _solicitarCodigo,
              )
              .animate()
              .fadeIn(delay: 280.ms, duration: 300.ms)
              .moveY(begin: 8, end: 0),
        ],
      ),
    );
  }

  Widget _construirPaso2(ThemeData theme, ColorScheme scheme) {
    return Form(
      key: _formKeyPaso2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _construirEncabezado(
            theme,
            icono: PhosphorIconsDuotone.password,
            eyebrow: 'PASO 2 DE 2',
            titulo: 'Ingresa el código y tu nueva contraseña',
            descripcion:
                'Revisa el correo verificado de tu cuenta. El código vence '
                'en 10 minutos.',
          ),
          const SizedBox(height: 28),
          TextFormField(
                controller: _codigoController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'Código de 6 dígitos',
                  counterText: '',
                  prefixIcon: PhosphorIcon(PhosphorIconsRegular.shieldCheck),
                ),
                validator: (value) {
                  if (value == null || !RegExp(r'^\d{6}$').hasMatch(value.trim())) {
                    return 'Ingresa el código de 6 dígitos';
                  }
                  return null;
                },
              )
              .animate()
              .fadeIn(delay: 160.ms, duration: 300.ms)
              .moveY(begin: 8, end: 0),
          const SizedBox(height: 16),
          TextFormField(
                controller: _nuevaController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Nueva contraseña',
                  prefixIcon: PhosphorIcon(PhosphorIconsRegular.lockKey),
                ),
                validator: (value) {
                  if (value == null || value.length < 8) {
                    return 'Debe tener al menos 8 caracteres';
                  }
                  return null;
                },
              )
              .animate()
              .fadeIn(delay: 200.ms, duration: 300.ms)
              .moveY(begin: 8, end: 0),
          const SizedBox(height: 16),
          TextFormField(
                controller: _confirmarController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirmar nueva contraseña',
                  prefixIcon: PhosphorIcon(PhosphorIconsRegular.checkCircle),
                ),
                validator: (value) => (value != _nuevaController.text)
                    ? 'Las contraseñas no coinciden'
                    : null,
              )
              .animate()
              .fadeIn(delay: 240.ms, duration: 300.ms)
              .moveY(begin: 8, end: 0),
          _construirAvisoYError(theme),
          const SizedBox(height: 20),
          PremiumButton(
                label: 'Cambiar contraseña',
                icono: PhosphorIconsRegular.check,
                cargando: _cargando,
                onPressed: _confirmarCambio,
              )
              .animate()
              .fadeIn(delay: 280.ms, duration: 300.ms)
              .moveY(begin: 8, end: 0),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _reenviando ? null : _reenviarCodigo,
              child: Text(
                _reenviando ? 'Reenviando…' : 'Reenviar código',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
