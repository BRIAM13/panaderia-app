import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../models/usuario_sesion.dart';
import '../../services/auth_service.dart';
import '../../services/notificaciones_service.dart';
import '../../services/tiendas_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../widgets/ad_banner.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/page_transitions.dart';
import '../auth/login_page.dart';
import '../hamburguesas/dashboard_page.dart';
import '../hamburguesas/hamburguesas_gestion_page.dart';
import '../hamburguesas/trabajadores_page.dart';
import '../perfil/mi_perfil_page.dart';
import '../sistema/token_api_peru_page.dart';
import '../tiendas/tienda_placeholder_page.dart';
import 'hacer_pedido_page.dart';
import 'mis_deudas_page.dart';
import 'mis_pedidos_pendientes_view.dart';

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

  /// Slugs de las tiendas a las que este trabajador/admin tiene acceso
  /// vigente — controla qué entradas de "Gestionar X" ve en el drawer.
  /// SUPERADMIN las recibe todas desde el backend sin necesitar asignación.
  Set<String> _misSlugsTiendas = {};

  @override
  void initState() {
    super.initState();
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

  void _abrirGestionHamburguesas() {
    pushSlideUpFade(
      context,
      (context) => HamburguesasGestionPage(usuario: widget.usuario),
    );
  }

  /// El anuncio solo existe para monetizar a quienes SOLO son clientes —
  /// un trabajador que también es cliente no lo ve al entrar a estos
  /// mismos apartados desde su drawer.
  bool get _esClientePuro => !widget.usuario.esPersonalDeGestion;

  void _abrirMiPerfil() {
    pushSlideUpFade(
      context,
      (context) => MiPerfilPage(mostrarAnuncio: _esClientePuro),
    );
  }

  void _abrirMisPedidos() {
    pushSlideUpFade(
      context,
      (context) => MisPedidosPendientesPage(mostrarAnuncio: _esClientePuro),
    );
  }

  void _abrirMisDeudas() {
    pushSlideUpFade(
      context,
      (context) => MisDeudasPage(mostrarAnuncio: _esClientePuro),
    );
  }

  void _abrirTrabajadores() {
    pushSlideUpFade(context, (context) => const TrabajadoresPage());
  }

  void _abrirTokenApiPeru() {
    pushSlideUpFade(context, (context) => const TokenApiPeruPage());
  }

  Future<void> _hacerPedido() async {
    final registrado = await pushSlideUpFade<bool>(
      context,
      (context) => HacerPedidoPage(mostrarAnuncio: _esClientePuro),
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
    final usuario = widget.usuario;
    // El personal (trabajador/admin/superadmin) siempre parte en su vista
    // de gestión, sea o no también cliente — ver a un cliente que además
    // trabaja ahí no debe cambiarle su pantalla principal. Sus apartados
    // de cliente (Mis pedidos, Mis deudas, Hacer pedido) quedan en el
    // drawer, no reemplazando el Dashboard/hub de tiendas.
    final vistaTrabajador = usuario.esPersonalDeGestion;
    // A partir de este ancho, el drawer deja de ser un overlay deslizante
    // y pasa a mostrarse siempre visible como panel lateral — en una
    // ventana de escritorio ancha, un menú que hay que "abrir" con un
    // ícono se ve fuera de lugar cuando sobra espacio de sobra para
    // tenerlo siempre ahí.
    final esEscritorio =
        MediaQuery.sizeOf(context).width >= Breakpoints.escritorio;

    final contenidoMenu = AppDrawerContenido(
      usuario: usuario,
      misSlugsTiendas: _misSlugsTiendas,
      onAbrirGestion: _abrirGestion,
      onAbrirHamburguesas: _abrirGestionHamburguesas,
      onAbrirMiPerfil: _abrirMiPerfil,
      onAbrirMisPedidos: _abrirMisPedidos,
      onAbrirMisDeudas: _abrirMisDeudas,
      onHacerPedido: _hacerPedido,
      onAbrirTrabajadores: _abrirTrabajadores,
      onAbrirTokenApiPeru: _abrirTokenApiPeru,
      onCerrarSesion: _cerrarSesion,
    );

    final cuerpo = SafeArea(
      bottom: vistaTrabajador,
      // El Dashboard de su tienda es la pantalla principal para TODO el
      // personal (Trabajador/Admin/Superadmin) — antes solo lo veían
      // Admin/Superadmin, y un Trabajador raso caía al grid genérico
      // "Elige tu tienda". El propio Dashboard ya distingue el rol para
      // decidir qué se puede tocar (ej. "Ventas de hoy").
      child: vistaTrabajador
          ? DashboardPage(usuario: usuario)
          : MisPedidosPendientesView(key: _misPedidosKey),
    );

    // El Hub es la raíz de la sesión autenticada: el botón/gesto de
    // retroceso nunca debe devolver al usuario al Login (algunos caminos,
    // como el cambio de clave obligatorio, sí dejan Login en el stack).
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Corporación Ronceros'),
          // Sin esto, en escritorio (sin drawer) el AppBar igual reserva el
          // hueco del ícono de menú a la izquierda, dejando el título
          // descentrado sin motivo.
          automaticallyImplyLeading: !esEscritorio,
        ),
        drawer: esEscritorio ? null : Drawer(child: contenidoMenu),
        floatingActionButton: vistaTrabajador
            ? null
            : FloatingActionButton.extended(
                    onPressed: _hacerPedido,
                    icon: const Icon(Icons.add_shopping_cart_rounded),
                    label: const Text('Hacer pedido'),
                  )
                  .animate()
                  .fadeIn(delay: 200.ms, duration: 350.ms)
                  .scale(
                    begin: const Offset(0.7, 0.7),
                    end: const Offset(1, 1),
                    curve: Curves.easeOutBack,
                  ),
        // El banner va en bottomNavigationBar (no dentro del body) para que
        // el Scaffold acomode el FAB automáticamente encima de él — antes,
        // al estar dentro del body, el FAB flotaba sin saber cuánto espacio
        // ocupaba el banner abajo y terminaba sobreponiéndosele.
        bottomNavigationBar: vistaTrabajador ? null : const AdBanner(),
        body: esEscritorio
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 300,
                    child: Material(
                      color: AppColors.background,
                      elevation: 1,
                      child: contenidoMenu,
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: cuerpo),
                ],
              )
            : cuerpo,
      ),
    );
  }
}
