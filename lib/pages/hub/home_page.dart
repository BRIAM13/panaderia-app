import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../models/usuario_sesion.dart';
import '../../services/auth_service.dart';
import '../../services/notificaciones_service.dart';
import '../../services/tiendas_service.dart';
import '../../widgets/ad_banner.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/proximamente_sheet.dart';
import '../../widgets/tienda_card.dart';
import '../auth/login_page.dart';
import '../hamburguesas/dashboard_page.dart';
import '../hamburguesas/hamburguesas_gestion_page.dart';
import '../hamburguesas/trabajadores_page.dart';
import '../perfil/mi_perfil_page.dart';
import '../tiendas/tienda_placeholder_page.dart';
import 'hacer_pedido_page.dart';
import 'mis_deudas_page.dart';
import 'mis_pedidos_pendientes_view.dart';

class _Tienda {
  const _Tienda({
    required this.nombre,
    required this.icono,
    required this.disponible,
  });

  final String nombre;
  final IconData icono;
  final bool disponible;
}

const _tiendas = [
  _Tienda(
    nombre: 'Hamburguesas',
    icono: Icons.lunch_dining_rounded,
    disponible: true,
  ),
  _Tienda(
    nombre: 'Horneados',
    icono: Icons.bakery_dining_rounded,
    disponible: true,
  ),
  _Tienda(
    nombre: 'Panadería',
    icono: Icons.breakfast_dining_rounded,
    disponible: false,
  ),
  _Tienda(
    nombre: 'Mercadería',
    icono: Icons.storefront_rounded,
    disponible: false,
  ),
  _Tienda(nombre: 'Pastelería', icono: Icons.cake_rounded, disponible: false),
];

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.usuario});

  final UsuarioSesion usuario;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _authService = AuthService();
  final _notificacionesService = NotificacionesService();
  final _tiendasService = TiendasService();
  final _misPedidosKey = GlobalKey<MisPedidosPendientesViewState>();
  late bool _vistaTrabajador;

  /// Slugs de las tiendas a las que este trabajador/admin tiene acceso
  /// vigente — controla qué entradas de "Gestionar X" ve en el drawer.
  /// SUPERADMIN las recibe todas desde el backend sin necesitar asignación.
  Set<String> _misSlugsTiendas = {};

  @override
  void initState() {
    super.initState();
    // El personal puro (no híbrido) siempre parte en su vista de gestión;
    // un cliente puro siempre parte en la vista de cliente. Solo el
    // usuario híbrido puede alternar libremente entre ambas.
    _vistaTrabajador =
        widget.usuario.esPersonalDeGestion && !widget.usuario.esCliente;
    // Registrar el token de notificaciones push una vez por sesión, ya con
    // el usuario autenticado (HomePage es la raíz de la sesión).
    _notificacionesService.inicializarYRegistrar();
    if (widget.usuario.esPersonalDeGestion) _cargarMisTiendas();
  }

  Future<void> _cargarMisTiendas() async {
    try {
      final tiendas = await _tiendasService.misTiendas();
      if (!mounted) return;
      setState(() => _misSlugsTiendas = tiendas.map((t) => t.slug).toSet());
    } catch (_) {
      // Silencioso: si falla, el drawer simplemente no muestra ninguna
      // entrada de gestión hasta que se pueda recargar (ej. sin conexión).
    }
  }

  void _abrirTienda(_Tienda tienda) {
    if (tienda.disponible) {
      pushSlideUpFade(
        context,
        (context) => TiendaPlaceholderPage(
          nombreTienda: tienda.nombre,
          icono: tienda.icono,
        ),
      );
    } else {
      showProximamenteSheet(
        context,
        nombreTienda: tienda.nombre,
        icono: tienda.icono,
      );
    }
  }

  void _abrirGestionHamburguesas() {
    pushSlideUpFade(
      context,
      (context) => HamburguesasGestionPage(usuario: widget.usuario),
    );
  }

  void _abrirMiPerfil() {
    pushSlideUpFade(context, (context) => const MiPerfilPage());
  }

  void _abrirMisPedidos() {
    pushSlideUpFade(context, (context) => const MisPedidosPendientesPage());
  }

  void _abrirMisDeudas() {
    pushSlideUpFade(context, (context) => const MisDeudasPage());
  }

  void _abrirTrabajadores() {
    pushSlideUpFade(context, (context) => const TrabajadoresPage());
  }

  Future<void> _hacerPedido() async {
    final registrado = await pushSlideUpFade<bool>(
      context,
      (context) => const HacerPedidoPage(),
    );
    if (registrado == true) _misPedidosKey.currentState?.recargar();
  }

  void _abrirGestion(String nombre, IconData icono) {
    pushSlideUpFade(
      context,
      (context) => TiendaPlaceholderPage(
        nombreTienda: nombre,
        icono: icono,
        titulo: nombre,
        mensaje:
            'Estamos preparando las herramientas de gestión para tu equipo. Muy pronto estarán aquí.',
      ),
    );
  }

  Future<void> _cerrarSesion() async {
    Navigator.of(context).pop(); // cierra el drawer
    await _authService.cerrarSesion();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      SlideUpFadeRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usuario = widget.usuario;

    // El Hub es la raíz de la sesión autenticada: el botón/gesto de
    // retroceso nunca debe devolver al usuario al Login (algunos caminos,
    // como el cambio de clave obligatorio, sí dejan Login en el stack).
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(title: const Text('Corporación Ronceros')),
        drawer: AppDrawer(
          usuario: usuario,
          vistaTrabajador: _vistaTrabajador,
          misSlugsTiendas: _misSlugsTiendas,
          onCambiarVista: (valor) => setState(() => _vistaTrabajador = valor),
          onAbrirGestion: _abrirGestion,
          onAbrirHamburguesas: _abrirGestionHamburguesas,
          onAbrirMiPerfil: _abrirMiPerfil,
          onAbrirMisPedidos: _abrirMisPedidos,
          onAbrirMisDeudas: _abrirMisDeudas,
          onAbrirTrabajadores: _abrirTrabajadores,
          onCerrarSesion: _cerrarSesion,
        ),
        floatingActionButton: _vistaTrabajador
            ? null
            : FloatingActionButton.extended(
                onPressed: _hacerPedido,
                icon: const Icon(Icons.add_shopping_cart_rounded),
                label: const Text('Hacer pedido'),
              ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: _vistaTrabajador
                    ? (usuario.rol == 'ADMIN' || usuario.rol == 'SUPERADMIN'
                          ? DashboardPage(usuario: usuario)
                          : _construirGridTiendas(theme, usuario))
                    : MisPedidosPendientesView(key: _misPedidosKey),
              ),
              if (!_vistaTrabajador) const AdBanner(),
            ],
          ),
        ),
      ),
    );
  }

  /// Vista de personal: hub "Elige tu tienda" para acceder a gestión. La
  /// vista cliente ya no usa este grid — su pantalla principal son sus
  /// pedidos pendientes (ver [MisPedidosPendientesView]).
  Widget _construirGridTiendas(ThemeData theme, UsuarioSesion usuario) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bienvenido, ${usuario.nombreCompleto}',
                  style: theme.textTheme.bodyMedium,
                ).animate().fadeIn(duration: 300.ms).moveY(begin: 6, end: 0),
                const SizedBox(height: 4),
                Text('Elige tu tienda', style: theme.textTheme.titleLarge)
                    .animate()
                    .fadeIn(delay: 60.ms, duration: 300.ms)
                    .moveY(begin: 6, end: 0),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.92,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final tienda = _tiendas[index];
              return TiendaCard(
                    nombre: tienda.nombre,
                    icono: tienda.icono,
                    disponible: tienda.disponible,
                    onTap: () => _abrirTienda(tienda),
                  )
                  .animate(delay: (80 * index).ms)
                  .fadeIn(duration: 380.ms, curve: Curves.easeOut)
                  .moveY(begin: 24, end: 0, curve: Curves.easeOutCubic)
                  .scale(
                    begin: const Offset(0.94, 0.94),
                    end: const Offset(1, 1),
                  );
            }, childCount: _tiendas.length),
          ),
        ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
      ],
    );
  }
}
