import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import '../../services/api_client.dart';
import '../../services/notificaciones_service.dart';
import '../../services/pedidos_service.dart';
import '../../utils/fecha_pedido_utils.dart';
import '../../utils/text_formatters.dart';
import '../../widgets/ad_banner.dart';
import '../../widgets/estado_error.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/premium_button.dart';

/// Nombres EXACTOS de `Productos.Nombre` en la base de datos — mismo
/// criterio que `NOMBRES_DISPONIBLES` en la página web (`data/config.ts`):
/// solo los panes que ya están listos para venderse sin que alguien los
/// revise antes. El resto del catálogo de Panadería (yema, maíz, integral,
/// manteca, petipanes) existe en la base pero todavía no se ofrece acá.
const _nombresDisponibles = {
  'Pan de Hamburguesa Clásico',
  'Pan de Agua',
  'Pan Francés',
};

/// Pedido mínimo para pan vendido por unidad (Pan de Agua/Francés) — el pan
/// de hamburguesa no aplica, se vende por paquete de 12 a precio fijo.
const _cantidadMinimaUnidad = 50;

/// Autoservicio (rol CLIENTE): el propio cliente registra su pedido, sin
/// negociar precio (siempre sale del catálogo) y sin elegir a "qué cliente"
/// es — siempre es él mismo. Mismo catálogo que ve un visitante sin cuenta
/// en la página web (pan de hamburguesa por paquete de 12, pan de agua y
/// pan francés por unidad, con 50 unidades como pedido mínimo) — el resto
/// del catálogo todavía no está listo para pedirse sin que alguien lo
/// revise antes. Al confirmar, el pedido queda "por confirmar" y el
/// personal de LA TIENDA CORRESPONDIENTE (Hamburguesas o Panadería, según
/// el producto elegido) recibe una notificación push real para aceptarlo o
/// rechazarlo según stock.
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
  final _pedidosService = PedidosService();

  bool _cargandoCatalogo = true;
  String? _errorCarga;
  List<ProductoAutoservicio> _productos = [];
  ProductoAutoservicio? _productoSeleccionado;

  DateTime? _fechaEntrega = DateTime.now();
  TimeOfDay? _horaEntrega;

  bool _enviando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarCatalogo();
    _cantidadController.text = '1';
  }

  @override
  void dispose() {
    _cantidadController.dispose();
    _notasController.dispose();
    super.dispose();
  }

  Future<void> _cargarCatalogo() async {
    setState(() {
      _cargandoCatalogo = true;
      _errorCarga = null;
    });
    try {
      final productos = (await _pedidosService.catalogoAutoservicio())
          .where((p) => _nombresDisponibles.contains(p.nombre))
          .toList();
      setState(() {
        _productos = productos;
        _productoSeleccionado = productos.isNotEmpty ? productos.first : null;
      });
      _aplicarCantidadPorDefecto();
    } on ApiException catch (e) {
      setState(() => _errorCarga = e.mensaje);
    } catch (_) {
      setState(() => _errorCarga = 'No se pudo cargar el catálogo.');
    } finally {
      if (mounted) setState(() => _cargandoCatalogo = false);
    }
  }

  int get _cantidad => int.tryParse(_cantidadController.text) ?? 0;

  bool get _esPaquete => _productoSeleccionado?.esPaquete ?? false;

  double get _total =>
      (_productoSeleccionado?.precioUnitario ?? 0) * _cantidad;

  /// Paquete de hamburguesa arranca en 1 (precio fijo por paquete, sin
  /// mínimo); pan de agua/francés arranca directo en el mínimo de venta
  /// (50) para que el cliente no tenga que adivinarlo ni tropezar con el
  /// error de "cantidad insuficiente" apenas abre el formulario.
  void _aplicarCantidadPorDefecto() {
    _cantidadController.text = _esPaquete ? '1' : '$_cantidadMinimaUnidad';
  }

  void _cambiarProducto(ProductoAutoservicio? producto) {
    setState(() => _productoSeleccionado = producto);
    _aplicarCantidadPorDefecto();
  }

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
    final producto = _productoSeleccionado;
    if (producto == null) {
      setState(() => _error = 'Selecciona un producto.');
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
        idProducto: producto.idProducto,
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
        title: Text('Pedido #${resultado.numeroPedidoDia} por confirmar'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${resultado.tienda ?? "La tienda"} ya lo recibió y lo confirmará según su stock disponible.',
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
        child: _cargandoCatalogo
            ? const Center(child: AppLoadingIndicator())
            : _errorCarga != null
            ? EstadoError(mensaje: _errorCarga!, onReintentar: _cargarCatalogo)
            : _productos.isEmpty
            ? const EstadoVacio(
                icono: Icons.storefront_outlined,
                titulo: 'Todavía no hay pedidos disponibles para hacer.',
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<ProductoAutoservicio>(
                        initialValue: _productoSeleccionado,
                        items: _productos
                            .map(
                              (p) => DropdownMenuItem(
                                value: p,
                                child: Text(
                                  p.nombre,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _cambiarProducto,
                        decoration: const InputDecoration(
                          labelText: 'Producto',
                          prefixIcon: Icon(Icons.inventory_2_rounded),
                        ),
                      ),
                      if (_productoSeleccionado != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _esPaquete
                              ? 'Cada paquete trae 12 panes de hamburguesa y cuesta S/ ${_productoSeleccionado!.precioUnitario.toStringAsFixed(2)}, sin importar cuántos paquetes pidas.'
                              : 'Pedido mínimo: $_cantidadMinimaUnidad panes.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _cantidadController,
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(
                          labelText: _esPaquete
                              ? 'Cantidad de paquetes (12 unidades cada uno)'
                              : 'Cantidad',
                          prefixIcon: const Icon(Icons.numbers_rounded),
                          counterText: '',
                        ),
                        onChanged: (_) => setState(() {}),
                        validator: (v) {
                          final n = int.tryParse(v ?? '');
                          if (n == null || n <= 0) {
                            return 'Ingresa una cantidad válida';
                          }
                          if (!_esPaquete && n < _cantidadMinimaUnidad) {
                            return 'El pedido mínimo es de $_cantidadMinimaUnidad panes';
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
                      if (_productoSeleccionado != null && _cantidad > 0) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _esPaquete
                                        ? 'Precio del paquete'
                                        : 'Precio por unidad',
                                  ),
                                  Text(
                                    'S/ ${_productoSeleccionado!.precioUnitario.toStringAsFixed(2)}',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Total',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    'S/ ${_total.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
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
                      PremiumButton(
                        label: 'Registrar pedido',
                        icono: Icons.add_shopping_cart_rounded,
                        cargando: _enviando,
                        onPressed: _registrarPedido,
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: 250.ms),
              ),
      ),
    );
  }
}
