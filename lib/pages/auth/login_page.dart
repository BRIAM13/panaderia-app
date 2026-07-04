import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../models/usuario_sesion.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/biometric_service.dart';
import '../../widgets/biometric_offer_sheet.dart';
import '../../widgets/page_transitions.dart';
import '../hub/home_page.dart';
import 'change_password_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usuarioController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  final _biometricService = BiometricService();

  bool _recordarme = true;
  bool _passwordVisible = false;
  bool _cargando = false;
  bool _cargandoBiometria = false;
  bool _biometriaDisponibleParaAcceso = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _evaluarAccesoBiometrico();
  }

  Future<void> _evaluarAccesoBiometrico() async {
    final biometriaActiva = await _authService.storage.obtenerBiometriaActiva();
    if (!biometriaActiva) return;

    final hayTokenGuardado = await _authService.storage.obtenerRefreshToken();
    final hardwareDisponible = await _biometricService.esDisponible();

    if (!mounted) return;
    setState(() {
      _biometriaDisponibleParaAcceso =
          biometriaActiva && hardwareDisponible && hayTokenGuardado != null;
    });
  }

  @override
  void dispose() {
    _usuarioController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _iniciarSesion() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final usuario = await _authService.login(
        nombreUsuario: _usuarioController.text.trim(),
        password: _passwordController.text,
        recordarme: _recordarme,
      );
      if (!mounted) return;
      await _continuarDespuesDeLogin(usuario);
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

  Future<void> _ingresarConHuella() async {
    setState(() {
      _cargandoBiometria = true;
      _error = null;
    });

    try {
      final autenticado = await _biometricService.autenticar(
        razon: 'Confirma tu huella para ingresar a Corporación Ronceros',
      );
      if (!autenticado) return;

      final usuario = await _authService.revalidarSesion();
      if (!mounted) return;
      await _continuarDespuesDeLogin(usuario, ofrecerBiometria: false);
    } on ApiException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(
        () =>
            _error = 'No se pudo validar tu huella. Intenta con tu contraseña.',
      );
    } finally {
      if (mounted) setState(() => _cargandoBiometria = false);
    }
  }

  Future<void> _continuarDespuesDeLogin(
    UsuarioSesion usuario, {
    bool ofrecerBiometria = true,
  }) async {
    if (usuario.requiereCambioPassword) {
      await pushSlideUpFade(
        context,
        (_) => ChangePasswordPage(usuario: usuario),
      );
      return;
    }

    if (ofrecerBiometria) {
      await _ofrecerActivarBiometriaSiAplica();
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      SlideUpFadeRoute(builder: (_) => HomePage(usuario: usuario)),
    );
  }

  Future<void> _ofrecerActivarBiometriaSiAplica() async {
    final yaActiva = await _authService.storage.obtenerBiometriaActiva();
    if (yaActiva) return;

    final disponible = await _biometricService.esDisponible();
    if (!disponible || !mounted) return;

    final activar = await showBiometricOfferSheet(context);
    if (activar == true) {
      await _authService.storage.establecerBiometriaActiva(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                Center(
                      child: Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [scheme.primary, scheme.secondary],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: const Icon(
                          Icons.bakery_dining_rounded,
                          color: Colors.white,
                          size: 40,
                        ),
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
                      'Corporación Ronceros',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge,
                    )
                    .animate()
                    .fadeIn(delay: 80.ms, duration: 300.ms)
                    .moveY(begin: 8, end: 0),
                const SizedBox(height: 4),
                Text(
                      'Inicia sesión para continuar',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    )
                    .animate()
                    .fadeIn(delay: 120.ms, duration: 300.ms)
                    .moveY(begin: 8, end: 0),
                const SizedBox(height: 32),
                TextFormField(
                      controller: _usuarioController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Usuario',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                          ? 'Ingresa tu usuario'
                          : null,
                    )
                    .animate()
                    .fadeIn(delay: 160.ms, duration: 300.ms)
                    .moveY(begin: 8, end: 0),
                const SizedBox(height: 16),
                TextFormField(
                      controller: _passwordController,
                      obscureText: !_passwordVisible,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _iniciarSesion(),
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _passwordVisible
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                          ),
                          onPressed: () => setState(
                            () => _passwordVisible = !_passwordVisible,
                          ),
                        ),
                      ),
                      validator: (value) => (value == null || value.isEmpty)
                          ? 'Ingresa tu contraseña'
                          : null,
                    )
                    .animate()
                    .fadeIn(delay: 200.ms, duration: 300.ms)
                    .moveY(begin: 8, end: 0),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Switch(
                      value: _recordarme,
                      onChanged: (v) => setState(() => _recordarme = v),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Recordarme en este dispositivo',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ).animate().fadeIn(delay: 240.ms, duration: 300.ms),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: scheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                ElevatedButton(
                      onPressed: _cargando ? null : _iniciarSesion,
                      child: _cargando
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Iniciar sesión'),
                    )
                    .animate()
                    .fadeIn(delay: 280.ms, duration: 300.ms)
                    .moveY(begin: 8, end: 0),
                if (_biometriaDisponibleParaAcceso) ...[
                  const SizedBox(height: 24),
                  Center(
                    child: Column(
                      children: [
                        Material(
                          color: scheme.secondaryContainer,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _cargandoBiometria
                                ? null
                                : _ingresarConHuella,
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: _cargandoBiometria
                                  ? const SizedBox(
                                      width: 26,
                                      height: 26,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(
                                      Icons.fingerprint_rounded,
                                      size: 32,
                                      color: scheme.primary,
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Ingresar con huella',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ).animate().fadeIn(delay: 320.ms, duration: 300.ms),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
