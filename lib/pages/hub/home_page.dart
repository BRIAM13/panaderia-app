import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../models/tienda_model.dart';
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
import '../hamburguesas/ajuste_costos_page.dart';
import '../hamburguesas/analitica_page.dart';
import '../hamburguesas/clientes_page.dart';
import '../hamburguesas/dashboard_page.dart';
import '../hamburguesas/deudas_page.dart';
import '../hamburguesas/medios_pago_page.dart';
import '../hamburguesas/nuevo_pedido_page.dart';
import '../hamburguesas/pedidos_page.dart';
import '../hamburguesas/trabajadores_page.dart';
import '../horneados/horneados_home_page.dart';
import '../panaderia/ajuste_precios_page.dart';
import '../panaderia/horarios_pedido_page.dart';
import '../perfil/mi_perfil_page.dart';
import '../sistema/token_api_peru_page.dart';
import '../sistema/version_app_page.dart';
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
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Tiendas a las que este trabajador/admin tiene acceso vigente — controla
  /// qué entradas de "Gestionar X" ve en el drawer, y le da a cada callback
  /// `_abrirXHamburguesas`/`_abrirXPanaderia` el objeto `Tienda` que sus
  /// páginas necesitan (esas páginas abren directo desde el drawer, sin
  /// pasar por el Dashboard, que carga su propia lista por separado).
  /// SUPERADMIN las recibe todas desde el backend sin necesitar asignación.
  List<Tienda> _misTiendas = [];

  Set<String> get _misSlugsTiendas =>
      _misTiendas.map((t) => t.slug).toSet();

  Tienda? _buscarMiTienda(String slug) {
    for (final t in _misTiendas) {
      if (t.slug == slug) return t;
    }
    return null;
  }

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
      setState(() => _misTiendas = tiendas);
    } catch (_) {
      // Silencioso: si falla, el drawer simplemente no muestra ninguna
      // entrada de gestión hasta que se pueda recargar (ej. sin conexión).
    }
  }

  /// Vuelve directo al Dashboard sin importar cuántas pantallas se hayan
  /// abierto encima — es el equivalente de "Inicio" en cualquier app: un
  /// solo toque desde donde sea, sin ir cerrando pantalla por pantalla.
  /// Usa `_scaffoldKey` (no `Scaffold.of(context)`) porque este método vive
  /// en el `State` de `HomePage`, cuyo `context` queda POR ENCIMA del
  /// `Scaffold` que arma su propio `build()` — `Scaffold.of` no encuentra
  /// un descendiente, necesita un ancestro.
  void _irAInicio() {
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      _scaffoldKey.currentState?.closeDrawer();
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _abrirClientesHamburguesas() {
    pushSlideUpFade(
      context,
      (context) => ClientesPage(usuario: widget.usuario),
    );
  }

  void _abrirPedidosHamburguesas() {
    final tienda = _buscarMiTienda('hamburguesas');
    if (tienda == null) return;
    pushSlideUpFade(context, (context) => PedidosPage(tienda: tienda));
  }

  void _abrirNuevoPedidoHamburguesas() {
    final tienda = _buscarMiTienda('hamburguesas');
    if (tienda == null) return;
    pushSlideUpFade(context, (context) => NuevoPedidoPage(tienda: tienda));
  }

  void _abrirDeudasHamburguesas() {
    final tienda = _buscarMiTienda('hamburguesas');
    if (tienda == null) return;
    pushSlideUpFade(context, (context) => DeudasPage(tienda: tienda));
  }

  void _abrirMediosPagoHamburguesas() {
    pushSlideUpFade(context, (context) => const MediosPagoPage());
  }

  void _abrirAjusteCostosHamburguesas() {
    pushSlideUpFade(context, (context) => const AjusteCostosPage());
  }

  void _abrirPedidosPanaderia() {
    final tienda = _buscarMiTienda('panaderia');
    if (tienda == null) return;
    pushSlideUpFade(context, (context) => PedidosPage(tienda: tienda));
  }

  void _abrirNuevoPedidoPanaderia() {
    final tienda = _buscarMiTienda('panaderia');
    if (tienda == null) return;
    pushSlideUpFade(context, (context) => NuevoPedidoPage(tienda: tienda));
  }

  void _abrirDeudasPanaderia() {
    final tienda = _buscarMiTienda('panaderia');
    if (tienda == null) return;
    pushSlideUpFade(context, (context) => DeudasPage(tienda: tienda));
  }

  void _abrirAjustePreciosPanaderia() {
    final tienda = _buscarMiTienda('panaderia');
    if (tienda == null) return;
    pushSlideUpFade(context, (context) => AjustePreciosPage(tienda: tienda));
  }

  void _abrirHorariosPanaderia() {
    pushSlideUpFade(context, (context) => const HorariosPedidoPage());
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

  void _abrirAnalitica() {
    pushSlideUpFade(
      context,
      (context) => AnaliticaPage(usuario: widget.usuario),
    );
  }

  void _abrirTrabajadores() {
    pushSlideUpFade(context, (context) => const TrabajadoresPage());
  }

  void _abrirTokenApiPeru() {
    pushSlideUpFade(context, (context) => const TokenApiPeruPage());
  }

  void _abrirVersionApp() {
    pushSlideUpFade(context, (context) => const VersionAppPage());
  }

  Future<void> _hacerPedido() async {
    final registrado = await pushSlideUpFade<bool>(
      context,
      (context) => HacerPedidoPage(mostrarAnuncio: _esClientePuro),
    );
    if (registrado == true) _misPedidosKey.currentState?.recargar();
  }

  void _abrirGestion(String nombre, IconData icono) {
    // Horneados ya tiene su propia pantalla de gestión (por ahora, solo
    // "Registrar pedido") — el resto de tiendas sigue cayendo al
    // placeholder genérico hasta que se construyan.
    if (nombre == 'Horneados') {
      pushSlideUpFade(context, (context) => const HorneadosHomePage());
      return;
    }
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
      onIrAInicio: _irAInicio,
      onAbrirGestion: _abrirGestion,
      onAbrirClientesHamburguesas: _abrirClientesHamburguesas,
      onAbrirPedidosHamburguesas: _abrirPedidosHamburguesas,
      onAbrirNuevoPedidoHamburguesas: _abrirNuevoPedidoHamburguesas,
      onAbrirDeudasHamburguesas: _abrirDeudasHamburguesas,
      onAbrirMediosPagoHamburguesas: _abrirMediosPagoHamburguesas,
      onAbrirAjusteCostosHamburguesas: _abrirAjusteCostosHamburguesas,
      onAbrirPedidosPanaderia: _abrirPedidosPanaderia,
      onAbrirNuevoPedidoPanaderia: _abrirNuevoPedidoPanaderia,
      onAbrirDeudasPanaderia: _abrirDeudasPanaderia,
      onAbrirAjustePreciosPanaderia: _abrirAjustePreciosPanaderia,
      onAbrirHorariosPanaderia: _abrirHorariosPanaderia,
      onAbrirMiPerfil: _abrirMiPerfil,
      onAbrirMisPedidos: _abrirMisPedidos,
      onAbrirMisDeudas: _abrirMisDeudas,
      onAbrirAnalitica: _abrirAnalitica,
      onAbrirTrabajadores: _abrirTrabajadores,
      onAbrirTokenApiPeru: _abrirTokenApiPeru,
      onAbrirVersionApp: _abrirVersionApp,
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
    // En un monitor grande el panel lateral puede respirar un poco más sin
    // robarle ancho útil al contenido; en 900–1400 se queda en 300 para no
    // dejar el tablero apretado.
    final anchoPanel =
        MediaQuery.sizeOf(context).width >= Breakpoints.escritorioAncho
        ? 320.0
        : 300.0;

    return PopScope(
      canPop: false,
      child: Scaffold(
        key: _scaffoldKey,
        // En escritorio la barra superior deja de ser un título centrado
        // (patrón de celular, donde compite con el ícono de menú) y pasa a
        // ser la barra de marca del shell: logotipo + nombre + contexto de
        // la sesión, alineados a la izquierda y separados del contenido por
        // una línea fina, como cualquier panel de administración web.
        appBar: esEscritorio
            ? _barraEscritorio(vistaTrabajador: vistaTrabajador)
            : AppBar(title: const Text('Panadería Ronceros')),
        drawer: esEscritorio ? null : Drawer(child: contenidoMenu),
        floatingActionButton: vistaTrabajador
            ? null
            : FloatingActionButton.extended(
                    onPressed: _hacerPedido,
                    icon: PhosphorIcon(PhosphorIconsBold.shoppingCartSimple),
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
        // En escritorio, el mismo drawer (mismo diseño que en celular) se
        // muestra siempre visible como panel lateral en vez de un overlay
        // que hay que abrir con un ícono — el resto del contenido usa
        // TODO el ancho restante, sin ningún tope artificial (cada pantalla
        // decide si se centra con un techo de ancho o no).
        body: esEscritorio
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // El panel deja de ser un bloque plano del mismo color que
                  // el contenido: degradado vertical suave, borde derecho
                  // fino y una sombra que lo separa del tablero. Sin eso, en
                  // pantalla ancha el menú y el contenido se leían como una
                  // sola superficie continua y costaba ubicar dónde termina
                  // la navegación y dónde empieza el trabajo.
                  Container(
                    width: anchoPanel,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [AppColors.surface, AppColors.background],
                      ),
                      border: const Border(
                        right: BorderSide(
                          color: AppColors.surfaceMuted,
                          width: 1.2,
                        ),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 18,
                          offset: const Offset(4, 0),
                        ),
                      ],
                    ),
                    child: contenidoMenu,
                  ),
                  Expanded(child: cuerpo),
                ],
              )
            : cuerpo,
      ),
    );
  }

  /// Barra superior del shell de escritorio. Vive acá (y no en el `build`)
  /// solo para no engrosar más ese método, ya bastante largo.
  PreferredSizeWidget _barraEscritorio({required bool vistaTrabajador}) {
    return AppBar(
      automaticallyImplyLeading: false,
      centerTitle: false,
      titleSpacing: 24,
      toolbarHeight: 72,
      shape: const Border(
        bottom: BorderSide(color: AppColors.surfaceMuted, width: 1.2),
      ),
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primary, AppColors.secondary],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.28),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: const Icon(
              PhosphorIconsFill.bread,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Panadería Ronceros',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                vistaTrabajador ? 'Panel de gestión' : 'Mi cuenta',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
        ],
      ).animate().fadeIn(duration: 300.ms).moveX(begin: -8, end: 0),
    );
  }
}
