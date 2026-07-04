import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../models/rol_model.dart';
import '../../models/tienda_model.dart';
import '../../models/trabajador_model.dart';
import '../../services/api_client.dart';
import '../../services/external_lookup_service.dart';
import '../../services/roles_service.dart';
import '../../services/tiendas_service.dart';
import '../../services/trabajadores_service.dart';
import '../../utils/text_formatters.dart';

/// Alta de un trabajador con el mismo "Estándar Briam" que Clientes: el DNI
/// es el único campo visible al inicio, la búsqueda es 100% automática (no
/// hace falta tocar "Buscar" — se dispara sola al completar los 8 dígitos)
/// y los datos verificados (de nuestra propia BD o de RENIEC) quedan
/// bloqueados. Si el DNI ya pertenece a un cliente y/o a un trabajador de
/// otra tienda, esa persona NUNCA se duplica: solo se le agrega el acceso a
/// las tiendas que este administrador elija.
class TrabajadorFormPage extends StatefulWidget {
  const TrabajadorFormPage({super.key});

  @override
  State<TrabajadorFormPage> createState() => _TrabajadorFormPageState();
}

class _TrabajadorFormPageState extends State<TrabajadorFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _dniController = TextEditingController();
  final _nombresController = TextEditingController();
  final _apellidoPaternoController = TextEditingController();
  final _apellidoMaternoController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _emailController = TextEditingController();
  final _direccionController = TextEditingController();
  final _salarioController = TextEditingController();

  final _trabajadoresService = TrabajadoresService();
  final _externalLookup = ExternalLookupService();
  final _tiendasService = TiendasService();
  final _rolesService = RolesService();

  bool _cargandoTiendas = true;
  List<Tienda> _misTiendas = [];
  final Set<int> _tiendasSeleccionadas = {};
  final Set<int> _tiendasYaAsignadas = {};

  bool _cargandoRoles = true;
  List<RolAsignable> _rolesAsignables = [];
  String? _rolSeleccionado;

  Timer? _debounce;
  bool _buscando = false;
  bool _camposExpandidos = false;
  bool _soloLectura = false;
  String _origenValidacion = 'MANUAL';
  bool _esCliente = false;
  bool _yaEsTrabajador = false;
  List<TrabajadorTiendaAsignada> _tiendasAsignadasOtras = [];
  String? _ultimoDniConsultado;

  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _dniController.addListener(_onDniCambiado);
    // El botón "Registrar" reacciona en vivo a estos campos (los únicos
    // editables a mano cuando el DNI no vino bloqueado por RENIEC/BD).
    _nombresController.addListener(_onCampoObligatorioCambiado);
    _apellidoPaternoController.addListener(_onCampoObligatorioCambiado);
    _cargarMisTiendas();
    _cargarRolesAsignables();
  }

  void _onCampoObligatorioCambiado() => setState(() {});

  @override
  void dispose() {
    _debounce?.cancel();
    _dniController.removeListener(_onDniCambiado);
    _nombresController.removeListener(_onCampoObligatorioCambiado);
    _apellidoPaternoController.removeListener(_onCampoObligatorioCambiado);
    _dniController.dispose();
    _nombresController.dispose();
    _apellidoPaternoController.dispose();
    _apellidoMaternoController.dispose();
    _telefonoController.dispose();
    _emailController.dispose();
    _direccionController.dispose();
    _salarioController.dispose();
    super.dispose();
  }

  Future<void> _cargarMisTiendas() async {
    setState(() => _cargandoTiendas = true);
    try {
      final tiendas = await _tiendasService.misTiendas();
      setState(() => _misTiendas = tiendas);
    } catch (_) {
      setState(() => _error = 'No se pudieron cargar tus tiendas.');
    } finally {
      if (mounted) setState(() => _cargandoTiendas = false);
    }
  }

  /// Los roles nunca se hardcodean en la app: siempre se leen de la tabla
  /// Roles a través del backend, ya filtrados según lo que el usuario
  /// autenticado puede asignar (ADMIN solo ve Trabajador, SUPERADMIN ve
  /// los 3).
  Future<void> _cargarRolesAsignables() async {
    setState(() => _cargandoRoles = true);
    try {
      final roles = await _rolesService.asignables();
      setState(() {
        _rolesAsignables = roles;
        if (roles.length == 1) _rolSeleccionado = roles.first.nombreRol;
      });
    } catch (_) {
      setState(() => _error = 'No se pudieron cargar los roles disponibles.');
    } finally {
      if (mounted) setState(() => _cargandoRoles = false);
    }
  }

  void _onDniCambiado() {
    _debounce?.cancel();
    final texto = _dniController.text.trim();

    if (texto != _ultimoDniConsultado) {
      setState(() {
        _camposExpandidos = false;
        _soloLectura = false;
        _origenValidacion = 'MANUAL';
        _esCliente = false;
        _yaEsTrabajador = false;
        _tiendasAsignadasOtras = [];
        _tiendasYaAsignadas.clear();
        _nombresController.clear();
        _apellidoPaternoController.clear();
        _apellidoMaternoController.clear();
        _telefonoController.clear();
        _emailController.clear();
        _direccionController.clear();
      });
    }

    if (texto.length != 8) return;

    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _buscarAutomaticamente(texto),
    );
  }

  /// 100% automático: primero nuestra propia BD (cliente y/o trabajador de
  /// otra tienda), y si no aparece ahí, recién RENIEC — nunca hace falta
  /// tocar el botón "Buscar" para que esto se dispare.
  Future<void> _buscarAutomaticamente(String dni) async {
    setState(() {
      _buscando = true;
      _error = null;
    });

    try {
      final resultado = await _trabajadoresService.buscarPorDni(dni);
      if (!mounted || dni != _dniController.text.trim()) return;

      if (resultado.existeEnBd) {
        setState(() {
          _nombresController.text = (resultado.nombres ?? '').toUpperCase();
          _apellidoPaternoController.text = (resultado.apellidoPaterno ?? '')
              .toUpperCase();
          _apellidoMaternoController.text = (resultado.apellidoMaterno ?? '')
              .toUpperCase();
          _telefonoController.text = resultado.telefono ?? '';
          _emailController.text = resultado.email ?? '';
          _direccionController.text = (resultado.direccion ?? '').toUpperCase();
          _origenValidacion = resultado.origenValidacion ?? 'MANUAL';
          _soloLectura = _origenValidacion == 'RENIEC';
          _esCliente = resultado.esCliente;
          _yaEsTrabajador = resultado.yaEsTrabajador;
          _tiendasAsignadasOtras = resultado.tiendasAsignadas;
          _tiendasYaAsignadas
            ..clear()
            ..addAll(
              resultado.tiendasAsignadas
                  .where((t) => t.activo)
                  .map((t) => t.idTienda),
            );
          _tiendasSeleccionadas
            ..clear()
            ..addAll(_tiendasYaAsignadas);
          _camposExpandidos = true;
          _ultimoDniConsultado = dni;
        });
        return;
      }

      // No está en nuestra BD: recién ahí se consulta RENIEC.
      final reniec = await _externalLookup.buscarPorDni(dni);
      if (!mounted || dni != _dniController.text.trim()) return;
      setState(() {
        _nombresController.text = reniec.nombres.toUpperCase();
        _apellidoPaternoController.text = reniec.apellidoPaterno.toUpperCase();
        _apellidoMaternoController.text = reniec.apellidoMaterno.toUpperCase();
        _origenValidacion = 'RENIEC';
        _soloLectura = true;
        _camposExpandidos = true;
        _ultimoDniConsultado = dni;
      });
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        // Ni en nuestra BD ni en RENIEC: se revela todo vacío para
        // completar a mano.
        if (!mounted || dni != _dniController.text.trim()) return;
        setState(() {
          _origenValidacion = 'MANUAL';
          _soloLectura = false;
          _camposExpandidos = true;
          _ultimoDniConsultado = dni;
        });
      } else {
        setState(() => _error = e.mensaje);
      }
    } catch (_) {
      setState(() => _error = 'Ocurrió un error al verificar el DNI.');
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  bool get _puedeGuardar =>
      _camposExpandidos &&
      _nombresController.text.trim().isNotEmpty &&
      _apellidoPaternoController.text.trim().isNotEmpty &&
      _rolSeleccionado != null &&
      _tiendasSeleccionadas.isNotEmpty;

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_tiendasSeleccionadas.isEmpty) {
      setState(() => _error = 'Selecciona al menos una tienda.');
      return;
    }

    setState(() {
      _guardando = true;
      _error = null;
    });

    final input = TrabajadorInput(
      dni: _dniController.text.trim(),
      nombres: _nombresController.text.trim(),
      apellidoPaterno: _apellidoPaternoController.text.trim(),
      apellidoMaterno: _apellidoMaternoController.text.trim().isEmpty
          ? null
          : _apellidoMaternoController.text.trim(),
      telefono: _telefonoController.text.trim().isEmpty
          ? null
          : _telefonoController.text.trim(),
      email: _emailController.text.trim().isEmpty
          ? null
          : _emailController.text.trim(),
      direccion: _direccionController.text.trim().isEmpty
          ? null
          : _direccionController.text.trim(),
      rol: _rolSeleccionado!,
      salario: _salarioController.text.trim().isEmpty
          ? null
          : double.tryParse(
              _salarioController.text.trim().replaceAll(',', '.'),
            ),
      origenValidacion: _origenValidacion,
      tiendas: _tiendasSeleccionadas.toList(),
    );

    try {
      await _trabajadoresService.crear(input);
      if (!mounted) return;
      Navigator.of(context).pop(true);
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
      appBar: AppBar(title: const Text('Nuevo trabajador')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Ingresa el DNI del trabajador — el resto se completa solo.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _dniController,
                        enabled: !_buscando,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        maxLength: 8,
                        decoration: const InputDecoration(
                          labelText: 'DNI',
                          counterText: '',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: FilledButton.icon(
                        // Siempre inactivo a propósito: la búsqueda es
                        // automática, este botón solo muestra el estado.
                        onPressed: null,
                        icon: _buscando
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.search_rounded, size: 18),
                        label: const Text('Buscar'),
                      ),
                    ),
                  ],
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
                if (_esCliente) ...[
                  const SizedBox(height: 10),
                  _AvisoInfo(
                    icono: Icons.badge_outlined,
                    texto:
                        'Esta persona ya es cliente registrado — seguirá siéndolo, solo se le agrega el acceso como trabajador.',
                    color: scheme.primary,
                  ),
                ],
                if (_yaEsTrabajador && _tiendasAsignadasOtras.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _AvisoInfo(
                    icono: Icons.storefront_outlined,
                    texto:
                        'Ya es trabajador en: ${_tiendasAsignadasOtras.map((t) => t.activo ? t.nombre : '${t.nombre} (inactivo)').join(', ')}.',
                    color: const Color(0xFFEA8C1B),
                  ),
                ],
                if (_origenValidacion == 'RENIEC' && _camposExpandidos) ...[
                  const SizedBox(height: 10),
                  Chip(
                    avatar: const Icon(
                      Icons.verified_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                    label: const Text('Validado por RENIEC'),
                    backgroundColor: const Color(0xFF2563EB),
                    labelStyle: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  child: !_camposExpandidos
                      ? const SizedBox(width: double.infinity)
                      : Column(
                          key: const ValueKey('campos-expandidos'),
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: _nombresController,
                              readOnly: _soloLectura,
                              textCapitalization: TextCapitalization.characters,
                              inputFormatters: const [UpperCaseTextFormatter()],
                              decoration: const InputDecoration(
                                labelText: 'Nombres',
                                prefixIcon: Icon(Icons.person_outline_rounded),
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Ingresa los nombres'
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _apellidoPaternoController,
                              readOnly: _soloLectura,
                              textCapitalization: TextCapitalization.characters,
                              inputFormatters: const [UpperCaseTextFormatter()],
                              decoration: const InputDecoration(
                                labelText: 'Apellido paterno',
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Ingresa el apellido paterno'
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _apellidoMaternoController,
                              readOnly: _soloLectura,
                              textCapitalization: TextCapitalization.characters,
                              inputFormatters: const [UpperCaseTextFormatter()],
                              decoration: const InputDecoration(
                                labelText: 'Apellido materno',
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _telefonoController,
                              keyboardType: TextInputType.phone,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Teléfono',
                                prefixIcon: Icon(Icons.phone_outlined),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                prefixIcon: Icon(Icons.email_outlined),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _direccionController,
                              textCapitalization: TextCapitalization.characters,
                              inputFormatters: const [UpperCaseTextFormatter()],
                              decoration: const InputDecoration(
                                labelText: 'Dirección',
                                prefixIcon: Icon(Icons.place_outlined),
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (_cargandoRoles)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            else
                              DropdownButtonFormField<String>(
                                initialValue: _rolSeleccionado,
                                items: _rolesAsignables
                                    .map(
                                      (r) => DropdownMenuItem(
                                        value: r.nombreRol,
                                        child: Text(r.etiqueta),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) =>
                                    setState(() => _rolSeleccionado = v),
                                decoration: const InputDecoration(
                                  labelText: 'Rol',
                                  prefixIcon: Icon(Icons.work_outline_rounded),
                                ),
                                validator: (v) =>
                                    v == null ? 'Selecciona un rol' : null,
                              ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _salarioController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Salario (S/, opcional)',
                                prefixIcon: Icon(Icons.payments_outlined),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Acceso a tiendas',
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            if (_cargandoTiendas)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            else if (_misTiendas.isEmpty)
                              Text(
                                'No administras ninguna tienda todavía.',
                                style: theme.textTheme.bodyMedium,
                              )
                            else
                              ..._misTiendas.map((tienda) {
                                final yaAsignado = _tiendasYaAsignadas.contains(
                                  tienda.idTienda,
                                );
                                return CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: _tiendasSeleccionadas.contains(
                                    tienda.idTienda,
                                  ),
                                  title: Text(tienda.nombre),
                                  subtitle: yaAsignado
                                      ? const Text('Ya tiene acceso')
                                      : null,
                                  onChanged: yaAsignado
                                      ? null
                                      : (marcado) => setState(() {
                                          if (marcado == true) {
                                            _tiendasSeleccionadas.add(
                                              tienda.idTienda,
                                            );
                                          } else {
                                            _tiendasSeleccionadas.remove(
                                              tienda.idTienda,
                                            );
                                          }
                                        }),
                                );
                              }),
                          ],
                        ).animate().fadeIn(duration: 250.ms),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: (_guardando || !_puedeGuardar) ? null : _guardar,
                  child: _guardando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Registrar trabajador'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AvisoInfo extends StatelessWidget {
  const _AvisoInfo({
    required this.icono,
    required this.texto,
    required this.color,
  });

  final IconData icono;
  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(texto, style: TextStyle(color: color)),
          ),
        ],
      ),
    );
  }
}
