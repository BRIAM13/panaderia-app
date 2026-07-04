import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../models/usuario_sesion.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/biometric_service.dart';
import '../../widgets/biometric_offer_sheet.dart';
import '../../widgets/page_transitions.dart';
import '../hub/home_page.dart';

/// Pantalla obligatoria de cambio de contraseña, mostrada cuando el
/// backend indica `requiereCambioPassword = true` (típico en la primera
/// vez que un colaborador entra con la clave temporal asignada).
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cambio de contraseña'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: scheme.secondaryContainer,
                      ),
                      child: Icon(
                        Icons.password_rounded,
                        color: scheme.primary,
                        size: 34,
                      ),
                    )
                    .animate()
                    .fadeIn(duration: 350.ms)
                    .scale(
                      begin: const Offset(0.85, 0.85),
                      end: const Offset(1, 1),
                    ),
                const SizedBox(height: 20),
                Text(
                      'Por seguridad, actualiza tu contraseña',
                      style: theme.textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    )
                    .animate()
                    .fadeIn(delay: 80.ms, duration: 300.ms)
                    .moveY(begin: 8, end: 0),
                const SizedBox(height: 6),
                Text(
                      'Es tu primer ingreso o un administrador restableció tu clave. Crea una nueva contraseña para continuar.',
                      style: theme.textTheme.bodyMedium,
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
                        prefixIcon: Icon(Icons.lock_rounded),
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
                        prefixIcon: Icon(Icons.check_circle_outline_rounded),
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
                ElevatedButton(
                      onPressed: _cargando ? null : _cambiarPassword,
                      child: _cargando
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Guardar y continuar'),
                    )
                    .animate()
                    .fadeIn(delay: 280.ms, duration: 300.ms)
                    .moveY(begin: 8, end: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
