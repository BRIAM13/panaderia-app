import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../models/medio_pago_model.dart';
import '../../models/tienda_model.dart';
import '../../services/api_client.dart';
import '../../services/medios_pago_service.dart';
import '../../services/tiendas_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/text_formatters.dart';
import '../../widgets/loading_indicator.dart';

const _tiposMedioPago = ['YAPE', 'PLIN', 'TRANSFERENCIA', 'OTRO'];

/// Gestión de métodos de pago (ADMIN/SUPERADMIN de la tienda): Yape, Plin,
/// transferencia bancaria u otro — estos son los que el cliente ve al
/// pagar una deuda. Se puede tener más de una tienda asignada, por eso
/// esta pantalla primero elige la tienda (si hay más de una) y luego lista
/// sus medios de pago (activos e inactivos, se pueden reactivar).
class MediosPagoPage extends StatefulWidget {
  const MediosPagoPage({super.key});

  @override
  State<MediosPagoPage> createState() => _MediosPagoPageState();
}

class _MediosPagoPageState extends State<MediosPagoPage> {
  final _tiendasService = TiendasService();
  final _mediosPagoService = MediosPagoService();

  bool _cargando = true;
  String? _error;
  List<Tienda> _tiendas = [];
  Tienda? _tiendaSeleccionada;
  List<MedioPago> _medios = [];

  @override
  void initState() {
    super.initState();
    _cargarTiendas();
  }

  Future<void> _cargarTiendas() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final tiendas = await _tiendasService.misTiendas();
      setState(() {
        _tiendas = tiendas;
        _tiendaSeleccionada = tiendas.isNotEmpty ? tiendas.first : null;
      });
      if (_tiendaSeleccionada != null) await _cargarMedios();
    } on ApiException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(() => _error = 'No se pudieron cargar tus tiendas.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _cargarMedios() async {
    if (_tiendaSeleccionada == null) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final medios = await _mediosPagoService.listarPorTienda(
        _tiendaSeleccionada!.idTienda,
      );
      setState(() => _medios = medios);
    } on ApiException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(() => _error = 'No se pudieron cargar los métodos de pago.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _cambiarEstado(MedioPago medio, bool activo) async {
    try {
      await _mediosPagoService.cambiarEstado(medio.idMedioPago, activo: activo);
      _cargarMedios();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.mensaje)));
    }
  }

  Future<void> _abrirFormulario({MedioPago? medioExistente}) async {
    if (_tiendaSeleccionada == null) return;
    final guardado = await showDialog<bool>(
      context: context,
      builder: (context) => _FormularioMedioPago(
        service: _mediosPagoService,
        idTienda: _tiendaSeleccionada!.idTienda,
        medioExistente: medioExistente,
      ),
    );
    if (guardado == true) _cargarMedios();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Métodos de pago')),
      floatingActionButton: _tiendaSeleccionada == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _abrirFormulario(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Agregar método'),
            ),
      body: SafeArea(child: _construirCuerpo()),
    );
  }

  Widget _construirCuerpo() {
    final theme = Theme.of(context);

    if (_cargando && _tiendas.isEmpty) {
      return const Center(child: AppLoadingIndicator());
    }
    if (_error != null && _tiendas.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _cargarTiendas,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }
    if (_tiendas.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No tienes tiendas asignadas.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargarMedios,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
        children: [
          if (_tiendas.length > 1) ...[
            DropdownButtonFormField<Tienda>(
              initialValue: _tiendaSeleccionada,
              items: _tiendas
                  .map((t) => DropdownMenuItem(value: t, child: Text(t.nombre)))
                  .toList(),
              onChanged: (t) {
                setState(() => _tiendaSeleccionada = t);
                _cargarMedios();
              },
              decoration: const InputDecoration(
                labelText: 'Tienda',
                prefixIcon: Icon(Icons.storefront_rounded),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_cargando)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: AppLoadingIndicator()),
            )
          else if (_medios.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: [
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 48,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Aún no configuraste ningún método de pago',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            ..._medios.asMap().entries.map(
              (entry) =>
                  _TarjetaMedioPago(
                        medio: entry.value,
                        onEditar: () =>
                            _abrirFormulario(medioExistente: entry.value),
                        onCambiarEstado: (activo) =>
                            _cambiarEstado(entry.value, activo),
                      )
                      .animate(delay: (60 * entry.key).ms)
                      .fadeIn(duration: 300.ms)
                      .moveY(begin: 10, end: 0),
            ),
        ],
      ),
    );
  }
}

class _TarjetaMedioPago extends StatelessWidget {
  const _TarjetaMedioPago({
    required this.medio,
    required this.onEditar,
    required this.onCambiarEstado,
  });

  final MedioPago medio;
  final VoidCallback onEditar;
  final ValueChanged<bool> onCambiarEstado;

  IconData get _icono {
    switch (medio.tipo) {
      case 'YAPE':
      case 'PLIN':
        return Icons.phone_android_rounded;
      case 'TRANSFERENCIA':
        return Icons.account_balance_rounded;
      default:
        return Icons.payments_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_icono, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(medio.etiquetaTipo, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    '${medio.titular} · ${medio.numeroDestino}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (medio.nombreBanco != null)
                    Text(
                      medio.nombreBanco!,
                      style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                    ),
                ],
              ),
            ),
            IconButton(
              onPressed: onEditar,
              icon: const Icon(Icons.edit_rounded, size: 20),
            ),
            Switch(value: medio.estado, onChanged: onCambiarEstado),
          ],
        ),
      ),
    );
  }
}

class _FormularioMedioPago extends StatefulWidget {
  const _FormularioMedioPago({
    required this.service,
    required this.idTienda,
    this.medioExistente,
  });

  final MediosPagoService service;
  final int idTienda;
  final MedioPago? medioExistente;

  @override
  State<_FormularioMedioPago> createState() => _FormularioMedioPagoState();
}

class _FormularioMedioPagoState extends State<_FormularioMedioPago> {
  final _formKey = GlobalKey<FormState>();
  late String _tipo;
  final _titularController = TextEditingController();
  final _numeroController = TextEditingController();
  final _cciController = TextEditingController();
  final _bancoController = TextEditingController();
  final _notasController = TextEditingController();

  bool _guardando = false;
  String? _error;

  bool get _esEdicion => widget.medioExistente != null;

  @override
  void initState() {
    super.initState();
    final medio = widget.medioExistente;
    _tipo = medio?.tipo ?? 'YAPE';
    _titularController.text = medio?.titular ?? '';
    _numeroController.text = medio?.numeroDestino ?? '';
    _cciController.text = medio?.cci ?? '';
    _bancoController.text = medio?.nombreBanco ?? '';
    _notasController.text = medio?.notas ?? '';
  }

  @override
  void dispose() {
    _titularController.dispose();
    _numeroController.dispose();
    _cciController.dispose();
    _bancoController.dispose();
    _notasController.dispose();
    super.dispose();
  }

  String get _labelNumero {
    switch (_tipo) {
      case 'YAPE':
        return 'Número de Yape';
      case 'PLIN':
        return 'Número de Plin';
      case 'TRANSFERENCIA':
        return 'Número de cuenta';
      default:
        return 'Número o referencia';
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _guardando = true;
      _error = null;
    });

    final input = MedioPagoInput(
      tipo: _tipo,
      titular: _titularController.text.trim(),
      numeroDestino: _numeroController.text.trim(),
      cci: _tipo == 'TRANSFERENCIA' ? _cciController.text.trim() : null,
      nombreBanco:
          _tipo == 'TRANSFERENCIA' && _bancoController.text.trim().isNotEmpty
          ? _bancoController.text.trim()
          : null,
      notas: _notasController.text.trim().isEmpty
          ? null
          : _notasController.text.trim(),
    );

    try {
      if (_esEdicion) {
        await widget.service.actualizar(
          widget.medioExistente!.idMedioPago,
          input,
        );
      } else {
        await widget.service.crear(widget.idTienda, input);
      }
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
    return AlertDialog(
      title: Text(
        _esEdicion ? 'Editar método de pago' : 'Nuevo método de pago',
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_esEdicion) ...[
                DropdownButtonFormField<String>(
                  initialValue: _tipo,
                  items: _tiposMedioPago
                      .map(
                        (t) => DropdownMenuItem(
                          value: t,
                          child: Text(_etiquetaTipo(t)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _tipo = v!),
                  decoration: const InputDecoration(labelText: 'Tipo'),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _titularController,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: const [UpperCaseTextFormatter()],
                decoration: const InputDecoration(labelText: 'Titular'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _numeroController,
                decoration: InputDecoration(labelText: _labelNumero),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              if (_tipo == 'TRANSFERENCIA') ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _cciController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'CCI (20 dígitos)',
                  ),
                  validator: (v) =>
                      (v == null || !RegExp(r'^\d{20}$').hasMatch(v.trim()))
                      ? 'Debe tener 20 dígitos'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _bancoController,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: const [UpperCaseTextFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Banco (opcional)',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _notasController,
                decoration: const InputDecoration(
                  labelText: 'Notas para el cliente (opcional)',
                ),
                maxLines: 2,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: _guardando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }

  String _etiquetaTipo(String tipo) {
    switch (tipo) {
      case 'YAPE':
        return 'Yape';
      case 'PLIN':
        return 'Plin';
      case 'TRANSFERENCIA':
        return 'Transferencia bancaria';
      default:
        return 'Otro';
    }
  }
}
