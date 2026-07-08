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

  /// Día que se muestra arriba (cobrado/deuda del día) — hoy por defecto.
  /// Solo se puede cambiar a un día con datos reales (ver
  /// [_fechasConDatos]), nunca a uno vacío.
  DateTime _fechaSeleccionada = DateTime.now();
  List<DateTime> _fechasConDatos = [];

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
        _fechaSeleccionada = DateTime.now();
      });
      if (_tiendaSeleccionada != null) {
        await Future.wait([_cargarResumen(), _cargarFechasConDatos()]);
      }
    } on ApiException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(() => _error = 'No se pudieron cargar tus tiendas.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _cargarFechasConDatos() async {
    if (_tiendaSeleccionada == null) return;
    try {
      final fechas = await _tiendasService.fechasConVentas(
        _tiendaSeleccionada!.idTienda,
      );
      if (mounted) setState(() => _fechasConDatos = fechas);
    } catch (_) {
      // Silencioso: si falla, el selector de fecha simplemente no deja
      // elegir ningún día distinto a hoy hasta que se pueda recargar.
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
      final resumen = await _tiendasService.resumen(
        _tiendaSeleccionada!.idTienda,
        fecha: _fechaSeleccionada,
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

  bool _mismoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _seleccionarFecha() async {
    if (_fechasConDatos.isEmpty) return;
    final primero = _fechasConDatos.reduce((a, b) => a.isBefore(b) ? a : b);
    final ultimo = _fechasConDatos.reduce((a, b) => a.isAfter(b) ? a : b);

    final elegida = await showDatePicker(
      context: context,
      initialDate: _fechaSeleccionada,
      firstDate: primero,
      lastDate: ultimo.isAfter(DateTime.now()) ? ultimo : DateTime.now(),
      // Solo se puede elegir un día con al menos una venta registrada —
      // el resto del calendario queda deshabilitado.
      selectableDayPredicate: (dia) =>
          _fechasConDatos.any((f) => _mismoDia(f, dia)),
      helpText: 'Elige un día con ventas registradas',
    );
    if (elegida == null || _mismoDia(elegida, _fechaSeleccionada)) return;

    setState(() => _fechaSeleccionada = elegida);
    await _cargarResumen();
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

    return RefreshIndicator(
      onRefresh: _cargarResumen,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
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
            DropdownButtonFormField<Tienda>(
              initialValue: _tiendaSeleccionada,
              items: _tiendas
                  .map((t) => DropdownMenuItem(value: t, child: Text(t.nombre)))
                  .toList(),
              onChanged: (t) {
                setState(() {
                  _tiendaSeleccionada = t;
                  _fechaSeleccionada = DateTime.now();
                });
                _cargarResumen();
                _cargarFechasConDatos();
              },
              decoration: const InputDecoration(
                labelText: 'Tienda',
                prefixIcon: Icon(Icons.storefront_rounded),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (resumen != null) ...[
            _SelectorFecha(
                  fecha: _fechaSeleccionada,
                  habilitado: _fechasConDatos.isNotEmpty,
                  onTap: _seleccionarFecha,
                )
                .animate()
                .fadeIn(delay: 80.ms, duration: 300.ms)
                .moveX(begin: -12, end: 0),
            const SizedBox(height: 10),
            // AnimatedSwitcher hace que las dos tarjetas de dinero entren
            // con una transición cada vez que cambia el día elegido, no
            // solo la primera vez que carga la pantalla.
            AnimatedSwitcher(
              duration: 420.ms,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position:
                      Tween<Offset>(
                        begin: const Offset(0, 0.08),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                        ),
                      ),
                  child: child,
                ),
              ),
              child: Row(
                key: ValueKey(_fechaSeleccionada.toIso8601String().split('T').first),
                children: [
                  Expanded(
                    child: _TarjetaMontoDia(
                      titulo: 'Cobrado',
                      icono: Icons.trending_up_rounded,
                      colores: const [
                        AppColors.primary,
                        AppColors.secondary,
                      ],
                      cantidad: resumen.cobradoDiaCantidad,
                      total: resumen.cobradoDiaTotal,
                      etiquetaCantidad: 'cobrado(s)',
                      onTap: _esGestorDeVentas
                          ? _abrirHistorialVentas
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TarjetaMontoDia(
                      titulo: 'Deuda del día',
                      icono: Icons.account_balance_wallet_rounded,
                      colores: const [
                        Color(0xFFC62828),
                        Color(0xFFE57373),
                      ],
                      cantidad: resumen.deudaDiaCantidad,
                      total: resumen.deudaDiaTotal,
                      etiquetaCantidad: 'con deuda',
                      onTap: _esGestorDeVentas
                          ? _abrirHistorialVentas
                          : null,
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 120.ms, duration: 450.ms),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.05,
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
            const SizedBox(height: 24),
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
        ],
      ),
    );
  }
}

/// Cuenta hacia arriba desde 0 hasta [valor] con una animación suave —
/// parte del "moderno y animado" que se pidió para este dashboard.
class _ContadorAnimado extends StatelessWidget {
  const _ContadorAnimado({
    required this.valor,
    required this.formatear,
    required this.estilo,
  });

  final double valor;
  final String Function(double) formatear;
  final TextStyle? estilo;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: valor),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, valorActual, _) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(formatear(valorActual), style: estilo, maxLines: 1),
      ),
    );
  }
}

/// Chip que muestra el día elegido para "Cobrado"/"Deuda del día" y abre el
/// selector de fecha al tocarlo — solo permite elegir días con ventas
/// registradas (ver [_DashboardPageState._seleccionarFecha]).
class _SelectorFecha extends StatelessWidget {
  const _SelectorFecha({
    required this.fecha,
    required this.habilitado,
    required this.onTap,
  });

  final DateTime fecha;
  final bool habilitado;
  final VoidCallback onTap;

  bool get _esHoy {
    final hoy = DateTime.now();
    return fecha.year == hoy.year &&
        fecha.month == hoy.month &&
        fecha.day == hoy.day;
  }

  @override
  Widget build(BuildContext context) {
    final etiqueta = _esHoy
        ? 'Hoy, ${DateFormat('d \'de\' MMMM', 'es').format(fecha)}'
        : DateFormat('EEEE d \'de\' MMMM', 'es').format(fecha);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: habilitado ? onTap : null,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.secondary.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.calendar_month_rounded,
                size: 16,
                color: AppColors.secondary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  etiqueta[0].toUpperCase() + etiqueta.substring(1),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (habilitado) ...[
                const SizedBox(width: 4),
                const Icon(
                  Icons.expand_more_rounded,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta compacta de dinero para el día elegido (cobrado o deuda) — dos
/// de estas van lado a lado arriba del Dashboard. El brillo diagonal y el
/// ícono con pulso continuo son a propósito: le dan ese aire "vivo" que se
/// pidió, sin exagerar (nada se mueve tan rápido como para distraer).
class _TarjetaMontoDia extends StatelessWidget {
  const _TarjetaMontoDia({
    required this.titulo,
    required this.icono,
    required this.colores,
    required this.cantidad,
    required this.total,
    required this.etiquetaCantidad,
    this.onTap,
  });

  final String titulo;
  final IconData icono;
  final List<Color> colores;
  final int cantidad;
  final double total;
  final String etiquetaCantidad;

  /// Solo presente para Admin/Superadmin — un Trabajador raso ve esta
  /// misma tarjeta pero no puede entrar al historial completo de ventas.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tarjeta3D(
      borderRadius: 22,
      profundidad: 0.002,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colores,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icono, color: Colors.white, size: 17)
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .scale(
                      begin: const Offset(1, 1),
                      end: const Offset(1.15, 1.15),
                      duration: 1400.ms,
                      curve: Curves.easeInOut,
                    ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    titulo,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (onTap != null)
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white70,
                    size: 18,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            _ContadorAnimado(
              valor: total,
              formatear: (v) => 'S/ ${v.toStringAsFixed(2)}',
              estilo: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$cantidad $etiquetaCantidad',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
                        ? _ContadorAnimado(
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
