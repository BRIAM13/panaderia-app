import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import '../../models/tienda_model.dart';
import '../../services/api_client.dart';
import '../../services/notificaciones_service.dart';
import '../../services/pedidos_service.dart';
import '../../services/tiendas_service.dart';
import '../../utils/fecha_pedido_utils.dart';
import '../../utils/text_formatters.dart';
import '../../widgets/ad_banner.dart';
import '../../widgets/loading_indicator.dart';

/// Autoservicio (rol CLIENTE): el propio cliente registra su pedido, sin
/// negociar precio (siempre sale del catálogo) y sin elegir a "qué
/// cliente" es — siempre es él mismo. Por ahora solo paquetes de pan de
/// hamburguesa: es el único producto con precio fijo y confiable — el
/// resto del catálogo todavía no está listo para pedirse sin que alguien
/// lo revise antes. Al confirmar, el pedido queda "por confirmar" y el
/// personal de la tienda recibe una notificación push real para aceptarlo
/// o rechazarlo según stock.
class HacerPedidoPage extends StatefulWidget {
  const HacerPedidoPage({super.key, this.mostrarAnuncio = false});

  /// Solo debe encender esto quien la abre sabiendo que el usuario es
  /// cliente puro (no híbrido) — el anuncio existe para monetizar a
  /// quienes solo compran, no a quienes también trabajan ahí.
  final bool mostrarAnuncio;

  @override
  State<HacerPedidoPage> createState() => _HacerPedidoPageState();
}

class _HacerPedidoPageState extends State<HacerPedidoPage> {
  final _formKey = GlobalKey<FormState>();
  final _cantidadController = TextEditingController();
  final _notasController = TextEditingController();
  final _tiendasService = TiendasService();
  final _pedidosService = PedidosService();

  bool _cargandoTiendas = true;
  String? _errorCarga;
  Tienda? _tiendaHamburguesas;

  DateTime? _fechaEntrega = DateTime.now();
  TimeOfDay? _horaEntrega;

  bool _enviando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarTienda();
    _cantidadController.text = '1';
  }

  @override
  void dispose() {
    _cantidadController.dispose();
    _notasController.dispose();
    super.dispose();
  }

  Future<void> _cargarTienda() async {
    setState(() {
      _cargandoTiendas = true;
      _errorCarga = null;
    });
    try {
      final tiendas = await _tiendasService.listar();
      Tienda? hamburguesas;
      for (final t in tiendas) {
        if (t.slug == 'hamburguesas' && t.disponible) hamburguesas = t;
      }
      setState(() => _tiendaHamburguesas = hamburguesas);
    } on ApiException catch (e) {
      setState(() => _errorCarga = e.mensaje);
    } catch (_) {
      setState(() => _errorCarga = 'No se pudo cargar la tienda.');
    } finally {
      if (mounted) setState(() => _cargandoTiendas = false);
    }
  }

  int get _cantidad => int.tryParse(_cantidadController.text) ?? 0;

  /// Con fecha (siempre trae hoy por defecto) ya cuenta como "programado",
  /// aunque no se elija una hora específica — igual que en el formulario
  /// de personal (ver nuevo_pedido_page.dart).
  DateTime? get _fechaHoraEntrega {
    if (_fechaEntrega == null) return null;
    return DateTime(
      _fechaEntrega!.year,
      _fechaEntrega!.month,
      _fechaEntrega!.day,
      _horaEntrega?.hour ?? 0,
      _horaEntrega?.minute ?? 0,
    );
  }

  Future<void> _elegirFecha() async {
    final hoy = DateTime.now();
    final soloHoy = DateTime(hoy.year, hoy.month, hoy.day);
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fechaEntrega != null
          ? DateTime(
              _fechaEntrega!.year,
              _fechaEntrega!.month,
              _fechaEntrega!.day,
            )
          : soloHoy,
      firstDate: soloHoy,
      lastDate: soloHoy.add(const Duration(days: 90)),
    );
    if (fecha != null) setState(() => _fechaEntrega = fecha);
  }

  Future<void> _elegirHora() async {
    final hora = await showTimePicker(
      context: context,
      initialTime: _horaEntrega ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (hora != null) setState(() => _horaEntrega = hora);
  }

  Future<void> _registrarPedido() async {
    if (!_formKey.currentState!.validate()) return;
    if (_tiendaHamburguesas == null) {
      setState(() => _error = 'La tienda no está disponible en este momento.');
      return;
    }

    final fechaHora = _fechaHoraEntrega;
    if (_horaEntrega != null &&
        fechaHora != null &&
        fechaHora.isBefore(DateTime.now())) {
      setState(
        () =>
            _error = 'La fecha y hora de entrega no puede estar en el pasado.',
      );
      return;
    }

    setState(() {
      _enviando = true;
      _error = null;
    });

    try {
      final resultado = await _pedidosService.crearComoCliente(
        idTienda: _tiendaHamburguesas!.idTienda,
        tipoPedido: 'PAQUETES',
        cantidad: _cantidad,
        fechaEntrega: fechaHora,
        notas: _notasController.text.trim().isEmpty
            ? null
            : _notasController.text.trim(),
      );

      NotificacionesService.avisarCambioPedido();
      if (!mounted) return;
      await _mostrarResumenPedido(resultado);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(
        () => _error = 'Ocurrió un error inesperado. Intenta nuevamente.',
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _mostrarResumenPedido(PedidoResultado resultado) {
    final formatoFechaHoraCreacion = DateFormat('d/MM/yyyy h:mm a', 'es');

    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(
          Icons.hourglass_top_rounded,
          color: Color(0xFFEA8C1B),
          size: 36,
        ),
        title: Text('Pedido #${resultado.idPedido} por confirmar'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_tiendaHamburguesas!.nombre} ya lo recibió y lo confirmará según su stock disponible.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.event_available_rounded, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    resultado.fechaEntrega != null
                        ? formatearFechaEntrega(
                            resultado.fechaEntrega!,
                            formatoLargo: true,
                          )
                        : 'Sin fecha de entrega programada',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.history_rounded, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Registrado el ${formatoFechaHoraCreacion.format(resultado.fechaCreacion)}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total'),
                  Text(
                    'S/ ${resultado.total.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Listo'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Hacer un pedido')),
      bottomNavigationBar: widget.mostrarAnuncio ? const AdBanner() : null,
      body: SafeArea(
        bottom: !widget.mostrarAnuncio,
        child: _cargandoTiendas
            ? const Center(child: AppLoadingIndicator())
            : _errorCarga != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_errorCarga!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _cargarTienda,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              )
            : _tiendaHamburguesas == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Todavía no hay pedidos disponibles para hacer.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.inventory_2_rounded,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Paquete de 12 panes de hamburguesa — ${_tiendaHamburguesas!.nombre}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Por ahora solo puedes pedir paquetes de pan de hamburguesa — es el único precio fijo. Cuando el resto del catálogo esté listo, se habilitará aquí.',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _cantidadController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Cantidad de paquetes',
                          prefixIcon: Icon(Icons.numbers_rounded),
                        ),
                        validator: (v) {
                          final n = int.tryParse(v ?? '');
                          if (n == null || n <= 0) {
                            return 'Ingresa una cantidad válida';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _elegirFecha,
                              icon: const Icon(
                                Icons.calendar_today_rounded,
                                size: 18,
                              ),
                              label: Text(
                                _fechaEntrega == null
                                    ? 'Fecha de entrega'
                                    : DateFormat(
                                        'dd/MM/yyyy',
                                      ).format(_fechaEntrega!),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _elegirHora,
                              icon: const Icon(
                                Icons.access_time_rounded,
                                size: 18,
                              ),
                              label: Text(
                                _horaEntrega == null
                                    ? 'Hora de entrega'
                                    : _horaEntrega!.format(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _notasController,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: const [UpperCaseTextFormatter()],
                        decoration: const InputDecoration(
                          labelText: 'Notas (opcional)',
                        ),
                        maxLines: 2,
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
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _enviando ? null : _registrarPedido,
                        child: _enviando
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Registrar pedido'),
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: 250.ms),
              ),
      ),
    );
  }
}
