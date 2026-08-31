import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../models/rol_model.dart';
import '../../models/tienda_model.dart';
import '../../models/trabajador_model.dart';
import '../../services/api_client.dart';
import '../../services/roles_service.dart';
import '../../services/tiendas_service.dart';
import '../../services/trabajadores_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/escritorio.dart';
import '../../widgets/estado_error.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/tarjeta_3d.dart';
import 'trabajador_form_page.dart';

/// Directorio completo de trabajadores (cruzado entre tiendas): un
/// administrador de Hamburguesas ve también a los de Horneados, pero solo
/// puede otorgar/quitar acceso a SU propia tienda — así encuentra a alguien
/// ya registrado en otro lado y decide si también trabaja en la suya. Solo
/// un SUPERADMIN puede ascender/descender el rol de acceso de alguien (ver
/// _editarRol) — un ADMIN solo puede crear TRABAJADOR desde el formulario.
class TrabajadoresPage extends StatefulWidget {
  const TrabajadoresPage({super.key});

  @override
  State<TrabajadoresPage> createState() => _TrabajadoresPageState();
}

class _TrabajadoresPageState extends State<TrabajadoresPage> {
  final _trabajadoresService = TrabajadoresService();
  final _tiendasService = TiendasService();
  final _rolesService = RolesService();

  List<RolAsignable> _rolesAsignables = [];

  List<Trabajador> _trabajadores = [];
  List<Tienda> _misTiendas = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final resultados = await Future.wait([
        _trabajadoresService.listar(),
        _tiendasService.misTiendas(),
        _rolesService.asignables(),
      ]);
      setState(() {
        _trabajadores = resultados[0] as List<Trabajador>;
        _misTiendas = resultados[1] as List<Tienda>;
        _rolesAsignables = resultados[2] as List<RolAsignable>;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(() => _error = 'No se pudo cargar la lista de trabajadores.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  /// Solo se ofrece si el usuario autenticado puede asignar más de un rol
  /// (es decir, es SUPERADMIN) — un ADMIN solo puede crear TRABAJADOR, no
  /// tiene sentido que "edite" a nadie a ese mismo rol.
  bool get _puedeEditarRoles => _rolesAsignables.length > 1;

  Future<void> _editarRol(Trabajador trabajador) async {
    final nuevoRol = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Rol de ${trabajador.nombreCompleto}'),
        children: _rolesAsignables
            .map(
              (r) => RadioListTile<String>(
                value: r.nombreRol,
                groupValue: trabajador.rol,
                title: Text(r.etiqueta),
                onChanged: (v) => Navigator.of(context).pop(v),
              ),
            )
            .toList(),
      ),
    );
    if (nuevoRol == null || nuevoRol == trabajador.rol) return;

    try {
      await _trabajadoresService.cambiarRol(
        idTrabajador: trabajador.idTrabajador,
        rol: nuevoRol,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Rol de ${trabajador.nombreCompleto} actualizado.'),
        ),
      );
      _cargar();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.mensaje)));
    }
  }

  Future<void> _darDeBaja(Trabajador trabajador) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Dar de baja?'),
        content: Text(
          '${trabajador.nombreCompleto} perderá su acceso a todas las '
          'tiendas y su cuenta volverá a ser de cliente. Si tiene sesión '
          'abierta, se cerrará automáticamente. Esto se puede revertir '
          'después volviendo a registrarlo como trabajador.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Dar de baja'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await _trabajadoresService.darDeBaja(
        idTrabajador: trabajador.idTrabajador,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${trabajador.nombreCompleto} fue dado de baja.'),
        ),
      );
      _cargar();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.mensaje)));
    }
  }

  Future<void> _nuevoTrabajador() async {
    final registrado = await pushSlideUpFade<bool>(
      context,
      (_) => const TrabajadorFormPage(),
    );
    if (registrado == true) _cargar();
  }

  Future<void> _alternarAcceso(
    Trabajador trabajador,
    Tienda tienda,
    bool otorgar,
  ) async {
    try {
      if (otorgar) {
        await _trabajadoresService.otorgarAcceso(
          idTrabajador: trabajador.idTrabajador,
          idTienda: tienda.idTienda,
        );
      } else {
        await _trabajadoresService.revocarAcceso(
          idTrabajador: trabajador.idTrabajador,
          idTienda: tienda.idTienda,
        );
      }
      _cargar();
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

    return Scaffold(
      appBar: appBarGestion(
        context,
        titulo: 'Trabajadores',
        subtitulo: escritorio
            ? 'Directorio del personal y acceso por tienda'
            : null,
        acciones: [
          if (escritorio)
            FilledButton.icon(
              onPressed: _nuevoTrabajador,
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: const Text('Nuevo trabajador'),
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
      ),
      floatingActionButton: escritorio
          ? null
          : FloatingActionButton.extended(
              onPressed: _nuevoTrabajador,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Nuevo trabajador'),
            ),
      body: SafeArea(
        child: escritorio ? _cuerpoEscritorio(context) : _construirCuerpo(),
      ),
    );
  }

  Widget _construirCuerpo() {
    if (_cargando) return const Center(child: AppLoadingIndicator());

    if (_error != null) {
      return EstadoError(mensaje: _error!, onReintentar: _cargar);
    }

    if (_trabajadores.isEmpty) {
      return EstadoVacio(
        icono: Icons.badge_outlined,
        titulo: 'Aún no hay trabajadores registrados',
        subtitulo: 'El personal que agregues va a aparecer acá.',
        onRefrescar: _cargar,
      );
    }

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
        itemCount: _trabajadores.length,
        itemBuilder: (context, index) {
          final trabajador = _trabajadores[index];
          return _TrabajadorCard(
                trabajador: trabajador,
                misTiendas: _misTiendas,
                onAlternarAcceso: (tienda, otorgar) =>
                    _alternarAcceso(trabajador, tienda, otorgar),
                onEditarRol: _puedeEditarRoles
                    ? () => _editarRol(trabajador)
                    : null,
                onDarDeBaja: () => _darDeBaja(trabajador),
              )
              .animate(delay: (30 * index).ms)
              .fadeIn(duration: 250.ms)
              .moveY(begin: 8, end: 0)
              .flipH(begin: 0.12, end: 0, duration: 320.ms);
        },
      ),
    );
  }

  // ---------------------------------------------------------------------
  // ESCRITORIO
  // ---------------------------------------------------------------------

  /// Directorio como tabla en vez de tarjetas apiladas. Un administrador
  /// entra acá para comparar quién tiene acceso a qué: con las tarjetas de
  /// celular hay que leer una por una porque cada dato está en una posición
  /// distinta; en columnas alineadas se barre la lista de un vistazo.
  Widget _cuerpoEscritorio(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 56),
      children: [
        ContenidoCentrado(
          anchoMaximo: 1360,
          child: PanelEscritorio(
            icono: Icons.groups_2_rounded,
            titulo: 'Personal registrado',
            subtitulo: _misTiendas.isEmpty
                ? 'Solo puedes otorgar o quitar acceso a las tiendas que administras.'
                : 'Solo puedes otorgar o quitar acceso a: '
                      '${_misTiendas.map((t) => t.nombre).join(', ')}.',
            accion: _cargando || _error != null
                ? null
                : Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_trabajadores.length}',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: _tablaEscritorio(),
          ),
        ),
      ],
    );
  }

  Widget _tablaEscritorio() {
    if (_cargando) return const _EsqueletoTablaTrabajadores();

    if (_error != null) {
      return SizedBox(
        height: 280,
        child: EstadoError(mensaje: _error!, onReintentar: _cargar),
      );
    }

    if (_trabajadores.isEmpty) {
      return const SizedBox(
        height: 280,
        child: EstadoVacio(
          icono: Icons.badge_outlined,
          titulo: 'Aún no hay trabajadores registrados',
          subtitulo: 'El personal que agregues va a aparecer acá.',
        ),
      );
    }

    return Column(
      children: [
        const EncabezadoTabla(
          columnas: [
            ('TRABAJADOR', 4),
            ('ROL DE ACCESO', 3),
            ('ACCESO A TIENDAS', 6),
            ('', 2),
          ],
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        ),
        const SizedBox(height: 4),
        for (var i = 0; i < _trabajadores.length; i++)
          _FilaTrabajadorEscritorio(
                trabajador: _trabajadores[i],
                misTiendas: _misTiendas,
                onAlternarAcceso: (tienda, otorgar) =>
                    _alternarAcceso(_trabajadores[i], tienda, otorgar),
                onEditarRol: _puedeEditarRoles
                    ? () => _editarRol(_trabajadores[i])
                    : null,
                onDarDeBaja: () => _darDeBaja(_trabajadores[i]),
              )
              .animate(delay: (25 * i).ms)
              .fadeIn(duration: 240.ms)
              .moveY(begin: 8, end: 0),
      ],
    );
  }
}

/// Etiqueta legible + color del rol de acceso. Se comparte entre la tarjeta
/// de celular y la fila de escritorio.
({String texto, Color color}) _estiloRol(Trabajador trabajador) {
  switch (trabajador.rol) {
    case 'SUPERADMIN':
      return (texto: 'Super administrador', color: AppColors.primary);
    case 'ADMIN':
      return (texto: 'Administrador', color: AppColors.secondary);
    case 'TRABAJADOR':
      return (texto: 'Trabajador', color: const Color(0xFF2563EB));
    case 'VISITOR':
      return (texto: 'Visitante', color: AppColors.textSecondary);
    default:
      return (texto: trabajador.cargo, color: AppColors.textSecondary);
  }
}

/// Una persona del directorio, en columnas alineadas con el encabezado.
class _FilaTrabajadorEscritorio extends StatelessWidget {
  const _FilaTrabajadorEscritorio({
    required this.trabajador,
    required this.misTiendas,
    required this.onAlternarAcceso,
    required this.onDarDeBaja,
    this.onEditarRol,
  });

  final Trabajador trabajador;
  final List<Tienda> misTiendas;
  final void Function(Tienda tienda, bool otorgar) onAlternarAcceso;
  final VoidCallback onDarDeBaja;
  final VoidCallback? onEditarRol;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rol = _estiloRol(trabajador);
    final otrasTiendas = trabajador.tiendas
        .where((t) => !misTiendas.any((m) => m.idTienda == t.idTienda))
        .toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: FilaTabla(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.secondaryContainer,
                    ),
                    child: const Icon(
                      Icons.badge_outlined,
                      color: AppColors.primary,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trabajador.nombreCompleto,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 14.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'DNI ${trabajador.dni ?? '—'}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: rol.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: rol.color.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Text(
                    rol.texto,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: rol.color,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 6,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  // Tiendas que administro: interruptor real.
                  ...misTiendas.map(
                    (tienda) => _ChipTiendaConSwitch(
                      nombre: tienda.nombre,
                      activo: trabajador.tieneAccesoA(tienda.idTienda),
                      onChanged: (v) => onAlternarAcceso(tienda, v),
                    ),
                  ),
                  // Tiendas de otros administradores: solo informativo.
                  ...otrasTiendas.map(
                    (t) => Chip(
                      label: Text(
                        t.activo ? t.nombre : '${t.nombre} (inactivo)',
                      ),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      backgroundColor: AppColors.surfaceMuted,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (onEditarRol != null)
                    IconButton(
                      onPressed: onEditarRol,
                      icon: const Icon(Icons.admin_panel_settings_outlined),
                      tooltip: 'Editar rol',
                      visualDensity: VisualDensity.compact,
                    ),
                  IconButton(
                    onPressed: onDarDeBaja,
                    icon: const Icon(Icons.person_remove_outlined),
                    color: AppColors.error,
                    tooltip: 'Dar de baja',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Esqueleto de la tabla mientras llegan los datos.
class _EsqueletoTablaTrabajadores extends StatelessWidget {
  const _EsqueletoTablaTrabajadores();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const EncabezadoTabla(
          columnas: [
            ('TRABAJADOR', 4),
            ('ROL DE ACCESO', 3),
            ('ACCESO A TIENDAS', 6),
            ('', 2),
          ],
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < 6; i++)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Row(
                    children: [
                      SkeletonBox(width: 40, height: 40, borderRadius: 20),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(width: 140, height: 13),
                            SizedBox(height: 7),
                            SkeletonBox(width: 80, height: 10),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SkeletonBox(width: 110, height: 24, borderRadius: 20),
                  ),
                ),
                Expanded(
                  flex: 6,
                  child: Row(
                    children: [
                      SkeletonBox(width: 96, height: 26, borderRadius: 20),
                      SizedBox(width: 8),
                      SkeletonBox(width: 84, height: 26, borderRadius: 20),
                    ],
                  ),
                ),
                Expanded(flex: 2, child: SizedBox()),
              ],
            ),
          ),
      ],
    );
  }
}

class _TrabajadorCard extends StatelessWidget {
  const _TrabajadorCard({
    required this.trabajador,
    required this.misTiendas,
    required this.onAlternarAcceso,
    required this.onDarDeBaja,
    this.onEditarRol,
  });

  final Trabajador trabajador;
  final List<Tienda> misTiendas;
  final void Function(Tienda tienda, bool otorgar) onAlternarAcceso;
  final VoidCallback onDarDeBaja;
  final VoidCallback? onEditarRol;

  String get _etiquetaRol {
    switch (trabajador.rol) {
      case 'ADMIN':
        return 'Administrador';
      case 'SUPERADMIN':
        return 'Super administrador';
      case 'TRABAJADOR':
        return 'Trabajador';
      case 'VISITOR':
        return 'Visitante';
      default:
        return trabajador.cargo;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Tarjeta3D(
        child: Container(
          color: AppColors.surface,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.secondaryContainer,
                    ),
                    child: Icon(Icons.badge_outlined, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trabajador.nombreCompleto,
                          style: theme.textTheme.titleMedium,
                        ),
                        Text(
                          'DNI ${trabajador.dni ?? '—'} · $_etiquetaRol',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  if (onEditarRol != null)
                    IconButton(
                      onPressed: onEditarRol,
                      icon: const Icon(Icons.admin_panel_settings_outlined),
                      tooltip: 'Editar rol',
                    ),
                  IconButton(
                    onPressed: onDarDeBaja,
                    icon: const Icon(Icons.person_remove_outlined),
                    color: AppColors.error,
                    tooltip: 'Dar de baja',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  // Tiendas que administro: switch real para otorgar/revocar.
                  ...misTiendas.map((tienda) {
                    final activo = trabajador.tieneAccesoA(tienda.idTienda);
                    return _ChipTiendaConSwitch(
                      nombre: tienda.nombre,
                      activo: activo,
                      onChanged: (v) => onAlternarAcceso(tienda, v),
                    );
                  }),
                  // Tiendas de OTROS administradores donde ya trabaja: solo
                  // informativo, no se puede tocar desde aquí.
                  ...trabajador.tiendas
                      .where(
                        (t) => !misTiendas.any((m) => m.idTienda == t.idTienda),
                      )
                      .map(
                        (t) => Chip(
                          label: Text(
                            t.activo ? t.nombre : '${t.nombre} (inactivo)',
                          ),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: AppColors.surfaceMuted,
                        ),
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

class _ChipTiendaConSwitch extends StatelessWidget {
  const _ChipTiendaConSwitch({
    required this.nombre,
    required this.activo,
    required this.onChanged,
  });

  final String nombre;
  final bool activo;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final color = activo ? const Color(0xFF2E7D32) : AppColors.textSecondary;
    return InkWell(
      onTap: () => onChanged(!activo),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              activo
                  ? Icons.check_circle_rounded
                  : Icons.add_circle_outline_rounded,
              size: 16,
              color: color,
            ),
            const SizedBox(width: 6),
            Text(
              nombre,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
