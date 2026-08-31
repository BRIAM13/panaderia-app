import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../models/tienda_model.dart';
import '../../models/tienda_resumen_model.dart';
import '../../models/usuario_sesion.dart';
import '../../services/api_client.dart';
import '../../services/notificaciones_service.dart';
import '../../services/tiendas_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/contador_animado.dart';
import '../../widgets/escritorio.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/premium_button.dart';
import '../../widgets/selector_desplegable.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/tarjeta_3d.dart';
import '../horneados/deudas_horneados_page.dart';
import '../horneados/nuevo_pedido_horneados_page.dart';
import '../horneados/pedidos_horneados_page.dart';
import 'deudas_page.dart';
import 'historial_ventas_page.dart';
import 'nuevo_pedido_page.dart';
import 'pedidos_page.dart';

/// Landing del ADMIN/SUPERADMIN al entrar en su vista de personal: un
/// resumen del negocio con gráficos, de un vistazo — reemplaza el grid
/// genérico "Elige tu tienda" para estos roles. Se actualiza solo cuando
/// llega una notificación push de cambio de pedido (mismo mecanismo que
/// los dashboards de Pedidos/Mis pedidos).
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.usuario});

  final UsuarioSesion usuario;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _tiendasService = TiendasService();
  StreamSubscription<void>? _suscripcionPush;

  bool _cargando = true;
  String? _error;
  List<Tienda> _tiendas = [];
  Tienda? _tiendaSeleccionada;
  TiendaResumen? _resumen;

  @override
  void initState() {
    super.initState();
    _cargarTiendas();
    // Recarga sola apenas cambia algún pedido/pago relevante — sin esto,
    // el panel se quedaba mostrando cifras viejas hasta refrescar a mano.
    _suscripcionPush = NotificacionesService.eventosPedido.listen(
      (_) => _cargarResumen(silencioso: true),
    );
  }

  @override
  void dispose() {
    _suscripcionPush?.cancel();
    super.dispose();
  }

  /// Este Dashboard es tienda-agnóstico (el selector de abajo puede apuntar
  /// a cualquier tienda asignada), pero Horneados tiene endpoints y pantallas
  /// propias (campos custom — carne, presentación, aderezo) — sin esta rama,
  /// tocar cualquiera de esas tarjetas con Horneados seleccionado abría la
  /// pantalla de catálogo simple (vacía para Horneados, o mezclando datos de
  /// la tienda equivocada). El resto (Hamburguesas, Panadería) comparte las
  /// mismas páginas, parametrizadas por `_tiendaSeleccionada`.
  bool get _esHorneados => _tiendaSeleccionada?.slug == 'horneados';

  void _abrirPedidos() {
    if (_esHorneados) {
      pushSlideUpFade(context, (_) => const PedidosHorneadosPage());
      return;
    }
    final tienda = _tiendaSeleccionada;
    if (tienda == null) return;
    pushSlideUpFade(context, (_) => PedidosPage(tienda: tienda));
  }

  /// Acceso directo a registrar un pedido nuevo desde el propio Dashboard —
  /// antes solo se llegaba entrando primero a Pedidos y tocando su botón
  /// flotante, dos pasos que no eran obvios para quien recién entra.
  Future<void> _abrirNuevoPedido() async {
    if (_esHorneados) {
      final registrado = await pushSlideUpFade<bool>(
        context,
        (_) => const NuevoPedidoHorneadosPage(),
      );
      if (registrado == true) _cargarResumen();
      return;
    }
    final tienda = _tiendaSeleccionada;
    if (tienda == null) return;
    final registrado = await pushSlideUpFade<bool>(
      context,
      (_) => NuevoPedidoPage(tienda: tienda),
    );
    if (registrado == true) _cargarResumen();
  }

  void _abrirDeudas() {
    if (_esHorneados) {
      pushSlideUpFade(context, (_) => const DeudasHorneadosPage());
      return;
    }
    final tienda = _tiendaSeleccionada;
    if (tienda == null) return;
    pushSlideUpFade(context, (_) => DeudasPage(tienda: tienda));
  }

  /// Solo Admin/Superadmin pueden entrar al historial completo de ventas —
  /// un Trabajador raso ve la tarjeta "Ventas de hoy" igual, pero no puede
  /// tocarla (ver [_esGestorDeVentas] y su uso en build()).
  bool get _esGestorDeVentas =>
      widget.usuario.rol == 'ADMIN' || widget.usuario.rol == 'SUPERADMIN';

  void _abrirHistorialVentas() {
    final tienda = _tiendaSeleccionada;
    if (tienda == null) return;
    pushSlideUpFade(context, (_) => HistorialVentasPage(tienda: tienda));
  }

  Future<void> _cargarTiendas() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final tiendas = await _tiendasService.misTiendas();
      setState(() {
        _tiendas = tiendas;
        _tiendaSeleccionada = tiendas.isNotEmpty ? tiendas.first : null;
      });
      if (_tiendaSeleccionada != null) await _cargarResumen();
    } on ApiException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(() => _error = 'No se pudieron cargar tus tiendas.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _cargarResumen({bool silencioso = false}) async {
    if (_tiendaSeleccionada == null) return;
    if (!silencioso) {
      setState(() {
        _cargando = true;
        _error = null;
      });
    }
    try {
      // Sin `fecha`: el backend usa hoy — el detalle día por día (con
      // selector de fecha) vive en Historial de ventas, no acá.
      final resumen = await _tiendasService.resumen(
        _tiendaSeleccionada!.idTienda,
      );
      if (mounted) setState(() => _resumen = resumen);
    } on ApiException catch (e) {
      if (!silencioso) setState(() => _error = e.mensaje);
    } catch (_) {
      if (!silencioso) {
        setState(() => _error = 'No se pudo cargar el resumen de la tienda.');
      }
    } finally {
      if (mounted && !silencioso) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_cargando && _resumen == null) {
      // En escritorio la primera carga muestra el ESQUELETO del tablero
      // (mismo layout, en shimmer) en vez de un spinner centrado en medio de
      // un océano de fondo vacío: la pantalla ya cuenta qué va a llegar y
      // dónde, así que el salto al contenido real no reacomoda nada.
      if (esEscritorio(context)) return const _EsqueletoTableroEscritorio();
      return const Center(child: AppLoadingIndicator());
    }

    if (_error != null && _resumen == null) {
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
                onPressed: _cargarTiendas,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_tiendas.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No tienes tiendas asignadas todavía.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }

    final resumen = _resumen;
    final escritorio = esEscritorio(context);

    // El tablero de escritorio no es el de celular con más columnas: cambia
    // la composición entera (encabezado con acciones a la derecha, fila de
    // KPIs de alto fijo, gráficos dentro de paneles con título). Vive en su
    // propio método para que la rama de celular quede intacta y legible.
    if (escritorio && resumen != null) {
      return RefreshIndicator(
        onRefresh: _cargarResumen,
        child: _cuerpoEscritorio(context, resumen),
      );
    }

    final graficoVentas = resumen == null
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ventas de los últimos 7 días',
                style: theme.textTheme.titleMedium,
              ).animate().fadeIn(delay: 300.ms, duration: 300.ms),
              const SizedBox(height: 12),
              _GraficoVentas7Dias(serie: resumen.ventasUltimos7Dias)
                  .animate()
                  .fadeIn(delay: 340.ms, duration: 400.ms)
                  .moveY(begin: 16, end: 0)
                  .flipH(begin: 0.1, end: 0, duration: 350.ms),
            ],
          );

    final graficoUrgencia = resumen == null
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pedidos por entregar, según urgencia',
                style: theme.textTheme.titleMedium,
              ).animate().fadeIn(delay: 380.ms, duration: 300.ms),
              const SizedBox(height: 12),
              _GraficoPendientesPorUrgencia(resumen: resumen)
                  .animate()
                  .fadeIn(delay: 420.ms, duration: 400.ms)
                  .moveY(begin: 16, end: 0)
                  .flipH(begin: 0.1, end: 0, duration: 350.ms),
            ],
          );

    return RefreshIndicator(
      onRefresh: _cargarResumen,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
        children: [
          Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bienvenido, ${widget.usuario.nombreCompleto}',
                    style: theme.textTheme.bodyMedium,
                  ).animate().fadeIn(duration: 300.ms).moveY(begin: 6, end: 0),
                  const SizedBox(height: 4),
                  Text('Panel de tu negocio', style: theme.textTheme.titleLarge)
                      .animate()
                      .fadeIn(delay: 60.ms, duration: 300.ms)
                      .moveY(begin: 6, end: 0),
                  const SizedBox(height: 16),
                  SizedBox(
                        width: escritorio ? 280 : double.infinity,
                        child: PremiumButton(
                          label: 'Registrar pedido',
                          icono: Icons.add_shopping_cart_rounded,
                          onPressed: _abrirNuevoPedido,
                        ),
                      )
                      .animate()
                      .fadeIn(delay: 90.ms, duration: 300.ms)
                      .moveY(begin: 10, end: 0),
                  const SizedBox(height: 16),
                  if (_tiendas.length > 1) ...[
                    SizedBox(
                      width: escritorio ? 320 : double.infinity,
                      child: SelectorDesplegable<Tienda>(
                        valor: _tiendaSeleccionada,
                        opciones: _tiendas,
                        etiqueta: (t) => t.nombre,
                        label: 'Tienda',
                        icono: PhosphorIconsRegular.storefront,
                        onChanged: (t) {
                          setState(() => _tiendaSeleccionada = t);
                          _cargarResumen();
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (resumen != null) ...[
                    // Solo lo cobrado (pagado) de hoy — la deuda no cuenta
                    // acá. Al tocarla (Admin/Superadmin) se abre Historial
                    // de ventas, con el detalle completo por día y el
                    // historial jerárquico de pedidos resueltos.
                    _TarjetaCobradoHoy(
                          cantidad: resumen.cobradoDiaCantidad,
                          total: resumen.cobradoDiaTotal,
                          onTap: _esGestorDeVentas
                              ? _abrirHistorialVentas
                              : null,
                        )
                        .animate()
                        .fadeIn(delay: 100.ms, duration: 450.ms)
                        .moveY(begin: 18, end: 0, curve: Curves.easeOutCubic)
                        .scale(
                          begin: const Offset(0.94, 0.94),
                          end: const Offset(1, 1),
                          curve: Curves.easeOutCubic,
                        )
                        .flipH(begin: 0.15, end: 0, duration: 400.ms),
                    const SizedBox(height: 16),
                    GridView.count(
                      // 4 en una sola fila cuando sobra ancho, en vez de la
                      // grilla 2x2 pensada para un celular angosto.
                      crossAxisCount: escritorio ? 4 : 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      // Con 4 columnas cada tarjeta queda más angosta que
                      // con 2 — necesita quedar más alta (ratio más chico)
                      // para no cortar el subtítulo de "Deuda total"/"Por
                      // entregar atrasado", no más achatada.
                      childAspectRatio: escritorio ? 0.95 : 1.05,
                      children: [
                        _TarjetaEstadistica(
                          icono: Icons.hourglass_top_rounded,
                          color: const Color(0xFFEA8C1B),
                          titulo: 'Por confirmar',
                          valor: '${resumen.pedidosPorConfirmar}',
                          delay: 140,
                          onTap: _abrirPedidos,
                        ),
                        _TarjetaEstadistica(
                          icono: Icons.local_shipping_rounded,
                          color: const Color(0xFF2563EB),
                          titulo: 'Por entregar',
                          valor: '${resumen.pendientesTotal}',
                          subtitulo: resumen.pendientesAtrasados > 0
                              ? '${resumen.pendientesAtrasados} atrasado(s)'
                              : null,
                          subtituloColor: const Color(0xFFC62828),
                          delay: 180,
                          onTap: _abrirPedidos,
                        ),
                        _TarjetaEstadistica(
                          icono: Icons.account_balance_wallet_rounded,
                          color: const Color(0xFFC62828),
                          titulo: 'Deuda total',
                          valor: 'S/ ${resumen.deudaTotal.toStringAsFixed(2)}',
                          subtitulo: '${resumen.deudaCantidad} pedido(s)',
                          delay: 220,
                          onTap: _abrirDeudas,
                        ),
                        _TarjetaEstadistica(
                          icono: Icons.qr_code_2_rounded,
                          color: const Color(0xFF6D4C41),
                          titulo: 'Pagos reportados',
                          valor: '${resumen.pagosReportados}',
                          delay: 260,
                          onTap: _abrirDeudas,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // En escritorio, los dos gráficos van uno al lado del
                    // otro — hay ancho de sobra y se comparan más fácil así
                    // que uno debajo del otro.
                    if (escritorio)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: graficoVentas),
                          const SizedBox(width: 24),
                          Expanded(child: graficoUrgencia),
                        ],
                      )
                    else ...[
                      graficoVentas,
                      const SizedBox(height: 24),
                      graficoUrgencia,
                    ],
                  ],
                ],
              ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // ESCRITORIO
  // ---------------------------------------------------------------------

  /// Tablero para ventana ancha. Tres bandas horizontales, de arriba abajo:
  /// encabezado con las acciones a la derecha, fila de indicadores de alto
  /// fijo y, abajo, los dos gráficos dentro de paneles con título.
  Widget _cuerpoEscritorio(BuildContext context, TiendaResumen resumen) {
    // Con el panel lateral fijo del Hub comiéndose 300 px, recién a partir
    // de [Breakpoints.escritorioComodo] quedan ~800 px útiles: es el punto
    // donde 5 tarjetas en una sola fila (el héroe + 4 KPIs) siguen siendo
    // legibles. Por debajo se parte en dos bandas de 2 KPIs.
    final comodo = esEscritorioComodo(context);

    final kpis = <Widget>[
      TarjetaKpi(
        icono: Icons.hourglass_top_rounded,
        color: const Color(0xFFEA8C1B),
        titulo: 'Por confirmar',
        valor: '${resumen.pedidosPorConfirmar}',
        delay: 140,
        onTap: _abrirPedidos,
      ),
      TarjetaKpi(
        icono: Icons.local_shipping_rounded,
        color: const Color(0xFF2563EB),
        titulo: 'Por entregar',
        valor: '${resumen.pendientesTotal}',
        subtitulo: resumen.pendientesAtrasados > 0
            ? '${resumen.pendientesAtrasados} atrasado(s)'
            : null,
        subtituloColor: const Color(0xFFC62828),
        delay: 180,
        onTap: _abrirPedidos,
      ),
      TarjetaKpi(
        icono: Icons.account_balance_wallet_rounded,
        color: const Color(0xFFC62828),
        titulo: 'Deuda total',
        valor: 'S/ ${resumen.deudaTotal.toStringAsFixed(2)}',
        subtitulo: '${resumen.deudaCantidad} pedido(s)',
        delay: 220,
        onTap: _abrirDeudas,
      ),
      TarjetaKpi(
        icono: Icons.qr_code_2_rounded,
        color: const Color(0xFF6D4C41),
        titulo: 'Pagos reportados',
        valor: '${resumen.pagosReportados}',
        delay: 260,
        onTap: _abrirDeudas,
      ),
    ];

    final heroe = _TarjetaCobradoHoyEscritorio(
      cantidad: resumen.cobradoDiaCantidad,
      total: resumen.cobradoDiaTotal,
      onTap: _esGestorDeVentas ? _abrirHistorialVentas : null,
    );

    // Todas las tarjetas de la banda declaran el mismo alto fijo (132), así
    // que alcanza con alinearlas arriba: no hace falta IntrinsicHeight.
    final Widget bandaIndicadores = comodo
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: heroe),
              const SizedBox(width: 16),
              for (var i = 0; i < kpis.length; i++) ...[
                if (i > 0) const SizedBox(width: 16),
                Expanded(flex: 2, child: kpis[i]),
              ],
            ],
          )
        : Column(
            children: [
              heroe,
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: kpis[0]),
                  const SizedBox(width: 16),
                  Expanded(child: kpis[1]),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: kpis[2]),
                  const SizedBox(width: 16),
                  Expanded(child: kpis[3]),
                ],
              ),
            ],
          );

    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 56),
      children: [
        ContenidoCentrado(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EncabezadoEscritorio(
                anteTitulo: 'HOLA, ${widget.usuario.nombreCompleto}',
                titulo: 'Panel de tu negocio',
                subtitulo:
                    'Cobros del día, deudas abiertas y entregas pendientes, '
                    'todo en una sola vista.',
                acciones: [
                  // En celular estos dos controles van apilados a lo ancho y
                  // empujan el primer dato debajo del pliegue. Acá caben en
                  // la misma línea del título, que era espacio muerto.
                  if (_tiendas.length > 1)
                    SizedBox(
                      width: 240,
                      child: SelectorDesplegable<Tienda>(
                        valor: _tiendaSeleccionada,
                        opciones: _tiendas,
                        etiqueta: (t) => t.nombre,
                        label: 'Tienda',
                        icono: PhosphorIconsRegular.storefront,
                        denso: true,
                        onChanged: (t) {
                          setState(() => _tiendaSeleccionada = t);
                          _cargarResumen();
                        },
                      ),
                    ),
                  SizedBox(
                    width: 220,
                    child: PremiumButton(
                      label: 'Registrar pedido',
                      icono: Icons.add_shopping_cart_rounded,
                      onPressed: _abrirNuevoPedido,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              bandaIndicadores,
              const SizedBox(height: espacioEscritorio),
              // Los dos gráficos, uno al lado del otro y más altos que en
              // celular (300 px contra 200-220): con ese alto ya vale la
              // pena dibujar el eje de valores y las guías horizontales, así
              // que en escritorio se leen cifras concretas y no solo la
              // silueta de las barras.
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: PanelEscritorio(
                        icono: Icons.show_chart_rounded,
                        titulo: 'Ventas de los últimos 7 días',
                        subtitulo: 'Solo pedidos ya cobrados.',
                        child:
                            _GraficoVentas7Dias(
                                  serie: resumen.ventasUltimos7Dias,
                                  alto: 300,
                                  conMarco: false,
                                  detallado: true,
                                )
                                .animate()
                                .fadeIn(delay: 320.ms, duration: 400.ms)
                                .moveY(begin: 16, end: 0),
                      ),
                    ),
                    const SizedBox(width: espacioEscritorio),
                    Expanded(
                      child: PanelEscritorio(
                        icono: Icons.local_shipping_rounded,
                        titulo: 'Pedidos por entregar',
                        subtitulo: 'Agrupados por urgencia, para priorizar.',
                        child:
                            _GraficoPendientesPorUrgencia(
                                  resumen: resumen,
                                  alto: 300,
                                  conMarco: false,
                                  detallado: true,
                                )
                                .animate()
                                .fadeIn(delay: 380.ms, duration: 400.ms)
                                .moveY(begin: 16, end: 0),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Versión de escritorio de "Cobrado hoy": la misma tarjeta con degradado de
/// marca, pero acostada — en una fila de indicadores de 132 px de alto, la
/// versión vertical de celular obligaría a estirar toda la banda.
class _TarjetaCobradoHoyEscritorio extends StatelessWidget {
  const _TarjetaCobradoHoyEscritorio({
    required this.cantidad,
    required this.total,
    this.onTap,
  });

  final int cantidad;
  final double total;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TarjetaEscritorio(
          onTap: onTap,
          acento: AppColors.primary,
          alto: 132,
          bordeVisible: false,
          padding: const EdgeInsets.fromLTRB(22, 16, 20, 16),
          gradiente: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primary, AppColors.secondary],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                        Icons.trending_up_rounded,
                        color: Colors.white,
                        size: 20,
                      )
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .scale(
                        begin: const Offset(1, 1),
                        end: const Offset(1.15, 1.15),
                        duration: 1400.ms,
                        curve: Curves.easeInOut,
                      ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Cobrado hoy',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (onTap != null)
                    const Icon(
                      Icons.arrow_outward_rounded,
                      size: 16,
                      color: Colors.white70,
                    ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ContadorAnimado(
                    valor: total,
                    formatear: (v) => 'S/ ${v.toStringAsFixed(2)}',
                    estilo: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$cantidad pedido(s) cobrado(s) hoy',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        )
        .animate()
        .fadeIn(duration: 400.ms)
        .moveY(begin: 14, end: 0, curve: Curves.easeOutCubic);
  }
}

/// Esqueleto del tablero mientras llega la primera respuesta: replica la
/// silueta real (encabezado, banda de 5 indicadores, dos paneles de
/// gráfico) con [SkeletonBox], para que la pantalla no salte al llenarse.
class _EsqueletoTableroEscritorio extends StatelessWidget {
  const _EsqueletoTableroEscritorio();

  @override
  Widget build(BuildContext context) {
    Widget marco({required double alto, required Widget child}) => Container(
      height: alto,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.surfaceMuted, width: 1.2),
      ),
      child: child,
    );

    final tarjeta = marco(
      alto: 132,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: const [
          SkeletonBox(width: 38, height: 38, borderRadius: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 96, height: 24),
              SizedBox(height: 8),
              SkeletonBox(width: 64, height: 11),
            ],
          ),
        ],
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 56),
      children: [
        ContenidoCentrado(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SkeletonBox(width: 180, height: 12),
              const SizedBox(height: 10),
              const SkeletonBox(width: 320, height: 28),
              const SizedBox(height: 32),
              Row(
                children: [
                  for (var i = 0; i < 5; i++) ...[
                    if (i > 0) const SizedBox(width: 16),
                    Expanded(child: tarjeta),
                  ],
                ],
              ),
              const SizedBox(height: espacioEscritorio),
              Row(
                children: [
                  Expanded(
                    child: marco(
                      alto: 380,
                      child: const SkeletonBox(
                        height: double.infinity,
                        borderRadius: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: espacioEscritorio),
                  Expanded(
                    child: marco(
                      alto: 380,
                      child: const SkeletonBox(
                        height: double.infinity,
                        borderRadius: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Tarjeta única "Cobrado hoy" — solo pedidos ENTREGADO+PAGADO, la deuda no
/// se cuenta acá. Al tocarla (Admin/Superadmin) se abre Historial de
/// ventas, que trae el desglose completo (cobrado/deuda por día, con
/// selector de fecha) y el historial jerárquico de pedidos resueltos.
class _TarjetaCobradoHoy extends StatelessWidget {
  const _TarjetaCobradoHoy({
    required this.cantidad,
    required this.total,
    this.onTap,
  });

  final int cantidad;
  final double total;

  /// Solo presente para Admin/Superadmin — un Trabajador raso ve esta
  /// misma tarjeta pero no puede entrar al historial completo de ventas.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tarjeta3D(
      borderRadius: 24,
      profundidad: 0.0022,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primary, AppColors.secondary],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.trending_up_rounded, color: Colors.white, size: 20)
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .scale(
                      begin: const Offset(1, 1),
                      end: const Offset(1.15, 1.15),
                      duration: 1400.ms,
                      curve: Curves.easeInOut,
                    ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Cobrado hoy',
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: Colors.white),
                  ),
                ),
                if (onTap != null)
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white70,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            ContadorAnimado(
              valor: total,
              formatear: (v) => 'S/ ${v.toStringAsFixed(2)}',
              estilo: const TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$cantidad pedido(s) cobrado(s) hoy',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

class _TarjetaEstadistica extends StatelessWidget {
  const _TarjetaEstadistica({
    required this.icono,
    required this.color,
    required this.titulo,
    required this.valor,
    this.subtitulo,
    this.subtituloColor,
    required this.delay,
    this.onTap,
  });

  final IconData icono;
  final Color color;
  final String titulo;
  final String valor;
  final String? subtitulo;
  final Color? subtituloColor;
  final int delay;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final esNumero = double.tryParse(valor.replaceAll(RegExp('[^0-9.]'), ''));

    return Tarjeta3D(
          onTap: onTap,
          borderRadius: 20,
          child: Material(
            color: AppColors.surface,
            child: InkWell(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icono, color: color, size: 18),
                    ),
                    const SizedBox(height: 8),
                    esNumero != null
                        ? ContadorAnimado(
                            valor: esNumero,
                            formatear: (v) => valor.startsWith('S/')
                                ? 'S/ ${v.toStringAsFixed(2)}'
                                : v.toStringAsFixed(0),
                            estilo: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          )
                        : Text(
                            valor,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                    Text(
                      titulo,
                      style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitulo != null)
                      Text(
                        subtitulo!,
                        style: TextStyle(
                          color: subtituloColor ?? AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ),
          ),
        )
        .animate(delay: delay.ms)
        .fadeIn(duration: 350.ms)
        .moveY(begin: 14, end: 0)
        .flipH(begin: 0.1, end: 0, duration: 320.ms);
  }
}

/// Gráfico de barras de ventas diarias (últimos 7 días) — fl_chart trae su
/// propia animación de entrada para las barras.
class _GraficoVentas7Dias extends StatelessWidget {
  const _GraficoVentas7Dias({
    required this.serie,
    this.alto = 220,
    this.conMarco = true,
    this.detallado = false,
  });

  final List<VentaDiaria> serie;

  /// Alto del área de dibujo. En escritorio sube a 300: con 220 las barras
  /// quedaban tan achatadas que las diferencias entre días no se veían.
  final double alto;

  /// false cuando el gráfico ya va dentro de un [PanelEscritorio] — evita
  /// una tarjeta dentro de otra tarjeta.
  final bool conMarco;

  /// Agrega eje de valores y guías horizontales. Solo tiene sentido con
  /// [alto] grande y ancho de escritorio; en celular sería ruido.
  final bool detallado;

  @override
  Widget build(BuildContext context) {
    final maximo = serie.fold<double>(
      0,
      (acc, v) => v.total > acc ? v.total : acc,
    );
    final techo = maximo <= 0 ? 10.0 : maximo * 1.25;
    final formatoDia = DateFormat('EEE', 'es');

    final grafico = Container(
      height: alto,
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
      color: conMarco ? AppColors.surface : null,
      child: BarChart(
        BarChartData(
          maxY: techo,
          alignment: BarChartAlignment.spaceAround,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                  BarTooltipItem(
                    detallado
                        ? '${formatoDia.format(serie[group.x].fecha)}\nS/ ${rod.toY.toStringAsFixed(2)}'
                        : 'S/ ${rod.toY.toStringAsFixed(2)}',
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: detallado,
                reservedSize: 46,
                getTitlesWidget: (value, meta) => Text(
                  'S/ ${value.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final indice = value.toInt();
                  if (indice < 0 || indice >= serie.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      formatoDia.format(serie[indice].fecha),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          gridData: FlGridData(
            show: detallado,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) => FlLine(
              color: AppColors.surfaceMuted,
              strokeWidth: 1,
              dashArray: const [4, 6],
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: serie.asMap().entries.map((entry) {
            final esHoy = entry.key == serie.length - 1;
            return BarChartGroupData(
              x: entry.key,
              barRods: [
                BarChartRodData(
                  toY: entry.value.total,
                  color: esHoy
                      ? AppColors.primary
                      : AppColors.secondary.withValues(alpha: 0.55),
                  width: detallado ? 30 : 22,
                  borderRadius: BorderRadius.circular(6),
                ),
              ],
            );
          }).toList(),
        ),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
      ),
    );

    return conMarco ? Tarjeta3D(child: grafico) : grafico;
  }
}

/// Gráfico de barras horizontal de pedidos pendientes de entrega,
/// agrupados por urgencia — ayuda al administrador a priorizar de un
/// vistazo qué necesita atención primero.
class _GraficoPendientesPorUrgencia extends StatelessWidget {
  const _GraficoPendientesPorUrgencia({
    required this.resumen,
    this.alto = 200,
    this.conMarco = true,
    this.detallado = false,
  });

  final TiendaResumen resumen;
  final double alto;
  final bool conMarco;
  final bool detallado;

  @override
  Widget build(BuildContext context) {
    final categorias = [
      ('Atrasados', resumen.pendientesAtrasados, const Color(0xFFC62828)),
      ('Hoy', resumen.pendientesHoy, AppColors.primary),
      ('Próximos', resumen.pendientesProximos, const Color(0xFF2563EB)),
      ('Sin fecha', resumen.pendientesSinFecha, AppColors.textSecondary),
    ];
    final maximo = categorias.fold<int>(0, (acc, c) => c.$2 > acc ? c.$2 : acc);
    final techo = maximo <= 0 ? 5.0 : maximo * 1.3;

    if (resumen.pendientesTotal == 0) {
      return Container(
        height: conMarco ? 100 : alto,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: conMarco ? AppColors.surface : null,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          'No hay pedidos pendientes de entrega',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    final grafico = Container(
      height: alto,
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
      color: conMarco ? AppColors.surface : null,
      child: BarChart(
        BarChartData(
          maxY: techo,
          alignment: BarChartAlignment.spaceAround,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                  BarTooltipItem(
                    detallado
                        ? '${categorias[group.x].$1}\n${rod.toY.toInt()} pedido(s)'
                        : '${rod.toY.toInt()} pedido(s)',
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: detallado,
                reservedSize: 32,
                // Solo enteros: "2.5 pedidos" no existe.
                getTitlesWidget: (value, meta) => value % 1 != 0
                    ? const SizedBox.shrink()
                    : Text(
                        value.toStringAsFixed(0),
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final indice = value.toInt();
                  if (indice < 0 || indice >= categorias.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      categorias[indice].$1,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          gridData: FlGridData(
            show: detallado,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) => FlLine(
              color: AppColors.surfaceMuted,
              strokeWidth: 1,
              dashArray: const [4, 6],
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: categorias.asMap().entries.map((entry) {
            return BarChartGroupData(
              x: entry.key,
              barRods: [
                BarChartRodData(
                  toY: entry.value.$2.toDouble(),
                  color: entry.value.$3,
                  width: detallado ? 38 : 28,
                  borderRadius: BorderRadius.circular(6),
                ),
              ],
            );
          }).toList(),
        ),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
      ),
    );

    return conMarco ? Tarjeta3D(child: grafico) : grafico;
  }
}
