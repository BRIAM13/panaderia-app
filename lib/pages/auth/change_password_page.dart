import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../models/usuario_sesion.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/biometric_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../widgets/biometric_offer_sheet.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/premium_button.dart';
import '../hub/home_page.dart';

/// Pantalla obligatoria de cambio de contraseña, mostrada cuando el
/// backend indica `requiereCambioPassword = true` (típico en la primera
/// vez que un colaborador entra con la clave temporal asignada).
///
/// Grupo B (pantalla de entrada/bloqueo): son dos campos y un botón — no
/// hay nada que repartir en columnas, así que en ventana ancha NO se aplica
/// un layout de escritorio: el formulario deja de estirarse y se recoge en
/// una tarjeta centrada de 440 px sobre el fondo de la app, con el mismo
/// umbral que usa el login ([Breakpoints.tablet], 600 px) porque comparten
/// el mismo momento del flujo y deben verse como la misma pantalla.
class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key, required this.usuario});

  final UsuarioSesion usuario;

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _nuevaController = TextEditingController();
  final _confirmarController = TextEditingController();
  final _authService = AuthService();
  final _biometricService = BiometricService();

  bool _cargando = false;
  String? _error;

  @override
  void dispose() {
    _nuevaController.dispose();
    _confirmarController.dispose();
    super.dispose();
  }

  Future<void> _cambiarPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      await _authService.cambiarPassword(passwordNueva: _nuevaController.text);

      if (!mounted) return;

      final disponibleBiometria = await _biometricService.esDisponible();
      if (disponibleBiometria && mounted) {
        final activar = await showBiometricOfferSheet(context);
        if (activar == true) {
          await _authService.storage.establecerBiometriaActiva(true);
        }
      }

      if (!mounted) return;
      final usuarioActualizado = widget.usuario.copyWith(
        requiereCambioPassword: false,
      );
      Navigator.of(context).pushReplacement(
        SlideUpFadeRoute(builder: (_) => HomePage(usuario: usuarioActualizado)),
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
    // Mismo umbral que el login: a partir de acá el formulario deja de
    // estirarse y se recoge en una tarjeta centrada.
    final anchoAmplio =
        MediaQuery.sizeOf(context).width >= Breakpoints.tablet;

    final formulario = Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.secondaryContainer,
                ),
                child: PhosphorIcon(
                  PhosphorIconsDuotone.password,
                  color: scheme.primary,
                  size: 40,
                ),
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
                'PRIMER INGRESO',
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
                'Por seguridad, actualiza tu contraseña',
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
                'Es tu primer ingreso o un administrador restableció tu clave. Crea una nueva contraseña para continuar.',
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                textAlign: TextAlign.center,
              )
              .animate()
              .fadeIn(delay: 120.ms, duration: 300.ms)
              .moveY(begin: 8, end: 0),
          const SizedBox(height: 28),
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
          const SizedBox(height: 20),
          PremiumButton(
                label: 'Guardar y continuar',
                icono: PhosphorIconsRegular.check,
                cargando: _cargando,
                onPressed: _cambiarPassword,
              )
              .animate()
              .fadeIn(delay: 280.ms, duration: 300.ms)
              .moveY(begin: 8, end: 0),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cambio de contraseña'),
        automaticallyImplyLeading: false,
      ),
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
}
