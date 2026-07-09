import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../services/api_client.dart';
import '../../services/clientes_service.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/premium_button.dart';
import '../../widgets/verificacion_otp.dart';

/// Cambio de contraseña autoservicio (rol CLIENTE), distinto del cambio
/// obligatorio de primer login: no pide la contraseña actual — pide
/// autorizar el cambio con un código enviado a un celular/correo YA
/// verificado. Así, si alguien más usa la sesión ya iniciada del dueño de
/// la cuenta (ej. la prestó a un trabajador), no puede cambiar la
/// contraseña sin tener acceso real a ese celular o correo.
class CambiarPasswordSeguroPage extends StatefulWidget {
  const CambiarPasswordSeguroPage({super.key});

  @override
  State<CambiarPasswordSeguroPage> createState() =>
      _CambiarPasswordSeguroPageState();
}

class _CambiarPasswordSeguroPageState extends State<CambiarPasswordSeguroPage> {
  final _formKey = GlobalKey<FormState>();
  final _nuevaController = TextEditingController();
  final _confirmarController = TextEditingController();
  final _clientesService = ClientesService();

  bool _cargandoPerfil = true;
  bool _telefonoVerificado = false;
  bool _emailVerificado = false;
  AutorizacionResultado? _autorizacion;
  bool _guardando = false;
  String? _error;
  String? _mensajeExito;

  @override
  void initState() {
    super.initState();
    _cargarEstadoVerificacion();
  }

  @override
  void dispose() {
    _nuevaController.dispose();
    _confirmarController.dispose();
    super.dispose();
  }

  Future<void> _cargarEstadoVerificacion() async {
    setState(() => _cargandoPerfil = true);
    try {
      final cliente = await _clientesService.obtenerMiPerfil();
      setState(() {
        _telefonoVerificado = cliente.telefonoVerificado;
        _emailVerificado = cliente.emailVerificado;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(() => _error = 'No se pudo cargar tu perfil.');
    } finally {
      if (mounted) setState(() => _cargandoPerfil = false);
    }
  }

  bool get _tieneCanalVerificado => _telefonoVerificado || _emailVerificado;

  Future<void> _autorizar() async {
    final resultado = await mostrarAutorizacionCambio(
      context,
      telefonoVerificado: _telefonoVerificado,
      emailVerificado: _emailVerificado,
      clientesService: _clientesService,
      titulo: 'Autoriza el cambio de contraseña',
    );
    if (resultado != null) setState(() => _autorizacion = resultado);
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    final autorizacion = _autorizacion;
    if (autorizacion == null) {
      setState(() => _error = 'Primero autoriza este cambio.');
      return;
    }

    setState(() {
      _guardando = true;
      _error = null;
      _mensajeExito = null;
    });

    try {
      await _clientesService.cambiarPasswordSeguro(
        passwordNueva: _nuevaController.text,
        canalAutorizacion: autorizacion.canal,
        codigoAutorizacion: autorizacion.codigo,
      );
      if (!mounted) return;
      setState(
        () => _mensajeExito = 'Tu contraseña se actualizó correctamente.',
      );
      _nuevaController.clear();
      _confirmarController.clear();
      _autorizacion = null;
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Cambiar contraseña')),
      body: SafeArea(
        child: _cargandoPerfil
            ? const Center(child: AppLoadingIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: !_tieneCanalVerificado
                    ? _AvisoSinVerificar(theme: theme)
                    : Form(
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
                                .fadeIn(duration: 300.ms)
                                .scale(
                                  begin: const Offset(0.85, 0.85),
                                  end: const Offset(1, 1),
                                ),
                            const SizedBox(height: 20),
                            Text(
                              'Cambia tu contraseña de forma segura',
                              style: theme.textTheme.titleLarge,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 20),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: scheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _autorizacion != null
                                        ? Icons.check_circle_rounded
                                        : Icons.shield_outlined,
                                    color: _autorizacion != null
                                        ? const Color(0xFF2E7D32)
                                        : scheme.primary,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _autorizacion != null
                                          ? 'Cambio autorizado por ${_autorizacion!.canal == 'SMS' ? 'SMS' : 'correo'}'
                                          : 'Este cambio requiere autorización',
                                    ),
                                  ),
                                  if (_autorizacion == null)
                                    FilledButton(
                                      onPressed: _autorizar,
                                      child: const Text('Autorizar'),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: _nuevaController,
                              obscureText: true,
                              enabled: _autorizacion != null,
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
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _confirmarController,
                              obscureText: true,
                              enabled: _autorizacion != null,
                              decoration: const InputDecoration(
                                labelText: 'Confirmar nueva contraseña',
                                prefixIcon: Icon(
                                  Icons.check_circle_outline_rounded,
                                ),
                              ),
                              validator: (value) =>
                                  (value != _nuevaController.text)
                                  ? 'Las contraseñas no coinciden'
                                  : null,
                            ),
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
                              label: 'Actualizar contraseña',
                              icono: Icons.lock_reset_rounded,
                              cargando: _guardando,
                              onPressed: _autorizacion == null
                                  ? null
                                  : _guardar,
                            ),
                          ],
                        ),
                      ),
              ),
      ),
    );
  }
}

class _AvisoSinVerificar extends StatelessWidget {
  const _AvisoSinVerificar({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.shield_outlined, size: 48, color: theme.colorScheme.error),
        const SizedBox(height: 16),
        Text(
          'Verifica tu celular o correo primero',
          style: theme.textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Por seguridad, necesitas al menos un canal verificado en Mi Perfil antes de poder cambiar tu contraseña.',
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
