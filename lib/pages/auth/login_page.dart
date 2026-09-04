import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../models/usuario_sesion.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/biometric_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../widgets/biometric_offer_sheet.dart';
import '../../widgets/credito_desarrollador.dart';
import '../../widgets/mascota_video.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/premium_button.dart';
import '../hub/home_page.dart';
import 'change_password_page.dart';
import 'recuperar_password_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.mensajeInicial});

  /// Aviso a mostrar apenas se abre la pantalla (ej. "tu rol cambió, vuelve
  /// a iniciar sesión") — usado cuando algo externo (no el propio usuario)
  /// forzó volver al login. Ver `main.dart` → `_manejarRolCambiado`.
  final String? mensajeInicial;

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
  bool _tardandoMasDeLoNormal = false;
  Timer? _timerTardanza;
  String? _error;
  String? _aviso;

  @override
  void initState() {
    super.initState();
    _aviso = widget.mensajeInicial;
    _evaluarAccesoBiometrico();
    _cargarPreferenciasGuardadas();
  }

  /// Prellena el usuario y el estado del switch "Recordarme" con lo último
  /// guardado (el nombre de usuario ya se guardaba en cada login exitoso,
  /// pero esta pantalla nunca lo volvía a leer). La contraseña nunca se
  /// guarda en texto plano acá a propósito: para eso está el autocompletado
  /// nativo (ver AutofillGroup más abajo), que delega ese trabajo al
  /// gestor de contraseñas del sistema (Samsung Pass, Google, etc.), cifrado
  /// y fuera del control de la app.
  Future<void> _cargarPreferenciasGuardadas() async {
    final recordarme = await _authService.storage.obtenerRecordarme();
    final nombreGuardado = recordarme
        ? await _authService.storage.obtenerNombreUsuario()
        : null;
    if (!mounted) return;
    setState(() {
      _recordarme = recordarme;
      if (nombreGuardado != null && nombreGuardado.isNotEmpty) {
        _usuarioController.text = nombreGuardado;
      }
    });
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
    _timerTardanza?.cancel();
    _usuarioController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _iniciarSesion() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _cargando = true;
      _tardandoMasDeLoNormal = false;
      _error = null;
    });

    // El backend está en un plan gratis cuya base de datos se pausa sola
    // tras un rato sin uso — la primera consulta después de eso puede
    // tardar bastante en "despertarla". Si el login se demora, se avisa en
    // vez de dejar el botón girando sin explicación (parecía trabado).
    _timerTardanza = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _tardandoMasDeLoNormal = true);
    });

    try {
      final usuario = await _authService.login(
        nombreUsuario: _usuarioController.text.trim(),
        password: _passwordController.text,
        recordarme: _recordarme,
      );
      // Avisa al framework de autocompletado que el login fue exitoso, para
      // que el gestor de contraseñas del sistema (Samsung Pass, Google
      // Password Manager, etc.) ofrezca guardar las credenciales recién
      // usadas — sin esto, nunca aparece esa ventanita.
      TextInput.finishAutofillContext();
      if (!mounted) return;
      await _continuarDespuesDeLogin(usuario);
    } on ApiException catch (e) {
      TextInput.finishAutofillContext(shouldSave: false);
      setState(() => _error = e.mensaje);
    } catch (_) {
      TextInput.finishAutofillContext(shouldSave: false);
      setState(
        () => _error = 'Ocurrió un error inesperado. Intenta nuevamente.',
      );
    } finally {
      _timerTardanza?.cancel();
      if (mounted) {
        setState(() {
          _cargando = false;
          _tardandoMasDeLoNormal = false;
        });
      }
    }
  }

  Future<void> _ingresarConHuella() async {
    setState(() {
      _cargandoBiometria = true;
      _error = null;
    });

    try {
      final autenticado = await _biometricService.autenticar(
        razon: 'Confirma tu huella para ingresar a Panadería Ronceros',
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final esEscritorio = constraints.maxWidth >= Breakpoints.tablet;
            final formulario = _construirFormulario(theme, scheme, esEscritorio);

            // Grupo B: el login es UNA sola acción con un formulario chico
            // — no gana nada con "más columnas". En pantallas anchas el
            // formulario angosto solo (sin nada más) se veía "perdido" y
            // estirado en medio de tanto espacio, así que se centra en una
            // tarjeta de ancho fijo, sobre un fondo con los colores de la
            // marca a pantalla completa — no un recorte en blanco en medio
            // de la ventana.
            if (!esEscritorio) return formulario;

            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [scheme.primary, scheme.secondary],
                ),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 460,
                    // Con la altura acotada al espacio real de la ventana,
                    // el formulario (ya compactado para escritorio) entra
                    // completo sin scroll en pantallas normales de laptop
                    // — y si alguna vez no entra (ventana muy baja), el
                    // SingleChildScrollView de adentro se encarga solo, en
                    // vez de que la página entera tenga que desplazarse.
                    maxHeight: constraints.maxHeight - 24,
                  ),
                  child:
                      Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 36,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.35),
                                width: 1.4,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.25),
                                  blurRadius: 40,
                                  offset: const Offset(0, 20),
                                ),
                              ],
                            ),
                            child: formulario,
                          )
                          .animate()
                          .fadeIn(duration: 380.ms)
                          .moveY(
                            begin: 18,
                            end: 0,
                            curve: Curves.easeOutCubic,
                          )
                          .scale(
                            begin: const Offset(0.97, 0.97),
                            end: const Offset(1, 1),
                            curve: Curves.easeOutCubic,
                          ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _construirFormulario(
    ThemeData theme,
    ColorScheme scheme,
    bool esEscritorio,
  ) {
    // El alto se toma de MediaQuery y no de las restricciones que llegan al
    // LayoutBuilder a propósito: al abrirse el teclado el Scaffold encoge su
    // cuerpo, y si el tamaño de la mascota dependiera de eso el formulario
    // entero cambiaría de escala apenas se toca un campo. Con MediaQuery la
    // medida es la de la pantalla, estable durante toda la sesión.
    final mq = MediaQuery.of(context);
    final altoUtil = mq.size.height - mq.padding.top - mq.padding.bottom;

    // El bloque de "Ingresar con huella" (círculo + texto + sus dos gaps)
    // agrega ~114dp que la calibración original no contemplaba — quien lo
    // tiene activado se quedaba sin ver "LABS" del pie. Se resta acá antes
    // de calcular t, así que a la MISMA altura de pantalla, con huella
    // activa todo escala un poco más compacto y libera justo ese espacio,
    // en vez de necesitar una rama de código aparte para ese caso.
    final alturaBiometria = _biometriaDisponibleParaAcceso ? 114.0 : 0.0;

    // 0 en un celular chico (~620dp útiles) y 1 de ~940dp para arriba: entre
    // esos dos extremos la mascota y los espacios verticales se interpolan,
    // en vez de usar constantes que en pantallas bajas empujaban el pie
    // ("Powered by Ronceros Labs") fuera del área visible.
    final t = ((altoUtil - alturaBiometria - 620) / (940 - 620)).clamp(
      0.0,
      1.0,
    );
    double esc(double minimo, double maximo) => minimo + (maximo - minimo) * t;

    final altoMascota = esc(140, 285);

    return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: esEscritorio ? 0 : 28,
            vertical: esEscritorio ? 8 : esc(12, 24),
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: esEscritorio ? 4 : esc(8, 24)),
                Center(
                      child: SizedBox(
                        // 680:900 es la proporción real del recorte de los
                        // clips, así que el alto manda y el ancho se deduce.
                        width: (esEscritorio ? 210.0 : altoMascota) * 680 / 900,
                        height: esEscritorio ? 210.0 : altoMascota,
                        // El usuario mira esta pantalla mientras escribe,
                        // así que el saludo se repite todo el tiempo (no
                        // solo una vez) — el clip trae su propio canal alfa
                        // empaquetado y el shader lo recompone, así que el
                        // personaje se recorta contra el fondo sin caja ni
                        // rectángulo alrededor.
                        child: const MascotaVideo(
                          modo: ModoMascota.soloSaludo,
                        ),
                      ),
                    )
                    .animate()
                    .fadeIn(duration: 350.ms)
                    .scale(
                      begin: const Offset(0.85, 0.85),
                      end: const Offset(1, 1),
                    ),
                Text(
                      'Panadería Ronceros',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        height: 1.1,
                      ),
                    )
                    .animate()
                    .fadeIn(delay: 80.ms, duration: 300.ms)
                    .moveY(begin: 8, end: 0),
                const SizedBox(height: 6),
                Text(
                      'Inicia sesión para continuar',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                        color: AppColors.secondary,
                      ),
                    )
                    .animate()
                    .fadeIn(delay: 120.ms, duration: 300.ms)
                    .moveY(begin: 8, end: 0),
                if (_aviso != null) ...[
                  const SizedBox(height: 20),
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
                      )
                      .animate()
                      .fadeIn(duration: 300.ms)
                      .moveY(begin: 8, end: 0),
                ],
                SizedBox(height: esEscritorio ? 16 : esc(18, 32)),
                AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                            controller: _usuarioController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.username],
                            decoration: const InputDecoration(
                              labelText: 'Usuario (DNI o RUC)',
                              prefixIcon: PhosphorIcon(
                                PhosphorIconsRegular.identificationCard,
                              ),
                            ),
                            validator: (value) =>
                                (value == null || value.trim().isEmpty)
                                ? 'Ingresa tu DNI o RUC'
                                : null,
                          )
                          .animate()
                          .fadeIn(delay: 160.ms, duration: 300.ms)
                          .moveY(begin: 8, end: 0),
                      SizedBox(height: esEscritorio ? 16 : esc(12, 16)),
                      TextFormField(
                            controller: _passwordController,
                            obscureText: !_passwordVisible,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.password],
                            onFieldSubmitted: (_) => _iniciarSesion(),
                            decoration: InputDecoration(
                              labelText: 'Contraseña',
                              prefixIcon: const PhosphorIcon(
                                PhosphorIconsRegular.lockSimple,
                              ),
                              suffixIcon: IconButton(
                                icon: PhosphorIcon(
                                  _passwordVisible
                                      ? PhosphorIconsRegular.eyeSlash
                                      : PhosphorIconsRegular.eye,
                                ),
                                onPressed: () => setState(
                                  () => _passwordVisible = !_passwordVisible,
                                ),
                              ),
                            ),
                            validator: (value) =>
                                (value == null || value.isEmpty)
                                ? 'Ingresa tu contraseña'
                                : null,
                          )
                          .animate()
                          .fadeIn(delay: 200.ms, duration: 300.ms)
                          .moveY(begin: 8, end: 0),
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _cargando
                        ? null
                        : () => pushSlideUpFade(
                            context,
                            (_) => const RecuperarPasswordPage(),
                          ),
                    child: const Text('¿Olvidaste tu contraseña?'),
                  ),
                ).animate().fadeIn(delay: 220.ms, duration: 300.ms),
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
                SizedBox(height: esEscritorio ? 16 : esc(10, 16)),
                PremiumButton(
                      label: 'Iniciar sesión',
                      icono: PhosphorIconsRegular.signIn,
                      cargando: _cargando,
                      onPressed: _iniciarSesion,
                    )
                    .animate()
                    .fadeIn(delay: 280.ms, duration: 300.ms)
                    .moveY(begin: 8, end: 0),
                if (_tardandoMasDeLoNormal) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Esto puede tardar un poco: el servidor estaba '
                    'inactivo y se está despertando…',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ).animate().fadeIn(duration: 250.ms),
                ],
                if (_biometriaDisponibleParaAcceso) ...[
                  SizedBox(height: esEscritorio ? 24 : esc(14, 24)),
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
                                  : PhosphorIcon(
                                      PhosphorIconsRegular.fingerprint,
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
                SizedBox(height: esEscritorio ? 12 : esc(14, 28)),
                const CreditoDesarrollador()
                    .animate()
                    .fadeIn(delay: 380.ms, duration: 300.ms),
              ],
            ),
          ),
        );
  }
}
