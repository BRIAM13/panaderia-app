import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import '../../models/tienda_model.dart';
import '../../models/tienda_resumen_model.dart';
import '../../services/api_client.dart';
import '../../services/pedidos_service.dart';
import '../../services/tiendas_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/fecha_pedido_utils.dart';
import '../../widgets/contador_animado.dart';
import '../../widgets/estado_error.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/pedidos_secciones.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/tarjeta_3d.dart';

/// Historial completo de ventas de una tienda (solo ADMIN/SUPERADMIN,
/// abierto desde la tarjeta "Ventas de hoy" del Dashboard) — reemplaza a la
/// sección "Historial" que antes vivía dentro de Pedidos. Muestra los
/// pedidos ya resueltos de forma jerárquica: primero los completados y
/// pagados, después los que quedaron como deuda, luego los cancelados, y
/// por último los rechazados (menos relevantes, se conservan para no
/// perder ese historial).
class HistorialVentasPage extends StatefulWidget {
  const HistorialVentasPage({super.key, required this.tienda});

  final Tienda tienda;

  @override
  State<HistorialVentasPage> createState() => _HistorialVentasPageState();
}

class _HistorialVentasPageState extends State<HistorialVentasPage> {
  final _pedidosService = PedidosService();
  final _tiendasService = TiendasService();

  bool _cargando = true;
  String? _error;
  List<Pedido> _pedidos = [];
  TiendaResumen? _resumen;
  List<DateTime> _fechasConDatos = [];

  /// Día que muestran las tarjetas "Cobrado"/"Deuda del día" — hoy por
  /// defecto. El historial de abajo no se filtra por esto: sigue mostrando
  /// todos los pedidos resueltos, sin importar qué día se esté mirando
  /// arriba.
  DateTime _fechaSeleccionada = DateTime.now();
  bool _cargandoResumen = false;

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
        _pedidosService.listar(),
        _tiendasService.resumen(widget.tienda.idTienda),
        _tiendasService.fechasConVentas(widget.tienda.idTienda),
      ]);
      if (!mounted) return;
      final pedidos = resultados[0] as List<Pedido>;
      setState(() {
        _pedidos = pedidos
            .where(
              (p) => p.idTienda == widget.tienda.idTienda && p.esFinalizado,
            )
            .toList();
        _resumen = resultados[1] as TiendaResumen;
        _fechasConDatos = resultados[2] as List<DateTime>;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo cargar el historial de ventas.');
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
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
      // Solo se puede elegir un día con al menos una venta registrada — el
      // resto del calendario queda deshabilitado.
      selectableDayPredicate: (dia) =>
          _fechasConDatos.any((f) => _mismoDia(f, dia)),
      helpText: 'Elige un día con ventas registradas',
    );
    if (elegida == null || _mismoDia(elegida, _fechaSeleccionada)) return;

    setState(() {
      _fechaSeleccionada = elegida;
      _cargandoResumen = true;
    });
    try {
      final resumen = await _tiendasService.resumen(
        widget.tienda.idTienda,
        fecha: elegida,
      );
      if (mounted) setState(() => _resumen = resumen);
    } catch (_) {
      // Silencioso: si falla, las tarjetas se quedan con el día anterior
      // hasta que se pueda reintentar.
    } finally {
      if (mounted) setState(() => _cargandoResumen = false);
    }
  }

  List<Pedido> _filtrarYOrdenar(bool Function(Pedido) filtro) {
    final lista = _pedidos.where(filtro).toList()
      ..sort(
        (a, b) => (b.fechaEntregaReal ?? b.fechaCreacion).compareTo(
          a.fechaEntregaReal ?? a.fechaCreacion,
        ),
      );
    return lista;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de ventas'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              widget.tienda.nombre,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(
                  context,
                ).appBarTheme.foregroundColor?.withValues(alpha: 0.85),
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(child: _construirCuerpo()),
    );
  }

  Widget _construirCuerpo() {
    if (_cargando) return const _EsqueletoHistorial();

    if (_error != null) {
      return EstadoError(mensaje: _error!, onReintentar: _cargar);
    }

    final pagados = _filtrarYOrdenar(
      (p) => p.estado == 'ENTREGADO' && p.estadoPago == 'PAGADO',
    );
    final deuda = _filtrarYOrdenar(
      (p) => p.estado == 'ENTREGADO' && p.estadoPago == 'DEUDA',
    );
    final cancelados = _filtrarYOrdenar((p) => p.estado == 'CANCELADO');
    final rechazados = _filtrarYOrdenar((p) => p.estado == 'RECHAZADO');

    if (pagados.isEmpty &&
        deuda.isEmpty &&
        cancelados.isEmpty &&
        rechazados.isEmpty) {
      return EstadoVacio(
        icono: Icons.receipt_long_rounded,
        titulo: 'Todavía no hay ventas en el historial',
        subtitulo:
            'Los pedidos entregados, cancelados o rechazados de esta '
            'tienda van a aparecer acá.',
        onRefrescar: _cargar,
      );
    }

    final resumen = _resumen;

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          if (resumen != null) ...[
            _SelectorFecha(
                  fecha: _fechaSeleccionada,
                  habilitado: _fechasConDatos.isNotEmpty,
                  onTap: _seleccionarFecha,
                )
                .animate()
                .fadeIn(delay: 60.ms, duration: 300.ms)
                .moveX(begin: -12, end: 0),
            const SizedBox(height: 10),
            // AnimatedSwitcher hace que las dos tarjetas entren con una
            // transición cada vez que cambia el día elegido, no solo la
            // primera vez que carga la pantalla.
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
              child: Opacity(
                key: ValueKey(
                  _fechaSeleccionada.toIso8601String().split('T').first,
                ),
                opacity: _cargandoResumen ? 0.5 : 1,
                child: Row(
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
                      ),
                    ),
                  ],
                ),
              ),
            ).animate().fadeIn(delay: 100.ms, duration: 450.ms),
            const SizedBox(height: 24),
            Text(
              'Historial completo',
              style: Theme.of(context).textTheme.titleMedium,
            ).animate().fadeIn(delay: 140.ms, duration: 300.ms),
            const SizedBox(height: 12),
          ],
          _SeccionHistorial(
            titulo: 'Completados y pagados',
            subtitulo: 'Entregados y ya cobrados',
            icono: Icons.check_circle_rounded,
            color: const Color(0xFF2E7D32),
            pedidos: pagados,
          ),
          _SeccionHistorial(
            titulo: 'Con deuda',
            subtitulo: 'Entregados, el cliente todavía debe',
            icono: Icons.account_balance_wallet_rounded,
            color: const Color(0xFFC62828),
            pedidos: deuda,
          ),
          _SeccionHistorial(
            titulo: 'Cancelados',
            subtitulo: 'No llegaron a entregarse',
            icono: Icons.block_rounded,
            color: const Color(0xFF6D4C41),
            pedidos: cancelados,
          ),
          _SeccionHistorial(
            titulo: 'Rechazados',
            subtitulo: 'El personal no los aceptó',
            icono: Icons.cancel_rounded,
            color: AppColors.textSecondary,
            pedidos: rechazados,
          ),
        ],
      ),
    );
  }
}

class _EsqueletoHistorial extends StatelessWidget {
  const _EsqueletoHistorial();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        const SkeletonBox(width: 160, height: 18),
        const SizedBox(height: 4),
        const SkeletonBox(width: 220, height: 13),
        const SizedBox(height: 14),
        ...List.generate(3, (i) => const _EsqueletoTarjeta()),
        const SizedBox(height: 20),
        const SkeletonBox(width: 130, height: 18),
        const SizedBox(height: 4),
        const SkeletonBox(width: 200, height: 13),
        const SizedBox(height: 14),
        const _EsqueletoTarjeta(),
      ],
    );
  }
}

class _EsqueletoTarjeta extends StatelessWidget {
  const _EsqueletoTarjeta();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: 140, height: 15),
            SizedBox(height: 8),
            SkeletonBox(width: 200, height: 12),
            SizedBox(height: 6),
            SkeletonBox(width: 100, height: 12),
          ],
        ),
      ),
    );
  }
}

class _SeccionHistorial extends StatelessWidget {
  const _SeccionHistorial({
    required this.titulo,
    required this.subtitulo,
    required this.icono,
    required this.color,
    required this.pedidos,
  });

  final String titulo;
  final String subtitulo;
  final IconData icono;
  final Color color;
  final List<Pedido> pedidos;

  @override
  Widget build(BuildContext context) {
    if (pedidos.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                titulo,
                style: theme.textTheme.titleMedium?.copyWith(color: color),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${pedidos.length}',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Text(subtitulo, style: theme.textTheme.bodyMedium),
          ),
          const SizedBox(height: 10),
          ...pedidos.asMap().entries.map(
            (entry) => _TarjetaVentaHistorial(
                  pedido: entry.value,
                  colorSeccion: color,
                )
                .animate(delay: (40 * entry.key).ms)
                .fadeIn(duration: 260.ms)
                .moveY(begin: 10, end: 0)
                .flipH(begin: 0.1, end: 0, duration: 320.ms),
          ),
        ],
      ),
    );
  }
}

class _TarjetaVentaHistorial extends StatelessWidget {
  const _TarjetaVentaHistorial({
    required this.pedido,
    required this.colorSeccion,
  });

  final Pedido pedido;
  final Color colorSeccion;

  String get _fechaResolucion {
    final fecha = pedido.fechaEntregaReal ?? pedido.fechaCreacion;
    return formatearFechaEntrega(fecha);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cliente = pedido.cliente;
    final nombreComercial = cliente.nombreComercial;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Tarjeta3D(
        borderRadius: 20,
        child: Container(
          color: AppColors.surface,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          colorSeccion.withValues(alpha: 0.20),
                          colorSeccion.withValues(alpha: 0.08),
                        ],
                      ),
                    ),
                    child: Icon(
                      pedido.tipoPedido == 'PAQUETES'
                          ? Icons.inventory_2_rounded
                          : Icons.local_dining_rounded,
                      color: colorSeccion,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cliente.nombreParaMostrar,
                          style: theme.textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (nombreComercial != null)
                          Text(
                            nombreComercial,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.secondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        const SizedBox(height: 2),
                        Text(
                          '${pedido.tipoPedido == 'PAQUETES' ? 'Paquetes' : 'Unidades'} · '
                          '${pedido.cantidad} · S/ ${pedido.total.toStringAsFixed(2)}',
                          style: theme.textTheme.bodyMedium,
                        ),
                        Text(
                          _fechaResolucion,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              InfoAuditoriaPedido(pedido: pedido),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chip que muestra el día elegido para "Cobrado"/"Deuda del día" y abre el
/// selector de fecha al tocarlo — solo permite elegir días con ventas
/// registradas (ver [_HistorialVentasPageState._seleccionarFecha]).
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
/// de estas van lado a lado arriba del historial. El ícono con pulso
/// continuo le da ese aire "vivo", sin exagerar.
class _TarjetaMontoDia extends StatelessWidget {
  const _TarjetaMontoDia({
    required this.titulo,
    required this.icono,
    required this.colores,
    required this.cantidad,
    required this.total,
    required this.etiquetaCantidad,
  });

  final String titulo;
  final IconData icono;
  final List<Color> colores;
  final int cantidad;
  final double total;
  final String etiquetaCantidad;

  @override
  Widget build(BuildContext context) {
    return Tarjeta3D(
      borderRadius: 22,
      profundidad: 0.002,
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
              ],
            ),
            const SizedBox(height: 10),
            ContadorAnimado(
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
