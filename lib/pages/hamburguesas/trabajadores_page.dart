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
import '../../widgets/estado_error.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/page_transitions.dart';
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
    return Scaffold(
      appBar: AppBar(title: const Text('Trabajadores')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nuevoTrabajador,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Nuevo trabajador'),
      ),
      body: SafeArea(child: _construirCuerpo()),
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
