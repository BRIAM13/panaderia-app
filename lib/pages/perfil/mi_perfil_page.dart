import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../models/cliente_model.dart';
import '../../services/api_client.dart';
import '../../services/clientes_service.dart';
import '../../services/geolocation_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/text_formatters.dart';
import '../../widgets/ad_banner.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/verificacion_otp.dart';
import 'cambiar_password_seguro_page.dart';

/// Autoservicio del cliente: ve sus datos verificados (nombres/documento,
/// de solo lectura), verifica/cambia celular y correo con código de un
/// solo uso, edita su dirección de entrega, y cambia su contraseña con
/// autorización previa. Cambiar celular/correo/contraseña una vez que ya
/// hay algún canal verificado exige autorizar primero con un código
/// enviado a ese canal — así, si alguien más usa la sesión ya iniciada del
/// dueño, no puede tocar estos datos sin acceso real a su celular/correo.
class MiPerfilPage extends StatefulWidget {
  const MiPerfilPage({super.key, this.mostrarAnuncio = false});

  /// Solo debe encender esto quien la abre sabiendo que el usuario es
  /// cliente puro (no híbrido) — el anuncio existe para monetizar a
  /// quienes solo compran, no a quienes también trabajan ahí.
  final bool mostrarAnuncio;

  @override
  State<MiPerfilPage> createState() => _MiPerfilPageState();
}

class _MiPerfilPageState extends State<MiPerfilPage> {
  final _direccionController = TextEditingController();
  final _clientesService = ClientesService();
  final _geolocationService = const GeolocationService();

  Cliente? _cliente;
  bool _cargando = true;
  bool _guardandoDireccion = false;
  bool _obteniendoUbicacion = false;
  String? _error;
  String? _mensajeExito;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _direccionController.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final cliente = await _clientesService.obtenerMiPerfil();
      setState(() {
        _cliente = cliente;
        _direccionController.text = (cliente.direccion ?? '').toUpperCase();
      });
    } on ApiException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(() => _error = 'No se pudo cargar tu perfil.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  bool get _requiereAutorizacion =>
      (_cliente?.telefonoVerificado ?? false) ||
      (_cliente?.emailVerificado ?? false);

  Future<AutorizacionResultado?> _pedirAutorizacionSiNecesaria(
    String titulo,
  ) async {
    if (!_requiereAutorizacion) return null;
    return mostrarAutorizacionCambio(
      context,
      telefonoVerificado: _cliente!.telefonoVerificado,
      emailVerificado: _cliente!.emailVerificado,
      clientesService: _clientesService,
      titulo: titulo,
    );
  }

  Future<void> _gestionarCelular() async {
    final cliente = _cliente!;
    AutorizacionResultado? autorizacion;
    if (_requiereAutorizacion) {
      autorizacion = await _pedirAutorizacionSiNecesaria(
        'Autoriza el cambio de celular',
      );
      if (autorizacion == null) return;
    }
    if (!mounted) return;
    final verificado = await mostrarVerificarCanal(
      context,
      canal: 'SMS',
      clientesService: _clientesService,
      autorizacion: autorizacion,
      valorInicial: cliente.telefono,
    );
    if (verificado) _cargar();
  }

  Future<void> _gestionarCorreo() async {
    final cliente = _cliente!;
    AutorizacionResultado? autorizacion;
    if (_requiereAutorizacion) {
      autorizacion = await _pedirAutorizacionSiNecesaria(
        'Autoriza el cambio de correo',
      );
      if (autorizacion == null) return;
    }
    if (!mounted) return;
    final verificado = await mostrarVerificarCanal(
      context,
      canal: 'EMAIL',
      clientesService: _clientesService,
      autorizacion: autorizacion,
      valorInicial: cliente.email,
    );
    if (verificado) _cargar();
  }

  Future<void> _abrirCambioPassword() async {
    await pushSlideUpFade(context, (_) => const CambiarPasswordSeguroPage());
  }

  Future<void> _autocompletarConGps() async {
    setState(() {
      _obteniendoUbicacion = true;
      _error = null;
    });
    try {
      final direccion = await _geolocationService.obtenerDireccionActual();
      setState(() => _direccionController.text = direccion.toUpperCase());
    } on GeolocationException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(
        () => _error = 'No se pudo obtener tu ubicación. Intenta nuevamente.',
      );
    } finally {
      if (mounted) setState(() => _obteniendoUbicacion = false);
    }
  }

  Future<void> _guardarDireccion() async {
    setState(() {
      _guardandoDireccion = true;
      _error = null;
      _mensajeExito = null;
    });

    try {
      await _clientesService.actualizarMiPerfil(
        direccion: _direccionController.text.trim().isEmpty
            ? null
            : _direccionController.text.trim(),
      );
      setState(() => _mensajeExito = 'Tu dirección se guardó correctamente.');
    } on ApiException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(
        () => _error = 'Ocurrió un error inesperado. Intenta nuevamente.',
      );
    } finally {
      if (mounted) setState(() => _guardandoDireccion = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cliente = _cliente;

    return Scaffold(
      appBar: AppBar(title: const Text('Mi perfil')),
      bottomNavigationBar: widget.mostrarAnuncio ? const AdBanner() : null,
      body: SafeArea(
        bottom: !widget.mostrarAnuncio,
        child: _cargando
            ? const Center(child: AppLoadingIndicator())
            : cliente == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _error ?? 'No se pudo cargar tu perfil.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              )
            : RefreshIndicator(
                onRefresh: _cargar,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(20),
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
                              Icons.person_rounded,
                              color: scheme.primary,
                              size: 32,
                            ),
                          )
                          .animate()
                          .fadeIn(duration: 300.ms)
                          .scale(
                            begin: const Offset(0.85, 0.85),
                            end: const Offset(1, 1),
                          ),
                      const SizedBox(height: 16),
                      Text(
                        cliente.nombreParaMostrar,
                        style: theme.textTheme.titleLarge,
                      ).animate().fadeIn(delay: 80.ms, duration: 250.ms),
                      const SizedBox(height: 4),
                      Text(
                        cliente.dni != null
                            ? '${cliente.dni!.length == 11 ? 'RUC' : 'DNI'} ${cliente.dni}'
                            : 'Sin documento registrado',
                        style: theme.textTheme.bodyMedium,
                      ).animate().fadeIn(delay: 120.ms, duration: 250.ms),
                      const SizedBox(height: 24),
                      Text(
                        'Contacto verificado',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Verificar tu celular o correo protege tu cuenta: cambiarlos o cambiar tu contraseña más adelante exigirá un código enviado a uno de estos canales.',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      _FilaCanal(
                        icono: Icons.phone_outlined,
                        etiqueta: 'Teléfono',
                        valor: cliente.telefono,
                        verificado: cliente.telefonoVerificado,
                        onTap: _gestionarCelular,
                      ),
                      const SizedBox(height: 10),
                      _FilaCanal(
                        icono: Icons.email_outlined,
                        etiqueta: 'Correo',
                        valor: cliente.email,
                        verificado: cliente.emailVerificado,
                        onTap: _gestionarCorreo,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Dirección de Entrega',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _direccionController,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: const [UpperCaseTextFormatter()],
                        decoration: InputDecoration(
                          hintText: 'Dirección de entrega',
                          prefixIcon: const Icon(Icons.place_outlined),
                          suffixIcon:
                              IconButton(
                                    tooltip: 'Usar mi ubicación GPS',
                                    onPressed: _obteniendoUbicacion
                                        ? null
                                        : _autocompletarConGps,
                                    icon: _obteniendoUbicacion
                                        ? SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: scheme.primary,
                                            ),
                                          )
                                        : Icon(
                                            Icons.my_location_rounded,
                                            color: scheme.primary,
                                          ),
                                  )
                                  .animate(
                                    onPlay: (c) => c.repeat(reverse: true),
                                  )
                                  .scale(
                                    begin: const Offset(1, 1),
                                    end: const Offset(1.12, 1.12),
                                    duration: 900.ms,
                                    curve: Curves.easeInOut,
                                  ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: _guardandoDireccion
                            ? null
                            : _guardarDireccion,
                        child: _guardandoDireccion
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: scheme.primary,
                                ),
                              )
                            : const Text('Guardar dirección'),
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
                      const SizedBox(height: 28),
                      const Divider(),
                      const SizedBox(height: 8),
                      Text('Seguridad', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _abrirCambioPassword,
                        icon: const Icon(Icons.lock_outline_rounded),
                        label: const Text('Cambiar contraseña'),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _FilaCanal extends StatelessWidget {
  const _FilaCanal({
    required this.icono,
    required this.etiqueta,
    required this.valor,
    required this.verificado,
    required this.onTap,
  });

  final IconData icono;
  final String etiqueta;
  final String? valor;
  final bool verificado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tieneValor = valor != null && valor!.trim().isNotEmpty;
    final colorBadge = verificado
        ? const Color(0xFF2E7D32)
        : (tieneValor ? const Color(0xFFEA8C1B) : AppColors.textSecondary);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icono, color: AppColors.textSecondary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(etiqueta, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 2),
                Text(
                  tieneValor ? valor! : 'No registrado',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colorBadge.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        verificado
                            ? Icons.verified_rounded
                            : (tieneValor
                                  ? Icons.error_outline_rounded
                                  : Icons.help_outline_rounded),
                        size: 12,
                        color: colorBadge,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        verificado
                            ? 'Verificado'
                            : (tieneValor ? 'Sin verificar' : 'No registrado'),
                        style: TextStyle(
                          color: colorBadge,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: onTap,
            child: Text(tieneValor && verificado ? 'Cambiar' : 'Verificar'),
          ),
        ],
      ),
    );
  }
}
