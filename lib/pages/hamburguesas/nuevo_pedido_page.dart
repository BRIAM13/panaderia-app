import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import '../../models/cliente_model.dart';
import '../../models/tienda_model.dart';
import '../../services/api_client.dart';
import '../../services/clientes_service.dart';
import '../../services/configuraciones_service.dart';
import '../../services/notificaciones_service.dart';
import '../../services/pedidos_service.dart';
import '../../services/tiendas_service.dart';
import '../../utils/fecha_pedido_utils.dart';
import '../../utils/text_formatters.dart';
import '../../utils/texto_utils.dart';
import '../../widgets/estado_error.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/premium_button.dart';
import '../../widgets/segmented_switch.dart';

const _tiposPedido = ['UNIDADES', 'PAQUETES'];
const _claveConfigPrecioPaquete = 'PRECIO_PAQUETE';
const _precioPaqueteRespaldo =
    '3.50'; // si la configuración no carga por algún motivo

/// Registro de un nuevo pedido a nombre de un cliente, en una tienda de
/// catálogo simple (Hamburguesas o Panadería — Horneados tiene su propia
/// página con sus campos propios). Hamburguesas mantiene su formulario de
/// siempre (unidades sueltas o paquetes de 12, precio sugerido desde
/// Configuraciones); el resto (Panadería) elige un producto de su catálogo,
/// con el precio precargado desde ahí. En ambos casos la cantidad y el
/// precio quedan editables — el vendedor puede negociar un precio especial.
class NuevoPedidoPage extends StatefulWidget {
  const NuevoPedidoPage({super.key, required this.tienda});

  final Tienda tienda;

  @override
  State<NuevoPedidoPage> createState() => _NuevoPedidoPageState();
}

class _NuevoPedidoPageState extends State<NuevoPedidoPage> {
  final _formKey = GlobalKey<FormState>();
  final _cantidadController = TextEditingController();
  final _precioController = TextEditingController();
  final _notasController = TextEditingController();
  final _clientesService = ClientesService();
  final _configuracionesService = ConfiguracionesService();
  final _pedidosService = PedidosService();
  final _tiendasService = TiendasService();

  bool _cargandoDatos = true;
  String? _errorCarga;

  List<Cliente> _clientes = [];
  String _precioPaqueteSugerido = _precioPaqueteRespaldo;

  /// Catálogo de la tienda — para Hamburguesas trae un solo producto
  /// (implícito, no se muestra selector); para Panadería, varios.
  List<ProductoAutoservicio> _productos = [];
  ProductoAutoservicio? _productoSeleccionado;

  bool get _esHamburguesas => widget.tienda.slug == 'hamburguesas';

  Cliente? _clienteSeleccionado;
  int _tipoPedidoIndex = 1; // 0 = UNIDADES, 1 = PAQUETES (por defecto)
  // Por defecto el día de hoy — el vendedor la cambia si el pedido es para
  // otro día; la hora queda vacía porque no hay un valor por defecto obvio.
  DateTime? _fechaEntrega = DateTime.now();
  TimeOfDay? _horaEntrega;

  bool _enviando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
    _cantidadController.addListener(_refrescarTotal);
    _precioController.addListener(_refrescarTotal);
  }

  @override
  void dispose() {
    _cantidadController.dispose();
    _precioController.dispose();
    _notasController.dispose();
    super.dispose();
  }

  void _refrescarTotal() => setState(() {});

  Future<void> _cargarDatos() async {
    setState(() {
      _cargandoDatos = true;
      _errorCarga = null;
    });

    try {
      final resultados = await Future.wait([
        _clientesService.listar(),
        _tiendasService.listarProductos(widget.tienda.idTienda),
        _esHamburguesas
            ? _configuracionesService.obtener(_claveConfigPrecioPaquete)
            : Future.value(_precioPaqueteRespaldo),
      ]);
      final clientes = resultados[0] as List<Cliente>;
      final productos = resultados[1] as List<ProductoAutoservicio>;
      final precioPaquete = resultados[2] as String;

      setState(() {
        _clientes = clientes;
        _productos = productos;
        _precioPaqueteSugerido = precioPaquete;
        _productoSeleccionado = productos.isNotEmpty ? productos.first : null;
      });
      _aplicarValoresPorDefecto();
    } on ApiException catch (e) {
      setState(() => _errorCarga = e.mensaje);
    } catch (_) {
      setState(
        () => _errorCarga = 'No se pudieron cargar los datos del pedido.',
      );
    } finally {
      if (mounted) setState(() => _cargandoDatos = false);
    }
  }

  /// Hamburguesas: precarga cantidad=1 y el precio sugerido, solo tiene
  /// sentido para "Paquetes"; "Unidades" siempre arranca vacío para forzar
  /// un ingreso manual (son pedidos especiales, sin precio de catálogo).
  /// Resto de tiendas (Panadería): precarga cantidad=1 y el precio del
  /// producto elegido — siempre hay un precio de catálogo de referencia.
  void _aplicarValoresPorDefecto() {
    if (!_esHamburguesas) {
      _cantidadController.text = '1';
      _precioController.text = (_productoSeleccionado?.precioUnitario ?? 0)
          .toStringAsFixed(2);
      return;
    }
    if (_tipoPedidoIndex == 1) {
      _cantidadController.text = '1';
      _precioController.text = _precioPaqueteSugerido;
    } else {
      _cantidadController.clear();
      _precioController.clear();
    }
  }

  void _cambiarTipoPedido(int index) {
    setState(() => _tipoPedidoIndex = index);
    _aplicarValoresPorDefecto();
  }

  void _cambiarProducto(ProductoAutoservicio? producto) {
    setState(() => _productoSeleccionado = producto);
    _aplicarValoresPorDefecto();
  }

  bool get _esPaquete => _esHamburguesas && _tipoPedidoIndex == 1;

  int get _cantidad => int.tryParse(_cantidadController.text) ?? 0;

  /// Cuando el precio es "por unidad" el total se calcula multiplicando por
  /// la cantidad. Solo Hamburguesas en "Unidades" (pedido especial, sin
  /// catálogo) es la excepción: ahí el vendedor escribe directamente el
  /// total del pedido, sin multiplicar.
  bool get _precioEsPorUnidad => !_esHamburguesas || _esPaquete;

  double get _valorIngresado =>
      double.tryParse(_precioController.text.replaceAll(',', '.')) ?? 0;

  double get _total =>
      _precioEsPorUnidad ? _valorIngresado * _cantidad : _valorIngresado;

  /// Precio por unidad que se envía al backend (que siempre calcula
  /// total = precioUnitario × cantidad). En Hamburguesas "Unidades" el
  /// vendedor ingresa el total final directamente, así que aquí se deriva
  /// el equivalente por unidad para que ese cálculo reproduzca el total
  /// exacto que se mostró en pantalla.
  double get _precioUnitarioParaEnviar {
    if (_precioEsPorUnidad) return _valorIngresado;
    if (_cantidad <= 0) return 0;
    return double.parse((_valorIngresado / _cantidad).toStringAsFixed(2));
  }

  /// Hamburguesas solo tiene un producto implícito (el primero — y único —
  /// del catálogo cargado); el resto de tiendas usa el elegido en el
  /// selector.
  int? get _idProductoParaEnviar => _esHamburguesas
      ? (_productos.isNotEmpty ? _productos.first.idProducto : null)
      : _productoSeleccionado?.idProducto;

  /// Con fecha (siempre trae un valor por defecto: hoy) ya cuenta como
  /// "pedido con fecha programada", aunque no se elija una hora específica
  /// — la hora queda en medianoche como señal de "sin hora especificada"
  /// (ver PedidoCard, que oculta la hora cuando es exactamente 00:00).
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
      // `firstDate`/`initialDate` deben compararse solo por fecha: si se
      // deja la hora del momento exacto, `_fechaEntrega` (capturado antes,
      // en initState) puede quedar "antes" de `firstDate` por milisegundos
      // y showDatePicker lanza un assertion error.
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

    if (_clienteSeleccionado == null) {
      setState(() => _error = 'Selecciona un cliente para el pedido.');
      return;
    }
    final idProducto = _idProductoParaEnviar;
    if (idProducto == null) {
      setState(() => _error = 'Selecciona un producto para el pedido.');
      return;
    }
    // La fecha ya viene precargada con hoy, y por sí sola ya cuenta como
    // "entrega programada" (no hace falta elegir una hora específica). Si
    // SÍ se eligió hora, recién ahí tiene sentido comparar el instante
    // exacto contra ahora — comparar "hoy a medianoche" contra el momento
    // actual siempre daría "en el pasado" y bloquearía el caso más común.
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
      final resultado = await _pedidosService.crear(
        idCliente: _clienteSeleccionado!.idCliente,
        idProducto: idProducto,
        tipoPedido: _esHamburguesas ? _tiposPedido[_tipoPedidoIndex] : 'UNIDADES',
        cantidad: _cantidad,
        precioUnitario: _precioUnitarioParaEnviar,
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cliente = resultado.cliente;
    final nombreComercial = cliente.nombreComercial;
    final formatoFechaHoraCreacion = DateFormat('d/MM/yyyy h:mm a', 'es');

    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          Icons.check_circle_rounded,
          color: const Color(0xFF2E7D32),
          size: 36,
        ),
        title: Text('Pedido #${resultado.numeroPedidoDia} registrado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FilaResumen(
              icono: Icons.person_rounded,
              texto: cliente.nombreParaMostrar,
              destacado: true,
            ),
            if (nombreComercial != null) ...[
              const SizedBox(height: 4),
              _FilaResumen(
                icono: Icons.storefront_rounded,
                texto: nombreComercial,
                color: scheme.secondary,
              ),
            ],
            const SizedBox(height: 10),
            _FilaResumen(
              icono: Icons.event_available_rounded,
              texto: resultado.fechaEntrega != null
                  ? formatearFechaEntrega(
                      resultado.fechaEntrega!,
                      formatoLargo: true,
                    )
                  : 'Sin fecha de entrega programada',
            ),
            const SizedBox(height: 4),
            _FilaResumen(
              icono: Icons.history_rounded,
              texto:
                  'Registrado el ${formatoFechaHoraCreacion.format(resultado.fechaCreacion)}',
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
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
    final esPaquete = _esPaquete;

    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo pedido')),
      body: SafeArea(
        child: _cargandoDatos
            ? const Center(child: AppLoadingIndicator())
            : _errorCarga != null
            ? EstadoError(mensaje: _errorCarga!, onReintentar: _cargarDatos)
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Cliente', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      _SelectorCliente(
                        clientes: _clientes,
                        seleccionado: _clienteSeleccionado,
                        onSeleccionado: (c) =>
                            setState(() => _clienteSeleccionado = c),
                      ),
                      const SizedBox(height: 24),
                      if (_esHamburguesas) ...[
                        Text(
                          'Tipo de pedido',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        SegmentedSwitch(
                          opciones: const [
                            'Unidades individuales',
                            'Paquetes de 12 panes',
                          ],
                          indiceSeleccionado: _tipoPedidoIndex,
                          onChanged: _cambiarTipoPedido,
                        ),
                        if (!esPaquete) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Pedido especial: ingresa manualmente la cantidad y el precio a cobrar por unidad.',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ] else ...[
                        Text('Producto', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
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
                            prefixIcon: Icon(Icons.inventory_2_rounded),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _cantidadController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: InputDecoration(
                                labelText: !_esHamburguesas
                                    ? 'Cantidad'
                                    : esPaquete
                                    ? 'Cantidad de paquetes'
                                    : 'Cantidad de unidades',
                                prefixIcon: const Icon(Icons.numbers_rounded),
                              ),
                              validator: (v) {
                                final n = int.tryParse(v ?? '');
                                if (n == null || n <= 0) {
                                  return 'Ingresa una cantidad válida';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _precioController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: const [
                                DecimalTextInputFormatter(),
                              ],
                              decoration: InputDecoration(
                                labelText: !_esHamburguesas
                                    ? 'Precio unitario (S/)'
                                    : esPaquete
                                    ? 'Precio del paquete (S/)'
                                    : 'Precio Total del Pedido (S/)',
                                prefixIcon: const Icon(Icons.sell_outlined),
                              ),
                              validator: (v) {
                                final n = double.tryParse(
                                  (v ?? '').replaceAll(',', '.'),
                                );
                                if (n == null || n <= 0) {
                                  return 'Ingresa un precio válido';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
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
                        decoration: const InputDecoration(labelText: 'Notas'),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_precioEsPorUnidad) ...[
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Precio unitario'),
                                  Text(
                                    'S/ ${_valorIngresado.toStringAsFixed(2)}',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                            ],
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Total',
                                  style: theme.textTheme.titleMedium,
                                ),
                                Text(
                                      'S/ ${_total.toStringAsFixed(2)}',
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    )
                                    .animate(target: 1)
                                    .scaleXY(
                                      begin: 0.9,
                                      end: 1,
                                      duration: 200.ms,
                                      curve: Curves.easeOut,
                                    ),
                              ],
                            ),
                          ],
                        ),
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
                      const SizedBox(height: 20),
                      PremiumButton(
                        label: 'Registrar pedido',
                        icono: Icons.add_shopping_cart_rounded,
                        cargando: _enviando,
                        onPressed: _registrarPedido,
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _SelectorCliente extends StatelessWidget {
  const _SelectorCliente({
    required this.clientes,
    required this.seleccionado,
    required this.onSeleccionado,
  });

  final List<Cliente> clientes;
  final Cliente? seleccionado;
  final ValueChanged<Cliente> onSeleccionado;

  @override
  Widget build(BuildContext context) {
    return Autocomplete<Cliente>(
      displayStringForOption: (c) => c.nombreParaMostrar,
      optionsBuilder: (textEditingValue) {
        final query = normalizarBusqueda(textEditingValue.text);
        if (query.isEmpty) return clientes;
        return clientes.where((c) {
          final texto = normalizarBusqueda(
            '${c.nombreCompleto} ${c.nombreComercial ?? ''} ${c.dni ?? ''}',
          );
          return texto.contains(query);
        });
      },
      onSelected: onSeleccionado,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        if (seleccionado != null && controller.text.isEmpty) {
          controller.text = seleccionado!.nombreParaMostrar;
        }
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          decoration: const InputDecoration(
            labelText: 'Buscar cliente por nombre, RUC o DNI',
            prefixIcon: Icon(Icons.person_search_rounded),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final cliente = options.elementAt(index);
                  return ListTile(
                    title: Text(cliente.nombreParaMostrar),
                    subtitle: Text(
                      cliente.nombreComercial ??
                          (cliente.dni != null
                              ? (cliente.dni!.length == 11
                                    ? 'RUC ${cliente.dni}'
                                    : 'DNI ${cliente.dni}')
                              : 'Sin documento'),
                    ),
                    onTap: () => onSelected(cliente),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FilaResumen extends StatelessWidget {
  const _FilaResumen({
    required this.icono,
    required this.texto,
    this.destacado = false,
    this.color,
  });

  final IconData icono;
  final String texto;
  final bool destacado;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icono, size: 18, color: color ?? theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            texto,
            style: destacado
                ? theme.textTheme.titleMedium
                : theme.textTheme.bodyMedium?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
