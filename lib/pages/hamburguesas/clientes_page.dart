import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../models/cliente_model.dart';
import '../../services/api_client.dart';
import '../../services/clientes_service.dart';
import '../../utils/texto_utils.dart';
import '../../widgets/cliente_acciones_sheet.dart';
import '../../widgets/cliente_card.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/segmented_switch.dart';
import 'cliente_form_page.dart';

/// Módulo de Clientes de Hamburguesas: lista con búsqueda predictiva local,
/// tarjetas con auditoría visual de calidad de dato y acciones directas.
class ClientesPage extends StatefulWidget {
  const ClientesPage({super.key});

  @override
  State<ClientesPage> createState() => _ClientesPageState();
}

class _ClientesPageState extends State<ClientesPage> {
  final _clientesService = ClientesService();
  final _busquedaController = TextEditingController();

  List<Cliente> _clientes = [];
  bool _cargando = true;
  String? _error;
  String _busqueda = '';

  /// 0 = Activos, 1 = Desactivados. Los clientes desactivados nunca se
  /// borran — solo quedan ocultos de la vista normal hasta reactivarlos.
  int _filtroIndice = 0;
  String get _estadoFiltro => _filtroIndice == 0 ? 'activos' : 'inactivos';

  @override
  void initState() {
    super.initState();
    _cargarClientes();
  }

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  Future<void> _cargarClientes() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final clientes = await _clientesService.listar(estado: _estadoFiltro);
      setState(() => _clientes = clientes);
    } on ApiException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(() => _error = 'No se pudo cargar la lista de clientes.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _cambiarFiltro(int indice) {
    if (indice == _filtroIndice) return;
    setState(() => _filtroIndice = indice);
    _cargarClientes();
  }

  /// Búsqueda inteligente: compara en simultáneo razón social, nombre
  /// comercial/puesto, nombres/apellidos y el documento (DNI o RUC son el
  /// mismo campo `dni`). El "Nombre comercial / Puesto" se indexa con
  /// prioridad — si el vendedor busca "Auto Rojo" y ese es el puesto de un
  /// cliente, aparece primero aunque también haya coincidencias de nombre.
  List<Cliente> get _clientesFiltrados {
    final query = normalizarBusqueda(_busqueda);
    if (query.isEmpty) return _clientes;

    final porNombreComercial = <Cliente>[];
    final porOtroCampo = <Cliente>[];

    for (final cliente in _clientes) {
      final nombreComercial = normalizarBusqueda(cliente.nombreComercial ?? '');
      if (nombreComercial.contains(query)) {
        porNombreComercial.add(cliente);
        continue;
      }
      final resto = normalizarBusqueda(
        '${cliente.nombreCompleto} ${cliente.dni ?? ''}',
      );
      if (resto.contains(query)) porOtroCampo.add(cliente);
    }

    return [...porNombreComercial, ...porOtroCampo];
  }

  Future<void> _abrirFormulario({Cliente? clienteExistente}) async {
    final guardado = await pushSlideUpFade<bool>(
      context,
      (_) => ClienteFormPage(clienteExistente: clienteExistente),
    );
    if (guardado == true) _cargarClientes();
  }

  Future<void> _abrirAcciones(Cliente cliente) async {
    final accion = await showClienteAccionesSheet(context, cliente);
    if (!mounted || accion == null) return;

    if (accion == ClienteAccion.editar) {
      await _abrirFormulario(clienteExistente: cliente);
    } else if (accion == ClienteAccion.desactivar) {
      await _confirmarDesactivar(cliente);
    } else if (accion == ClienteAccion.reactivar) {
      await _reactivar(cliente);
    }
  }

  Future<void> _reactivar(Cliente cliente) async {
    try {
      await _clientesService.reactivar(cliente.idCliente);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${cliente.nombreParaMostrar} fue reactivado correctamente.',
          ),
        ),
      );
      _cargarClientes();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.mensaje)));
    }
  }

  Future<void> _confirmarDesactivar(Cliente cliente) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Desactivar cliente'),
        content: Text(
          '¿Seguro que deseas desactivar a ${cliente.nombreCompleto}? Podrás seguir viendo su historial.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Desactivar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      await _clientesService.desactivar(cliente.idCliente);
      _cargarClientes();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.mensaje)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Clientes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Nuevo cliente'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: SegmentedSwitch(
                opciones: const ['Activos', 'Desactivados'],
                indiceSeleccionado: _filtroIndice,
                onChanged: _cambiarFiltro,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: TextField(
                controller: _busquedaController,
                onChanged: (value) => setState(() => _busqueda = value),
                decoration: InputDecoration(
                  hintText: 'Buscar por nombre, razón social, RUC o DNI',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _busqueda.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _busquedaController.clear();
                            setState(() => _busqueda = '');
                          },
                        ),
                ),
              ),
            ),
            Expanded(child: _construirCuerpo(theme)),
          ],
        ),
      ),
    );
  }

  Widget _construirCuerpo(ThemeData theme) {
    if (_cargando) {
      return const Center(child: AppLoadingIndicator());
    }

    if (_error != null) {
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
                onPressed: _cargarClientes,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    final clientes = _clientesFiltrados;

    if (clientes.isEmpty) {
      final sinBusqueda = _filtroIndice == 0
          ? 'Aún no hay clientes registrados'
          : 'No hay clientes desactivados';
      return Center(
        child: Text(
          _busqueda.isEmpty ? sinBusqueda : 'No se encontraron clientes',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargarClientes,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
        itemCount: clientes.length,
        itemBuilder: (context, index) {
          final cliente = clientes[index];
          return ClienteCard(
                cliente: cliente,
                onTap: () => _abrirAcciones(cliente),
              )
              .animate(delay: (30 * index).ms)
              .fadeIn(duration: 250.ms)
              .moveY(begin: 8, end: 0);
        },
      ),
    );
  }
}
