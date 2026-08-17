import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import '../../models/cliente_model.dart';
import '../../services/api_client.dart';
import '../../services/clientes_service.dart';
import '../../services/horneados_service.dart';
import '../../services/notificaciones_service.dart';
import '../../utils/text_formatters.dart';
import '../../utils/texto_utils.dart';
import '../../widgets/campo_con_sugerencias.dart';
import '../../widgets/estado_error.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/premium_button.dart';
import '../../widgets/segmented_switch.dart';

const _tiposAderezo = ['CRIOLLO', 'ORIENTAL'];

/// Registro de un nuevo pedido de Horneados: carne y presentación con
/// autocompletado "que aprende" (ver [CampoConSugerencias]), aderezo
/// opcional de un solo tipo y total calculado automáticamente.
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

  double get _total => _precioUnitario * _cantidad;

  Future<void> _registrarPedido() async {
    if (!_formKey.currentState!.validate()) return;

    if (_clienteSeleccionado == null) {
      setState(() => _error = 'Selecciona un cliente para el pedido.');
      return;
    }

    setState(() {
      _enviando = true;
      _error = null;
    });

    try {
      final resultado = await _horneadosService.crearPedido(
        idCliente: _clienteSeleccionado!.idCliente,
        carne: _carneController.text.trim(),
        presentacion: _presentacionController.text.trim(),
        cantidad: _cantidad,
        aplicaAderezo: _aplicaAderezo,
        tipoAderezo: _aplicaAderezo ? _tiposAderezo[_tipoAderezoIndex] : null,
        precioHorneado: _precioHorneado,
        precioAderezo: _aplicaAderezo ? _precioAderezo : null,
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

  Future<void> _mostrarResumenPedido(PedidoHorneadoResultado resultado) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cliente = resultado.cliente;
    final nombreComercial = cliente.nombreComercial;
    final formatoFechaHoraCreacion = DateFormat('d/MM/yyyy h:mm a', 'es');

    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(
          Icons.check_circle_rounded,
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
                icono: Icons.set_meal_rounded,
                texto: '${resultado.carne} · ${resultado.presentacion}',
              ),
              const SizedBox(height: 4),
              _FilaResumen(
                icono: Icons.numbers_rounded,
                texto: 'Cantidad: ${resultado.cantidad}',
              ),
              if (resultado.aplicaAderezo) ...[
                const SizedBox(height: 4),
                _FilaResumen(
                  icono: Icons.local_dining_rounded,
                  texto: 'Aderezo: ${resultado.tipoAderezo}',
                ),
              ],
              const SizedBox(height: 4),
              _FilaResumen(
                icono: Icons.history_rounded,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo pedido de Horneados')),
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
                      _SelectorClienteHorneados(
                        clientes: _clientes,
                        seleccionado: _clienteSeleccionado,
                        onSeleccionado: (c) =>
                            setState(() => _clienteSeleccionado = c),
                      ),
                      const SizedBox(height: 24),
                      Text('Carne', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      CampoConSugerencias(
                        controller: _carneController,
                        label: 'Ej. POLLO, PAVO, CHANCHO',
                        icono: Icons.set_meal_rounded,
                        buscarSugerencias: (prefijo) =>
                            _horneadosService.sugerencias(
                              'CARNE',
                              q: prefijo,
                            ),
                      ),
                      const SizedBox(height: 20),
                      Text('Presentación', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      CampoConSugerencias(
                        controller: _presentacionController,
                        label: 'Ej. POR UNIDADES, POR PRESAS',
                        icono: Icons.restaurant_menu_rounded,
                        buscarSugerencias: (prefijo) =>
                            _horneadosService.sugerencias(
                              'PRESENTACION',
                              q: prefijo,
                            ),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _cantidadController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(
                          labelText: 'Cantidad',
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
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(
                            alpha: 0.4,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('¿Aplica aderezo?'),
                          value: _aplicaAderezo,
                          onChanged: _cambiarAplicaAderezo,
                        ),
                      ),
                      if (_aplicaAderezo) ...[
                        const SizedBox(height: 16),
                        SegmentedSwitch(
                          opciones: const ['Criollo', 'Oriental'],
                          indiceSeleccionado: _tipoAderezoIndex,
                          onChanged: (i) =>
                              setState(() => _tipoAderezoIndex = i),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _precioHorneadoController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: const [
                                DecimalTextInputFormatter(),
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Precio del horneado (S/)',
                                prefixIcon: Icon(Icons.sell_outlined),
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
                          if (_aplicaAderezo) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _precioAderezoController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                inputFormatters: const [
                                  DecimalTextInputFormatter(),
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'Precio del aderezo (S/)',
                                  prefixIcon: Icon(
                                    Icons.local_dining_outlined,
                                  ),
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
                        ],
                      ),
                      const SizedBox(height: 24),
                      Container(
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
