import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../models/cliente_model.dart';
import '../../models/usuario_sesion.dart';
import '../../services/api_client.dart';
import '../../services/clientes_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/texto_utils.dart';
import '../../widgets/cliente_acciones_sheet.dart';
import '../../widgets/cliente_card.dart';
import '../../widgets/escritorio.dart';
import '../../widgets/estado_error.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/segmented_switch.dart';
import '../../widgets/skeleton_loader.dart';
import 'cliente_form_page.dart';
import 'cliente_perfil_page.dart';

/// Módulo de Clientes de Hamburguesas: lista con búsqueda predictiva local,
/// tarjetas con auditoría visual de calidad de dato y acciones directas.
class ClientesPage extends StatefulWidget {
  const ClientesPage({super.key, this.usuario});

  /// Necesario solo para decidir si se muestra el botón de campaña de
  /// reactivación (exclusivo ADMIN/SUPERADMIN) — opcional para no romper
  /// otros lugares que todavía navegan aquí sin sesión a mano.
  final UsuarioSesion? usuario;

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

  /// Solo se usa en el maestro-detalle de escritorio: qué cliente se está
  /// mostrando en el panel derecho. En celular siempre queda en null (ahí se
  /// navega a `ClientePerfilPage` como pantalla completa, igual que antes).
  Cliente? _seleccionado;

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
      setState(() {
        _clientes = clientes;
        // El panel de detalle sigue apuntando al MISMO cliente tras
        // recargar (con sus datos frescos); si ya no está en la lista
        // vigente — por ejemplo se acaba de desactivar y estamos viendo
        // "Activos" — se limpia en vez de mostrar una ficha fantasma.
        final seleccionado = _seleccionado;
        if (seleccionado != null) {
          final indice = clientes.indexWhere(
            (c) => c.idCliente == seleccionado.idCliente,
          );
          _seleccionado = indice >= 0 ? clientes[indice] : null;
        }
      });
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

    if (accion == ClienteAccion.verPerfil) {
      // En escritorio el perfil ya está a la vista: "Ver perfil" solo mueve
      // la selección del panel derecho, sin apilar otra ruta encima.
      if (esEscritorio(context)) {
        setState(() => _seleccionado = cliente);
      } else {
        await _abrirPerfil(cliente);
      }
    } else if (accion == ClienteAccion.editar) {
      await _abrirFormulario(clienteExistente: cliente);
    } else if (accion == ClienteAccion.desactivar) {
      await _confirmarDesactivar(cliente);
    } else if (accion == ClienteAccion.reactivar) {
      await _reactivar(cliente);
    }
  }

  Future<void> _abrirPerfil(Cliente cliente) async {
    await pushSlideUpFade(
      context,
      (_) => ClientePerfilPage(cliente: cliente),
    );
    _cargarClientes();
  }

  bool get _puedeEnviarCampania {
    final rol = widget.usuario?.rol;
    return rol == 'ADMIN' || rol == 'SUPERADMIN';
  }

  Future<void> _abrirCampaniaReactivacion() async {
    final mensajeController = TextEditingController(
      text:
          'Te extrañamos en Panadería Ronceros. Vuelve pronto, tenemos algo rico esperándote 🥖',
    );

    final mensaje = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Campaña de reactivación'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Se enviará este mensaje por notificación push a todos los '
              'clientes marcados como "En riesgo".',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: mensajeController,
              minLines: 2,
              maxLines: 4,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Mensaje'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(mensajeController.text.trim()),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );

    mensajeController.dispose();
    if (mensaje == null || mensaje.isEmpty || !mounted) return;

    try {
      final resultado = await _clientesService.enviarCampaniaReactivacion(
        mensaje,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Campaña enviada a ${resultado.clientesNotificados} clientes en '
            'riesgo (${resultado.dispositivosAlcanzados} dispositivos alcanzados).',
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.mensaje)));
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
    final escritorio = esEscritorio(context);

    final filtro = Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: SegmentedSwitch(
        opciones: const ['Activos', 'Desactivados'],
        indiceSeleccionado: _filtroIndice,
        onChanged: _cambiarFiltro,
      ),
    );

    final buscador = Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: TextField(
        controller: _busquedaController,
        onChanged: (value) => setState(() => _busqueda = value),
        decoration: InputDecoration(
          hintText: escritorio
              ? 'Buscar por nombre, RUC o DNI'
              : 'Buscar por nombre, razón social, RUC o DNI',
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
    );

    return Scaffold(
      appBar: appBarGestion(
        context,
        titulo: 'Clientes',
        subtitulo: escritorio
            ? '${_clientes.length} ${_filtroIndice == 0 ? 'activo(s)' : 'desactivado(s)'} en la cartera'
            : null,
        acciones: [
          if (_puedeEnviarCampania)
            IconButton(
              icon: const Icon(Icons.campaign_outlined),
              tooltip: 'Campaña de reactivación',
              onPressed: _abrirCampaniaReactivacion,
            ),
          // En escritorio el botón principal sube a la barra: un FAB
          // flotando sobre el panel de detalle taparía el contenido del
          // cliente que se está leyendo, y con mouse la esquina inferior
          // derecha no es un lugar privilegiado como sí lo es con el pulgar.
          if (escritorio) ...[
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => _abrirFormulario(),
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: const Text('Nuevo cliente'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ],
      ),
      floatingActionButton: escritorio
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _abrirFormulario(),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Nuevo cliente'),
            ),
      body: SafeArea(
        child: escritorio
            ? _cuerpoEscritorio(context, filtro: filtro, buscador: buscador)
            : Column(
                children: [
                  filtro,
                  buscador,
                  Expanded(child: _construirCuerpo()),
                ],
              ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // ESCRITORIO — maestro / detalle
  // ---------------------------------------------------------------------

  /// Lista a la izquierda, ficha completa del cliente elegido a la derecha,
  /// sin cambiar de ruta. En celular hay que entrar y volver por cada
  /// cliente que se quiere revisar; acá se recorre la cartera con un clic
  /// por ficha y la lista nunca pierde su posición ni el texto buscado.
  Widget _cuerpoEscritorio(
    BuildContext context, {
    required Widget filtro,
    required Widget buscador,
  }) {
    final anchoMaestro = esEscritorioAncho(context) ? 420.0 : 360.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: anchoMaestro,
          decoration: const BoxDecoration(
            border: Border(
              right: BorderSide(color: AppColors.surfaceMuted, width: 1.2),
            ),
          ),
          child: Column(
            children: [
              filtro,
              buscador,
              Expanded(child: _listaEscritorio()),
            ],
          ),
        ),
        Expanded(
          child: ContenidoCentrado(
            anchoMaximo: 960,
            child: _detalleEscritorio(),
          ),
        ),
      ],
    );
  }

  Widget _listaEscritorio() {
    if (_cargando) return const _EsqueletoListaClientes();

    if (_error != null) {
      return EstadoError(mensaje: _error!, onReintentar: _cargarClientes);
    }

    final clientes = _clientesFiltrados;
    if (clientes.isEmpty) return _estadoVacio();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      itemCount: clientes.length,
      itemBuilder: (context, index) {
        final cliente = clientes[index];
        return _FilaClienteEscritorio(
              cliente: cliente,
              seleccionada: _seleccionado?.idCliente == cliente.idCliente,
              onTap: () => setState(() => _seleccionado = cliente),
              onAcciones: () => _abrirAcciones(cliente),
            )
            .animate(delay: (20 * index).ms)
            .fadeIn(duration: 220.ms)
            .moveY(begin: 6, end: 0);
      },
    );
  }

  Widget _detalleEscritorio() {
    final seleccionado = _seleccionado;
    if (seleccionado == null) {
      return const EstadoVacio(
        icono: Icons.badge_outlined,
        titulo: 'Elige un cliente de la lista',
        subtitulo:
            'Su historial de compras, segmento, puntos de fidelidad y notas '
            'internas se abren acá mismo, sin salir de la lista.',
      );
    }

    // La llave por id fuerza un estado nuevo al cambiar de cliente: así la
    // ficha se recarga sola en vez de quedarse con los datos del anterior.
    return ClientePerfilVista(
      key: ValueKey(seleccionado.idCliente),
      idCliente: seleccionado.idCliente,
      clienteInicial: seleccionado,
      embebido: true,
      onCambio: _cargarClientes,
    );
  }

  EstadoVacio _estadoVacio() {
    final sinBusqueda = _filtroIndice == 0
        ? 'Aún no hay clientes registrados'
        : 'No hay clientes desactivados';
    return EstadoVacio(
      icono: _busqueda.isEmpty
          ? Icons.people_outline_rounded
          : Icons.search_off_rounded,
      titulo: _busqueda.isEmpty ? sinBusqueda : 'No se encontraron clientes',
      subtitulo: _busqueda.isEmpty
          ? 'Los clientes que registres van a aparecer acá.'
          : 'Prueba con otro nombre, razón social, RUC o DNI.',
      onRefrescar: _cargarClientes,
    );
  }

  Widget _construirCuerpo() {
    if (_cargando) {
      return const Center(child: AppLoadingIndicator());
    }

    if (_error != null) {
      return EstadoError(mensaje: _error!, onReintentar: _cargarClientes);
    }

    final clientes = _clientesFiltrados;

    if (clientes.isEmpty) {
      final sinBusqueda = _filtroIndice == 0
          ? 'Aún no hay clientes registrados'
          : 'No hay clientes desactivados';
      return EstadoVacio(
        icono: _busqueda.isEmpty
            ? Icons.people_outline_rounded
            : Icons.search_off_rounded,
        titulo: _busqueda.isEmpty
            ? sinBusqueda
            : 'No se encontraron clientes',
        subtitulo: _busqueda.isEmpty
            ? 'Los clientes que registres van a aparecer acá.'
            : 'Prueba con otro nombre, razón social, RUC o DNI.',
        onRefrescar: _cargarClientes,
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

/// Fila del maestro en escritorio. Más densa que [ClienteCard] (que es una
/// tarjeta con sombra pensada para el dedo): sin sombra, con estado
/// seleccionado, resaltado al pasar el mouse y un botón de acciones a la
/// derecha — el clic en la fila abre la ficha en el panel de al lado, el
/// botón abre el menú de siempre (llamar, WhatsApp, editar, desactivar).
class _FilaClienteEscritorio extends StatelessWidget {
  const _FilaClienteEscritorio({
    required this.cliente,
    required this.seleccionada,
    required this.onTap,
    required this.onAcciones,
  });

  final Cliente cliente;
  final bool seleccionada;
  final VoidCallback onTap;
  final VoidCallback onAcciones;

  static const _colorReniec = Color(0xFF2563EB);
  static const _colorManual = Color(0xFFEA8C1B);
  static const _colorSinDni = Color(0xFFDC2626);

  Color get _color {
    switch (cliente.calidadDato) {
      case CalidadDato.reniec:
        return _colorReniec;
      case CalidadDato.manual:
        return _colorManual;
      case CalidadDato.sinDni:
        return _colorSinDni;
    }
  }

  IconData get _iconoTipo {
    switch (cliente.tipoDocumento) {
      case TipoClienteDocumento.dni:
        return Icons.person_rounded;
      case TipoClienteDocumento.rucPersonaNatural:
        return Icons.storefront_rounded;
      case TipoClienteDocumento.rucPersonaJuridica:
        return Icons.apartment_rounded;
      case TipoClienteDocumento.sinDocumento:
        return Icons.person_outline_rounded;
    }
  }

  String get _documento {
    switch (cliente.tipoDocumento) {
      case TipoClienteDocumento.dni:
        return cliente.dni != null ? 'DNI ${cliente.dni}' : 'Sin DNI';
      case TipoClienteDocumento.rucPersonaNatural:
      case TipoClienteDocumento.rucPersonaJuridica:
        return 'RUC ${cliente.dni}';
      case TipoClienteDocumento.sinDocumento:
        return 'Sin documento';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _color;
    final comercial = cliente.esNegocio ? cliente.nombreComercial : null;
    final telefono = cliente.telefono;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: FilaTabla(
        onTap: onTap,
        seleccionada: seleccionada,
        acento: color,
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    color.withValues(alpha: 0.20),
                    color.withValues(alpha: 0.08),
                  ],
                ),
                border: Border.all(color: color.withValues(alpha: 0.35)),
              ),
              child: Icon(_iconoTipo, color: color, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cliente.nombreParaMostrar,
                    style: theme.textTheme.titleMedium?.copyWith(fontSize: 14.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (comercial != null && comercial.trim().isNotEmpty)
                    Text(
                      comercial,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.secondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 2),
                  // Dos datos por fila en vez de uno: con mouse y esta
                  // densidad se barre la cartera mucho más rápido.
                  Text(
                    telefono != null && telefono.trim().isNotEmpty
                        ? '$_documento · $telefono'
                        : _documento,
                    style: theme.textTheme.bodyMedium?.copyWith(fontSize: 11.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
            IconButton(
              onPressed: onAcciones,
              icon: const Icon(Icons.more_vert_rounded, size: 18),
              tooltip: 'Acciones',
              color: AppColors.textSecondary,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

/// Esqueleto de la lista maestra mientras carga: filas en shimmer con la
/// misma altura que las reales, para que no salte nada al llegar los datos.
class _EsqueletoListaClientes extends StatelessWidget {
  const _EsqueletoListaClientes();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      itemCount: 8,
      itemBuilder: (context, index) => const Padding(
        padding: EdgeInsets.fromLTRB(12, 10, 6, 12),
        child: Row(
          children: [
            SkeletonBox(width: 40, height: 40, borderRadius: 20),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 150, height: 13),
                  SizedBox(height: 8),
                  SkeletonBox(width: 110, height: 10),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
