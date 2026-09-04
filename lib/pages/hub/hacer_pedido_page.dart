import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../services/api_client.dart';
import '../../services/notificaciones_service.dart';
import '../../services/pedidos_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/fecha_pedido_utils.dart';
import '../../utils/text_formatters.dart';
import '../../widgets/ad_banner.dart';
import '../../widgets/carrito_pedido_widget.dart';
import '../../widgets/escritorio.dart';
import '../../widgets/estado_error.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/premium_button.dart';
import '../../widgets/selector_desplegable.dart';

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
///
/// Escritorio (>= Breakpoints.escritorio, vía `esEscritorio`): el patrón de
/// carrito de toda la vida — los campos a la izquierda y el resumen de
/// precio + botón de confirmar fijos a la derecha, siempre visibles. En
/// celular el total vive al final del scroll y hay que bajar para verlo;
/// en una ventana ancha no hay razón para esconderlo. Por debajo de ese
/// umbral el árbol de widgets es idéntico al de siempre.
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

  /// Los productos que el cliente ya agregó a este pedido. Todos deben ser
  /// de la misma tienda — el backend lo rechaza si no, así que acá se avisa
  /// antes de dejar agregar (ver [_agregarAlCarrito]).
  final List<NuevoItemAutoservicio> _carrito = [];

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

  /// Lo que suma el producto que se está eligiendo ahora — todavía no está
  /// en el pedido.
  double get _totalLineaActual =>
      (_productoSeleccionado?.precioUnitario ?? 0) * _cantidad;

  /// Total del pedido: la suma de lo ya agregado al carrito.
  double get _total => _carrito.fold<double>(0, (acc, i) => acc + i.subtotal);

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

  /// Valida el producto elegido y lo agrega al pedido, dejando el
  /// formulario listo para el siguiente. La fecha y las notas son del
  /// pedido completo, así que no se tocan.
  void _agregarAlCarrito() {
    if (!_formKey.currentState!.validate()) return;
    final producto = _productoSeleccionado;
    if (producto == null) {
      setState(() => _error = 'Selecciona un producto.');
      return;
    }

    // Un pedido pertenece a una sola tienda. En este catálogo el pan de
    // hamburguesa (esPaquete) es lo único que viene de Hamburguesas y el
    // resto de Panadería, así que esa bandera alcanza para detectar la
    // mezcla acá y no dejar que el cliente arme un pedido que el backend va
    // a rechazar recién al confirmar.
    if (_carrito.isNotEmpty && _carrito.first.esPaquete != producto.esPaquete) {
      setState(
        () => _error =
            'El pan de hamburguesa y el pan de panadería se piden por separado. '
            'Confirma este pedido y luego haz otro.',
      );
      return;
    }

    setState(() {
      _error = null;
      final indiceExistente = _carrito.indexWhere(
        (i) => i.idProducto == producto.idProducto,
      );
      if (indiceExistente >= 0) {
        // El mismo producto agregado dos veces suma cantidades en vez de
        // repetir la línea: el precio es de catálogo, siempre el mismo.
        final actual = _carrito[indiceExistente];
        _carrito[indiceExistente] = NuevoItemAutoservicio(
          idProducto: actual.idProducto,
          producto: actual.producto,
          cantidad: actual.cantidad + _cantidad,
          precioUnitario: actual.precioUnitario,
          esPaquete: actual.esPaquete,
        );
      } else {
        _carrito.add(
          NuevoItemAutoservicio(
            idProducto: producto.idProducto,
            producto: producto.nombre,
            cantidad: _cantidad,
            precioUnitario: producto.precioUnitario,
            esPaquete: producto.esPaquete,
          ),
        );
      }
    });

    _aplicarCantidadPorDefecto();
  }

  void _quitarDelCarrito(int indice) {
    setState(() {
      _carrito.removeAt(indice);
      _error = null;
    });
  }

  /// Las líneas del carrito, en el formato que muestra [CarritoPedido].
  List<LineaCarrito> get _lineasCarrito => _carrito
      .map(
        (i) => LineaCarrito(
          titulo: i.producto,
          cantidad: i.cantidad,
          precioUnitario: i.precioUnitario,
          subtotal: i.subtotal,
          etiquetaUnidad: i.esPaquete ? 'paquetes' : 'unidades',
        ),
      )
      .toList();

  Future<void> _registrarPedido() async {
    if (_carrito.isEmpty) {
      setState(
        () => _error = 'Agrega al menos un producto antes de confirmar.',
      );
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
        items: List.of(_carrito),
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
        icon: const PhosphorIcon(
          PhosphorIconsDuotone.hourglassHigh,
          color: Color(0xFFEA8C1B),
          size: 40,
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
                const PhosphorIcon(
                  PhosphorIconsRegular.calendarCheck,
                  size: 18,
                ),
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
                const PhosphorIcon(
                  PhosphorIconsRegular.clockCounterClockwise,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Registrado el ${formatoFechaHoraCreacion.format(resultado.fechaCreacion)}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Una fila por producto: con varios en el pedido, el total solo
            // no alcanza para confirmar que se pidió lo correcto.
            for (final item in resultado.items) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      '${item.descripcion} × ${item.cantidad}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('S/ ${item.subtotal.toStringAsFixed(2)}'),
                ],
              ),
              const SizedBox(height: 4),
            ],
            const SizedBox(height: 10),
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
    final escritorio = esEscritorio(context);

    return Scaffold(
      appBar: escritorio
          ? appBarGestion(
              context,
              titulo: 'Hacer un pedido',
              subtitulo: 'Tu pedido queda "por confirmar" hasta que la '
                  'tienda revise su stock',
            )
          : AppBar(title: const Text('Hacer un pedido')),
      bottomNavigationBar: widget.mostrarAnuncio ? const AdBanner() : null,
      body: SafeArea(
        bottom: !widget.mostrarAnuncio,
        child: _cargandoCatalogo
            ? const Center(child: AppLoadingIndicator())
            : _errorCarga != null
            ? EstadoError(mensaje: _errorCarga!, onReintentar: _cargarCatalogo)
            : _productos.isEmpty
            ? const EstadoVacio(
                icono: PhosphorIconsRegular.storefront,
                titulo: 'Todavía no hay pedidos disponibles para hacer.',
              )
            : escritorio
            ? _construirEscritorio(theme, scheme)
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _campoProducto(),
                      if (_productoSeleccionado != null) ...[
                        const SizedBox(height: 8),
                        Text(_notaProducto, style: theme.textTheme.bodyMedium),
                      ],
                      const SizedBox(height: 20),
                      _campoCantidad(),
                      const SizedBox(height: 16),
                      _botonAgregar(),
                      const SizedBox(height: 20),
                      CarritoPedido(
                        lineas: _lineasCarrito,
                        onEliminar: _quitarDelCarrito,
                        habilitado: !_enviando,
                        mensajeVacio:
                            'Todavía no agregaste nada. Elige un producto y una '
                            'cantidad, y toca "Agregar al pedido".',
                      ),
                      const SizedBox(height: 24),
                      Text('¿Cuándo lo recoges?', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: _botonFecha()),
                          const SizedBox(width: 12),
                          Expanded(child: _botonHora()),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _campoNotas(),
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
                        label: 'Confirmar pedido',
                        icono: PhosphorIconsRegular.shoppingCartSimple,
                        cargando: _enviando,
                        onPressed: _carrito.isEmpty ? null : _registrarPedido,
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: 250.ms),
              ),
      ),
    );
  }

  // ---------------------------------------------------------------- común

  String get _notaProducto => _esPaquete
      ? 'Cada paquete trae 12 panes de hamburguesa y cuesta S/ ${_productoSeleccionado!.precioUnitario.toStringAsFixed(2)}, sin importar cuántos paquetes pidas.'
      : 'Pedido mínimo: $_cantidadMinimaUnidad panes.';

  Widget _campoProducto() {
    return SelectorDesplegable<ProductoAutoservicio>(
      valor: _productoSeleccionado,
      opciones: _productos,
      etiqueta: (p) => p.nombre,
      label: 'Producto',
      icono: PhosphorIconsRegular.bread,
      onChanged: _cambiarProducto,
    );
  }

  Widget _campoCantidad() {
    return TextFormField(
      controller: _cantidadController,
      keyboardType: TextInputType.number,
      maxLength: 4,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: _esPaquete
            ? 'Cantidad de paquetes (12 unidades cada uno)'
            : 'Cantidad',
        prefixIcon: const PhosphorIcon(PhosphorIconsRegular.listNumbers),
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
    );
  }

  Widget _botonFecha() {
    return OutlinedButton.icon(
      onPressed: _elegirFecha,
      icon: const PhosphorIcon(PhosphorIconsRegular.calendarBlank, size: 18),
      label: Text(
        _fechaEntrega == null
            ? 'Fecha de entrega'
            : DateFormat('dd/MM/yyyy').format(_fechaEntrega!),
      ),
    );
  }

  Widget _botonHora() {
    return OutlinedButton.icon(
      onPressed: _elegirHora,
      icon: const PhosphorIcon(PhosphorIconsRegular.clock, size: 18),
      label: Text(
        _horaEntrega == null
            ? 'Hora de entrega'
            : _horaEntrega!.format(context),
      ),
    );
  }

  /// Cierra el bloque "producto actual" y lo manda al pedido.
  Widget _botonAgregar() {
    return OutlinedButton.icon(
      onPressed: _enviando ? null : _agregarAlCarrito,
      icon: const PhosphorIcon(PhosphorIconsRegular.plusCircle, size: 18),
      label: Text(
        _totalLineaActual > 0
            ? 'Agregar al pedido · S/ ${_totalLineaActual.toStringAsFixed(2)}'
            : 'Agregar al pedido',
      ),
    );
  }

  Widget _campoNotas() {
    return TextFormField(
      controller: _notasController,
      textCapitalization: TextCapitalization.characters,
      inputFormatters: const [UpperCaseTextFormatter()],
      decoration: const InputDecoration(labelText: 'Notas (opcional)'),
      maxLines: 2,
    );
  }

  // ----------------------------------------------------------- escritorio

  Widget _construirEscritorio(ThemeData theme, ColorScheme scheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 48),
      child: ContenidoCentrado(
        anchoMaximo: 1040,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const EncabezadoEscritorio(
                anteTitulo: 'AUTOSERVICIO',
                titulo: 'Hacer un pedido',
                subtitulo:
                    'Elige el producto, cuánto y cuándo lo recoges. La '
                    'tienda lo confirma según su stock.',
              ),
              const SizedBox(height: espacioEscritorio),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: _panelDatos(theme)),
                  const SizedBox(width: espacioEscritorio),
                  Expanded(flex: 4, child: _panelResumen(theme, scheme)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _panelDatos(ThemeData theme) {
    return PanelEscritorio(
          titulo: 'Tu pedido',
          subtitulo: 'Producto, cantidad y entrega',
          icono: PhosphorIconsRegular.bread,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _campoProducto(),
              if (_productoSeleccionado != null) ...[
                const SizedBox(height: 8),
                Text(_notaProducto, style: theme.textTheme.bodyMedium),
              ],
              const SizedBox(height: 20),
              _campoCantidad(),
              const SizedBox(height: 16),
              _botonAgregar(),
              const SizedBox(height: 20),
              CarritoPedido(
                lineas: _lineasCarrito,
                onEliminar: _quitarDelCarrito,
                habilitado: !_enviando,
                mensajeVacio:
                    'Todavía no agregaste nada. Elige un producto y una '
                    'cantidad, y toca "Agregar al pedido".',
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: _botonFecha()),
                  const SizedBox(width: 12),
                  Expanded(child: _botonHora()),
                ],
              ),
              const SizedBox(height: 16),
              _campoNotas(),
            ],
          ),
        )
        .animate(delay: 60.ms)
        .fadeIn(duration: 320.ms)
        .moveY(begin: 12, end: 0, curve: Curves.easeOutCubic);
  }

  /// Resumen "de carrito": el total y el botón de confirmar quedan a la
  /// vista mientras se completan los campos de la izquierda.
  Widget _panelResumen(ThemeData theme, ColorScheme scheme) {
    // El detalle producto por producto vive en el carrito, a la izquierda:
    // acá quedan las cifras del pedido completo y el botón de confirmar.
    final hayResumen = _carrito.isNotEmpty;

    return TarjetaEscritorio(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          radio: 24,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const PhosphorIcon(
                      PhosphorIconsRegular.receipt,
                      size: 19,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('Resumen', style: theme.textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 20),
              if (!hayResumen)
                Text(
                  'Agrega al menos un producto para ver el total.',
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                )
              else ...[
                _FilaResumen(
                  etiqueta: 'Productos',
                  valor: _carrito.length == 1
                      ? '1 producto'
                      : '${_carrito.length} productos',
                ),
                const SizedBox(height: 8),
                _FilaResumen(
                  etiqueta: 'Unidades en total',
                  valor:
                      '${_carrito.fold<int>(0, (acc, i) => acc + i.cantidad)}',
                ),
                const SizedBox(height: 8),
                _FilaResumen(
                  etiqueta: 'Entrega',
                  valor: _fechaEntrega == null
                      ? 'Sin fecha'
                      : DateFormat('dd/MM/yyyy').format(_fechaEntrega!) +
                            (_horaEntrega == null
                                ? ''
                                : ' · ${_horaEntrega!.format(context)}'),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.primary, AppColors.secondary],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'Total',
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'S/ ${_total.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 14),
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
                label: 'Confirmar pedido',
                icono: PhosphorIconsRegular.shoppingCartSimple,
                cargando: _enviando,
                onPressed: _carrito.isEmpty ? null : _registrarPedido,
              ),
            ],
          ),
        )
        .animate(delay: 140.ms)
        .fadeIn(duration: 320.ms)
        .moveY(begin: 12, end: 0, curve: Curves.easeOutCubic);
  }
}

/// Fila etiqueta/valor del resumen de escritorio.
class _FilaResumen extends StatelessWidget {
  const _FilaResumen({required this.etiqueta, required this.valor});

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            etiqueta,
            style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12.5),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            valor,
            textAlign: TextAlign.right,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
