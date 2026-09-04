import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../models/cliente_model.dart';
import '../../services/api_client.dart';
import '../../services/clientes_service.dart';
import '../../services/horneados_service.dart';
import '../../services/notificaciones_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/text_formatters.dart';
import '../../utils/texto_utils.dart';
import '../../widgets/campo_con_sugerencias.dart';
import '../../widgets/carrito_pedido_widget.dart';
import '../../widgets/estado_error.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/premium_button.dart';
import '../../widgets/segmented_switch.dart';
import '../../widgets/escritorio.dart';

const _tiposAderezo = ['CRIOLLO', 'ORIENTAL'];

/// Registro de un nuevo pedido de Horneados: carne y presentación con
/// autocompletado "que aprende" (ver [CampoConSugerencias]), aderezo
/// opcional de un solo tipo y total calculado automáticamente.
///
/// Un pedido puede llevar VARIAS líneas, cada una con su propia carne,
/// presentación y aderezo: los campos de abajo arman "la línea actual" y
/// "Agregar al pedido" la manda al carrito. El cliente es de la cabecera y
/// se elige una sola vez.
///
/// En escritorio (>= [esEscritorio]) el formulario deja de ser una sola
/// columna larga: los datos quedan a la izquierda en dos paneles (cliente y
/// detalle del horneado) y el resumen con el total + el botón de registro se
/// van a una columna lateral fija a la derecha, siempre visible. Los campos
/// son exactamente los mismos widgets en ambos layouts; por debajo del
/// umbral el árbol es idéntico al de siempre.
class NuevoPedidoHorneadosPage extends StatefulWidget {
  const NuevoPedidoHorneadosPage({super.key});

  @override
  State<NuevoPedidoHorneadosPage> createState() =>
      _NuevoPedidoHorneadosPageState();
}

class _NuevoPedidoHorneadosPageState extends State<NuevoPedidoHorneadosPage> {
  final _formKey = GlobalKey<FormState>();
  final _carneController = TextEditingController();
  final _presentacionController = TextEditingController();
  final _cantidadController = TextEditingController();
  final _precioHorneadoController = TextEditingController();
  final _precioAderezoController = TextEditingController();
  final _clientesService = ClientesService();
  final _horneadosService = HorneadosService();

  bool _cargandoDatos = true;
  String? _errorCarga;
  List<Cliente> _clientes = [];

  Cliente? _clienteSeleccionado;
  bool _aplicaAderezo = false;
  int _tipoAderezoIndex = 0; // 0 = CRIOLLO, 1 = ORIENTAL

  /// Las líneas ya agregadas al pedido — cada una conserva su carne,
  /// presentación y aderezo propios.
  final List<NuevoItemHorneado> _carrito = [];

  bool _enviando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
    _cantidadController.addListener(_refrescarTotal);
    _precioHorneadoController.addListener(_refrescarTotal);
    _precioAderezoController.addListener(_refrescarTotal);
  }

  @override
  void dispose() {
    _carneController.dispose();
    _presentacionController.dispose();
    _cantidadController.dispose();
    _precioHorneadoController.dispose();
    _precioAderezoController.dispose();
    super.dispose();
  }

  void _refrescarTotal() => setState(() {});

  Future<void> _cargarDatos() async {
    setState(() {
      _cargandoDatos = true;
      _errorCarga = null;
    });
    try {
      final clientes = await _clientesService.listar();
      setState(() => _clientes = clientes);
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

  void _cambiarAplicaAderezo(bool valor) {
    setState(() {
      _aplicaAderezo = valor;
      // Al apagar el toggle (o si nunca se prendió), el precio del aderezo
      // no debe quedar con un valor viejo escondido — se limpia junto con
      // el campo, para que si se vuelve a activar arranque en blanco.
      if (!valor) _precioAderezoController.clear();
    });
  }

  int get _cantidad => int.tryParse(_cantidadController.text) ?? 0;

  double get _precioHorneado =>
      double.tryParse(_precioHorneadoController.text.replaceAll(',', '.')) ??
      0;

  double get _precioAderezo =>
      double.tryParse(_precioAderezoController.text.replaceAll(',', '.')) ??
      0;

  double get _precioUnitario =>
      _precioHorneado + (_aplicaAderezo ? _precioAderezo : 0);

  /// Lo que suma la línea que se está armando ahora — todavía no está en el
  /// pedido. El total real es [_total].
  double get _totalLineaActual => _precioUnitario * _cantidad;

  /// Total del pedido: la suma de las líneas ya agregadas.
  double get _total => _carrito.fold<double>(0, (acc, i) => acc + i.subtotal);

  /// Valida la línea en pantalla y la manda al carrito, dejando los campos
  /// del horneado listos para la siguiente. El cliente no se toca: es de la
  /// cabecera del pedido.
  void _agregarAlCarrito() {
    if (!_formKey.currentState!.validate()) return;

    final carne = _carneController.text.trim();
    final presentacion = _presentacionController.text.trim();
    if (carne.isEmpty || presentacion.isEmpty) {
      setState(() => _error = 'Indica la carne y la presentación.');
      return;
    }

    setState(() {
      _error = null;
      _carrito.add(
        NuevoItemHorneado(
          carne: carne,
          presentacion: presentacion,
          cantidad: _cantidad,
          aplicaAderezo: _aplicaAderezo,
          tipoAderezo: _aplicaAderezo ? _tiposAderezo[_tipoAderezoIndex] : null,
          precioHorneado: _precioHorneado,
          precioAderezo: _aplicaAderezo ? _precioAderezo : null,
        ),
      );
      // Se limpia TODO el bloque del horneado: dos líneas del mismo pedido
      // suelen ser carnes distintas, no la misma repetida.
      _carneController.clear();
      _presentacionController.clear();
      _cantidadController.clear();
      _precioHorneadoController.clear();
      _precioAderezoController.clear();
      _aplicaAderezo = false;
      _tipoAderezoIndex = 0;
    });
  }

  void _quitarDelCarrito(int indice) {
    setState(() {
      _carrito.removeAt(indice);
      _error = null;
    });
  }

  /// Las líneas del carrito, en el formato que muestra [CarritoPedido]. Acá
  /// el "título" es la carne y la presentación — el producto de catálogo es
  /// siempre el mismo y no distinguiría una línea de otra.
  List<LineaCarrito> get _lineasCarrito => _carrito
      .map(
        (i) => LineaCarrito(
          titulo: '${i.carne} · ${i.presentacion}',
          subtitulo: i.aplicaAderezo
              ? 'Aderezo ${i.tipoAderezo?.toLowerCase()} · S/ ${(i.precioAderezo ?? 0).toStringAsFixed(2)}'
              : null,
          cantidad: i.cantidad,
          precioUnitario: i.precioUnitario,
          subtotal: i.subtotal,
        ),
      )
      .toList();

  Future<void> _registrarPedido() async {
    if (_clienteSeleccionado == null) {
      setState(() => _error = 'Selecciona un cliente para el pedido.');
      return;
    }
    if (_carrito.isEmpty) {
      setState(() => _error = 'Agrega al menos una línea antes de confirmar.');
      return;
    }

    setState(() {
      _enviando = true;
      _error = null;
    });

    try {
      final resultado = await _horneadosService.crearPedido(
        idCliente: _clienteSeleccionado!.idCliente,
        items: List.of(_carrito),
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
        icon: const PhosphorIcon(
          PhosphorIconsFill.checkCircle,
          color: Color(0xFF2E7D32),
          size: 36,
        ),
        title: Text('Pedido #${resultado.numeroPedidoDia} registrado'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _FilaResumen(
                icono: PhosphorIconsRegular.user,
                texto: cliente.nombreParaMostrar,
                destacado: true,
              ),
              if (nombreComercial != null) ...[
                const SizedBox(height: 4),
                _FilaResumen(
                  icono: PhosphorIconsRegular.storefront,
                  texto: nombreComercial,
                  color: scheme.secondary,
                ),
              ],
              const SizedBox(height: 10),
              // Una entrada por línea: cada una tiene su propia carne,
              // presentación y aderezo, así que un solo bloque no alcanza.
              for (final item in resultado.items) ...[
                _FilaResumen(
                  icono: PhosphorIconsRegular.bowlFood,
                  texto:
                      '${item.descripcion} × ${item.cantidad} — S/ ${item.subtotal.toStringAsFixed(2)}',
                ),
                if (item.aplicaAderezo == true) ...[
                  const SizedBox(height: 2),
                  _FilaResumen(
                    icono: PhosphorIconsRegular.drop,
                    texto: 'Aderezo: ${item.tipoAderezo}',
                  ),
                ],
                const SizedBox(height: 6),
              ],
              _FilaResumen(
                icono: PhosphorIconsRegular.clockCounterClockwise,
                texto:
                    'Registrado el ${formatoFechaHoraCreacion.format(resultado.fechaCreacion)}',
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
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

  // ------------------------------------------------- piezas del formulario
  // Se comparten tal cual entre el layout móvil y el de escritorio: lo único
  // que cambia entre los dos es cómo se acomodan, no qué widget es cada campo.

  Widget _selectorCliente() => _SelectorClienteHorneados(
    clientes: _clientes,
    seleccionado: _clienteSeleccionado,
    onSeleccionado: (c) => setState(() => _clienteSeleccionado = c),
  );

  Widget _campoCarne() => CampoConSugerencias(
    controller: _carneController,
    label: 'Ej. POLLO, PAVO, CHANCHO',
    icono: PhosphorIconsRegular.bowlFood,
    buscarSugerencias: (prefijo) =>
        _horneadosService.sugerencias('CARNE', q: prefijo),
  );

  Widget _campoPresentacion() => CampoConSugerencias(
    controller: _presentacionController,
    label: 'Ej. POR UNIDADES, POR PRESAS',
    icono: PhosphorIconsRegular.forkKnife,
    buscarSugerencias: (prefijo) =>
        _horneadosService.sugerencias('PRESENTACION', q: prefijo),
  );

  Widget _campoCantidad() => TextFormField(
    controller: _cantidadController,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    decoration: const InputDecoration(
      labelText: 'Cantidad',
      prefixIcon: PhosphorIcon(PhosphorIconsRegular.hash),
    ),
    validator: (v) {
      final n = int.tryParse(v ?? '');
      if (n == null || n <= 0) {
        return 'Ingresa una cantidad válida';
      }
      return null;
    },
  );

  Widget _interruptorAderezo(ColorScheme scheme) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    decoration: BoxDecoration(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(16),
    ),
    child: SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('¿Aplica aderezo?'),
      value: _aplicaAderezo,
      onChanged: _cambiarAplicaAderezo,
    ),
  );

  Widget _selectorTipoAderezo() => SegmentedSwitch(
    opciones: const ['Criollo', 'Oriental'],
    indiceSeleccionado: _tipoAderezoIndex,
    onChanged: (i) => setState(() => _tipoAderezoIndex = i),
  );

  Widget _campoPrecioHorneado() => TextFormField(
    controller: _precioHorneadoController,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: const [DecimalTextInputFormatter()],
    decoration: const InputDecoration(
      labelText: 'Precio del horneado (S/)',
      prefixIcon: PhosphorIcon(PhosphorIconsRegular.tag),
    ),
    validator: (v) {
      final n = double.tryParse((v ?? '').replaceAll(',', '.'));
      if (n == null || n <= 0) {
        return 'Ingresa un precio válido';
      }
      return null;
    },
  );

  Widget _campoPrecioAderezo() => TextFormField(
    controller: _precioAderezoController,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: const [DecimalTextInputFormatter()],
    decoration: const InputDecoration(
      labelText: 'Precio del aderezo (S/)',
      prefixIcon: PhosphorIcon(PhosphorIconsRegular.drop),
    ),
    validator: (v) {
      final n = double.tryParse((v ?? '').replaceAll(',', '.'));
      if (n == null || n <= 0) {
        return 'Ingresa un precio válido';
      }
      return null;
    },
  );

  Widget _cajaTotal(ThemeData theme, ColorScheme scheme) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: scheme.secondaryContainer,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('Total', style: theme.textTheme.titleMedium),
        Text(
              'S/ ${_total.toStringAsFixed(2)}',
              style: theme.textTheme.titleLarge?.copyWith(
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
  );

  /// Cierra el bloque "línea actual" y la manda al pedido.
  Widget _botonAgregar() => OutlinedButton.icon(
    onPressed: _enviando ? null : _agregarAlCarrito,
    icon: const PhosphorIcon(PhosphorIconsRegular.plusCircle, size: 18),
    label: Text(
      _totalLineaActual > 0
          ? 'Agregar al pedido · S/ ${_totalLineaActual.toStringAsFixed(2)}'
          : 'Agregar al pedido',
    ),
  );

  Widget _carritoPedido() => CarritoPedido(
    lineas: _lineasCarrito,
    onEliminar: _quitarDelCarrito,
    habilitado: !_enviando,
    titulo: 'Líneas del pedido',
    mensajeVacio:
        'Todavía no agregaste ninguna línea. Completa la carne, la '
        'presentación y el precio, y toca "Agregar al pedido".',
  );

  Widget _botonRegistrar() => PremiumButton(
    label: 'Confirmar pedido',
    icono: PhosphorIconsBold.shoppingCartSimple,
    cargando: _enviando,
    // Sin líneas no hay pedido que confirmar.
    onPressed: _carrito.isEmpty ? null : _registrarPedido,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBarGestion(context, titulo: 'Nuevo pedido de Horneados'),
      body: SafeArea(
        child: _cargandoDatos
            ? const Center(child: AppLoadingIndicator())
            : _errorCarga != null
            ? EstadoError(mensaje: _errorCarga!, onReintentar: _cargarDatos)
            : esEscritorio(context)
            ? _construirEscritorio(context)
            : _construirMovil(context),
      ),
    );
  }

  // ---------------------------------------------------------------- móvil

  Widget _construirMovil(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Cliente', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            _selectorCliente(),
            const SizedBox(height: 24),
            Text('Carne', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            _campoCarne(),
            const SizedBox(height: 20),
            Text('Presentación', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            _campoPresentacion(),
            const SizedBox(height: 20),
            _campoCantidad(),
            const SizedBox(height: 20),
            _interruptorAderezo(scheme),
            if (_aplicaAderezo) ...[
              const SizedBox(height: 16),
              _selectorTipoAderezo(),
            ],
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _campoPrecioHorneado()),
                if (_aplicaAderezo) ...[
                  const SizedBox(width: 12),
                  Expanded(child: _campoPrecioAderezo()),
                ],
              ],
            ),
            const SizedBox(height: 20),
            _botonAgregar(),
            const SizedBox(height: 24),
            _carritoPedido(),
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
            _botonRegistrar(),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------- escritorio

  Widget _construirEscritorio(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cliente = _clienteSeleccionado;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 48),
      child: ContenidoCentrado(
        anchoMaximo: 1280,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const EncabezadoEscritorio(
                    icono: PhosphorIconsDuotone.shoppingCartSimple,
                    titulo: 'Nuevo pedido de Horneados',
                    subtitulo:
                        'Elige el cliente, describe el horneado y el total se '
                        'calcula solo mientras escribes.',
                  )
                  .animate()
                  .fadeIn(duration: 300.ms)
                  .moveY(begin: 10, end: 0),
              const SizedBox(height: 28),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        PanelEscritorio(
                              icono: PhosphorIconsRegular.user,
                              titulo: 'Cliente',
                              subtitulo:
                                  'Busca por nombre, razón social, RUC o DNI.',
                              hijos: [_selectorCliente()],
                            )
                            .animate(delay: 60.ms)
                            .fadeIn(duration: 280.ms)
                            .moveY(begin: 10, end: 0),
                        const SizedBox(height: 20),
                        PanelEscritorio(
                              icono: PhosphorIconsRegular.bowlFood,
                              titulo: 'Detalle del horneado',
                              subtitulo:
                                  'Carne y presentación aprenden de lo que ya '
                                  'registraste antes.',
                              separacion: 18,
                              hijos: [
                                Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: _campoCarne()),
                                    const SizedBox(width: 16),
                                    Expanded(child: _campoPresentacion()),
                                  ],
                                ),
                                Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: _campoCantidad()),
                                    const SizedBox(width: 16),
                                    Expanded(child: _campoPrecioHorneado()),
                                  ],
                                ),
                              ],
                            )
                            .animate(delay: 110.ms)
                            .fadeIn(duration: 280.ms)
                            .moveY(begin: 10, end: 0),
                        const SizedBox(height: 20),
                        PanelEscritorio(
                              icono: PhosphorIconsRegular.drop,
                              titulo: 'Aderezo',
                              subtitulo:
                                  'Opcional — si lo activas, su precio se suma '
                                  'al precio por unidad.',
                              separacion: 16,
                              hijos: [
                                _interruptorAderezo(scheme),
                                if (_aplicaAderezo) ...[
                                  _selectorTipoAderezo(),
                                  _campoPrecioAderezo(),
                                ],
                                _botonAgregar(),
                              ],
                            )
                            .animate(delay: 160.ms)
                            .fadeIn(duration: 280.ms)
                            .moveY(begin: 10, end: 0),
                        const SizedBox(height: 20),
                        _carritoPedido()
                            .animate(delay: 200.ms)
                            .fadeIn(duration: 280.ms)
                            .moveY(begin: 10, end: 0),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 2,
                    child:
                        PanelEscritorio(
                              icono: PhosphorIconsRegular.receipt,
                              titulo: 'Resumen',
                              separacion: 14,
                              hijos: [
                                _FilaResumen(
                                  icono: PhosphorIconsRegular.user,
                                  texto:
                                      cliente?.nombreParaMostrar ??
                                      'Sin cliente seleccionado',
                                  destacado: cliente != null,
                                  color: cliente == null
                                      ? AppColors.textSecondary
                                      : null,
                                ),
                                // El detalle línea por línea vive en el
                                // carrito, a la izquierda: acá quedan las
                                // cifras del pedido completo.
                                _FilaResumen(
                                  icono: PhosphorIconsRegular.listBullets,
                                  texto: _carrito.isEmpty
                                      ? 'Sin líneas todavía'
                                      : _carrito.length == 1
                                      ? '1 línea'
                                      : '${_carrito.length} líneas',
                                ),
                                _FilaResumen(
                                  icono: PhosphorIconsRegular.hash,
                                  texto:
                                      'Unidades en total: ${_carrito.fold<int>(0, (acc, i) => acc + i.cantidad)}',
                                ),
                                _cajaTotal(theme, scheme),
                                if (_error != null)
                                  Text(
                                    _error!,
                                    style: TextStyle(
                                      color: scheme.error,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                _botonRegistrar(),
                              ],
                            )
                            .animate(delay: 200.ms)
                            .fadeIn(duration: 280.ms)
                            .moveY(begin: 10, end: 0),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectorClienteHorneados extends StatelessWidget {
  const _SelectorClienteHorneados({
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
            prefixIcon: PhosphorIcon(PhosphorIconsRegular.magnifyingGlass),
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
        PhosphorIcon(icono, size: 18, color: color ?? theme.colorScheme.primary),
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
