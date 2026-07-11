import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import '../../models/tienda_model.dart';
import '../../models/tienda_resumen_model.dart';
import '../../models/usuario_sesion.dart';
import '../../services/api_client.dart';
import '../../services/notificaciones_service.dart';
import '../../services/tiendas_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../widgets/contador_animado.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/tarjeta_3d.dart';
import 'deudas_page.dart';
import 'historial_ventas_page.dart';
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

  void _abrirPedidos() {
    pushSlideUpFade(context, (_) => const PedidosPage());
  }

  void _abrirDeudas() {
    pushSlideUpFade(context, (_) => const DeudasPage());
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
    final esEscritorio = MediaQuery.sizeOf(context).width >= Breakpoints.escritorio;

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
          Center(
            child: ConstrainedBox(
              // En monitores muy anchos, 1400px de contenido se lee mejor
              // que gráficos estirados de punta a punta de la pantalla.
              constraints: const BoxConstraints(maxWidth: 1400),
              child: Column(
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
                  if (_tiendas.length > 1) ...[
                    SizedBox(
                      width: esEscritorio ? 320 : double.infinity,
                      child: DropdownButtonFormField<Tienda>(
                        initialValue: _tiendaSeleccionada,
                        items: _tiendas
                            .map(
                              (t) => DropdownMenuItem(
                                value: t,
                                child: Text(t.nombre),
                              ),
                            )
                            .toList(),
                        onChanged: (t) {
                          setState(() => _tiendaSeleccionada = t);
                          _cargarResumen();
                        },
                        decoration: const InputDecoration(
                          labelText: 'Tienda',
                          prefixIcon: Icon(Icons.storefront_rounded),
                        ),
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
                      crossAxisCount: esEscritorio ? 4 : 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: esEscritorio ? 1.3 : 1.05,
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
                    if (esEscritorio)
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
            ),
          ),
        ],
      ),
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
  const _GraficoVentas7Dias({required this.serie});

  final List<VentaDiaria> serie;

  @override
  Widget build(BuildContext context) {
    final maximo = serie.fold<double>(
      0,
      (acc, v) => v.total > acc ? v.total : acc,
    );
    final techo = maximo <= 0 ? 10.0 : maximo * 1.25;
    final formatoDia = DateFormat('EEE', 'es');

    return Tarjeta3D(
      child: Container(
        height: 220,
        padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
        color: AppColors.surface,
        child: BarChart(
          BarChartData(
            maxY: techo,
            alignment: BarChartAlignment.spaceAround,
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                    BarTooltipItem(
                      'S/ ${rod.toY.toStringAsFixed(2)}',
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
              ),
            ),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
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
                    if (indice < 0 || indice >= serie.length)
                      return const SizedBox.shrink();
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
            gridData: const FlGridData(show: false),
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
                    width: 22,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ],
              );
            }).toList(),
          ),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
        ),
      ),
    );
  }
}

/// Gráfico de barras horizontal de pedidos pendientes de entrega,
/// agrupados por urgencia — ayuda al administrador a priorizar de un
/// vistazo qué necesita atención primero.
class _GraficoPendientesPorUrgencia extends StatelessWidget {
  const _GraficoPendientesPorUrgencia({required this.resumen});

  final TiendaResumen resumen;

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
        height: 100,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          'No hay pedidos pendientes de entrega',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return Tarjeta3D(
      child: Container(
        height: 200,
        padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
        color: AppColors.surface,
        child: BarChart(
          BarChartData(
            maxY: techo,
            alignment: BarChartAlignment.spaceAround,
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                    BarTooltipItem(
                      '${rod.toY.toInt()} pedido(s)',
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
              ),
            ),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
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
                    if (indice < 0 || indice >= categorias.length)
                      return const SizedBox.shrink();
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
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            barGroups: categorias.asMap().entries.map((entry) {
              return BarChartGroupData(
                x: entry.key,
                barRods: [
                  BarChartRodData(
                    toY: entry.value.$2.toDouble(),
                    color: entry.value.$3,
                    width: 28,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ],
              );
            }).toList(),
          ),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
        ),
      ),
    );
  }
}
