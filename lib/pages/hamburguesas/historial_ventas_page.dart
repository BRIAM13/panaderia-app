import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import '../../models/tienda_model.dart';
import '../../services/api_client.dart';
import '../../services/horneados_service.dart';
import '../../services/pedidos_service.dart';
import '../../services/tiendas_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/fecha_pedido_utils.dart';
import '../../widgets/contador_animado.dart';
import '../../widgets/estado_error.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/pedidos_secciones.dart';
import '../../widgets/selector_fecha_calendario.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/tarjeta_3d.dart';

/// Historial completo de ventas de una tienda (solo ADMIN/SUPERADMIN,
/// abierto desde la tarjeta "Ventas de hoy" del Dashboard) — reemplaza a la
/// sección "Historial" que antes vivía dentro de Pedidos. Por defecto
/// muestra solo lo resuelto HOY, agrupado en secciones plegadas
/// (Completados y pagados / Con deuda / Cancelados / Rechazados) que se
/// despliegan al tocarlas; el botón "Ver todo" cambia a ver el histórico
/// completo sin filtrar por fecha.
class HistorialVentasPage extends StatefulWidget {
  const HistorialVentasPage({super.key, required this.tienda});

  final Tienda tienda;

  @override
  State<HistorialVentasPage> createState() => _HistorialVentasPageState();
}

class _HistorialVentasPageState extends State<HistorialVentasPage> {
  final _pedidosService = PedidosService();
  final _horneadosService = HorneadosService();
  final _tiendasService = TiendasService();

  bool _cargando = true;
  String? _error;
  List<Pedido> _pedidos = [];
  List<DateTime> _fechasConDatos = [];
  List<DateTime> _fechasConDeuda = [];

  DateTime _fechaSeleccionada = DateTime.now();

  /// true: ignora [_fechaSeleccionada] y muestra todo el histórico. Se
  /// activa con el botón junto al selector de fecha.
  bool _verTodo = false;

  /// Títulos de las secciones actualmente desplegadas — todas empiezan
  /// plegadas (solo el encabezado con el conteo) para no abrumar con la
  /// lista completa apenas se entra a la pantalla.
  final Set<String> _seccionesExpandidas = {};

  bool get _esHorneados => widget.tienda.slug == 'horneados';

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
        _cargarPedidosDeTienda(),
        _tiendasService.fechasConVentas(widget.tienda.idTienda),
      ]);
      if (!mounted) return;
      setState(() {
        _pedidos = resultados[0] as List<Pedido>;
        final fechas = resultados[1] as FechasConVentas;
        _fechasConDatos = fechas.fechas;
        _fechasConDeuda = fechas.fechasConDeuda;
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

  /// El endpoint de listado es distinto por tienda: Horneados tiene su
  /// propio servicio dedicado (campos propios — carne, presentación,
  /// aderezo); el resto (Hamburguesas, Panadería) comparte `/pedidos`,
  /// filtrado por `idTienda`.
  Future<List<Pedido>> _cargarPedidosDeTienda() async {
    if (_esHorneados) {
      final horneados = await _horneadosService.listarPedidos();
      return horneados.map((h) => h.pedido).toList();
    }
    return _pedidosService.listar(idTienda: widget.tienda.idTienda);
  }

  bool _mismoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _seleccionarFecha() async {
    final elegida = await mostrarSelectorFechaVentas(
      context: context,
      fechaSeleccionada: _fechaSeleccionada,
      fechasHabilitadas: _fechasConDatos,
      fechasConDeuda: _fechasConDeuda,
    );
    if (elegida == null) return;
    setState(() {
      _fechaSeleccionada = elegida;
      _verTodo = false;
    });
  }

  void _alternarVerTodo() => setState(() => _verTodo = !_verTodo);

  void _alternarSeccion(String titulo) {
    setState(() {
      if (!_seccionesExpandidas.remove(titulo)) {
        _seccionesExpandidas.add(titulo);
      }
    });
  }

  List<Pedido> _filtrar(bool Function(Pedido) filtroEstado) {
    final lista = _pedidos.where((p) {
      if (!filtroEstado(p)) return false;
      if (_verTodo) return true;
      final fecha = p.fechaEntregaReal ?? p.fechaCreacion;
      return _mismoDia(fecha, _fechaSeleccionada);
    }).toList()..sort(
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

    final pagados = _filtrar(
      (p) => p.estado == 'ENTREGADO' && p.estadoPago == 'PAGADO',
    );
    final deuda = _filtrar(
      (p) => p.estado == 'ENTREGADO' && p.estadoPago == 'DEUDA',
    );
    final cancelados = _filtrar((p) => p.estado == 'CANCELADO');
    final rechazados = _filtrar((p) => p.estado == 'RECHAZADO');

    final cobradoCantidad = pagados.length;
    final cobradoTotal = pagados.fold(0.0, (a, p) => a + p.total);
    final deudaCantidad = deuda.length;
    final deudaTotal = deuda.fold(0.0, (a, p) => a + p.total);

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          Row(
            children: [
              Expanded(
                child: _SelectorFecha(
                  fecha: _fechaSeleccionada,
                  verTodo: _verTodo,
                  habilitado: _fechasConDatos.isNotEmpty,
                  onTap: _seleccionarFecha,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _alternarVerTodo,
                style: OutlinedButton.styleFrom(
                  backgroundColor: _verTodo
                      ? AppColors.primary.withValues(alpha: 0.12)
                      : null,
                ),
                child: Text(_verTodo ? 'Ver por día' : 'Ver todo'),
              ),
            ],
          ).animate().fadeIn(delay: 60.ms, duration: 300.ms),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: 380.ms,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.08),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
                ),
                child: child,
              ),
            ),
            child: Row(
              key: ValueKey(
                _verTodo
                    ? 'todo'
                    : _fechaSeleccionada.toIso8601String().split('T').first,
              ),
              children: [
                Expanded(
                  child: _TarjetaMontoDia(
                    titulo: _verTodo ? 'Cobrado (total)' : 'Cobrado',
                    icono: Icons.trending_up_rounded,
                    colores: const [AppColors.primary, AppColors.secondary],
                    cantidad: cobradoCantidad,
                    total: cobradoTotal,
                    etiquetaCantidad: 'cobrado(s)',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TarjetaMontoDia(
                    titulo: _verTodo ? 'Deuda (total)' : 'Deuda del día',
                    icono: Icons.account_balance_wallet_rounded,
                    colores: const [Color(0xFFC62828), Color(0xFFE57373)],
                    cantidad: deudaCantidad,
                    total: deudaTotal,
                    etiquetaCantidad: 'con deuda',
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(delay: 100.ms, duration: 450.ms),
          const SizedBox(height: 20),
          if (pagados.isEmpty &&
              deuda.isEmpty &&
              cancelados.isEmpty &&
              rechazados.isEmpty)
            // Sin onRefrescar a propósito: EstadoVacio arma su propio
            // RefreshIndicator+LayoutBuilder(constraints.maxHeight) pensado
            // para ser el cuerpo ENTERO de la pantalla — anidado adentro de
            // este ListView (que ya tiene su propio RefreshIndicator más
            // arriba, junto al selector de fecha) esa altura queda infinita
            // y el contenido se renderiza superpuesto.
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: EstadoVacio(
                icono: Icons.receipt_long_rounded,
                titulo: _verTodo
                    ? 'Todavía no hay ventas en el historial'
                    : 'No hay ventas resueltas este día',
                subtitulo: _verTodo
                    ? 'Los pedidos entregados, cancelados o rechazados de esta tienda van a aparecer acá.'
                    : 'Prueba "Ver todo" o elige otro día en el calendario.',
              ),
            )
          else ...[
            _SeccionHistorial(
              titulo: 'Completados y pagados',
              subtitulo: 'Entregados y ya cobrados',
              icono: Icons.check_circle_rounded,
              color: const Color(0xFF2E7D32),
              pedidos: pagados,
              expandida: _seccionesExpandidas.contains('Completados y pagados'),
              onToggle: () => _alternarSeccion('Completados y pagados'),
            ),
            _SeccionHistorial(
              titulo: 'Con deuda',
              subtitulo: 'Entregados, el cliente todavía debe',
              icono: Icons.account_balance_wallet_rounded,
              color: const Color(0xFFC62828),
              pedidos: deuda,
              expandida: _seccionesExpandidas.contains('Con deuda'),
              onToggle: () => _alternarSeccion('Con deuda'),
            ),
            _SeccionHistorial(
              titulo: 'Cancelados',
              subtitulo: 'No llegaron a entregarse',
              icono: Icons.block_rounded,
              color: const Color(0xFF6D4C41),
              pedidos: cancelados,
              expandida: _seccionesExpandidas.contains('Cancelados'),
              onToggle: () => _alternarSeccion('Cancelados'),
            ),
            _SeccionHistorial(
              titulo: 'Rechazados',
              subtitulo: 'El personal no los aceptó',
              icono: Icons.cancel_rounded,
              color: AppColors.textSecondary,
              pedidos: rechazados,
              expandida: _seccionesExpandidas.contains('Rechazados'),
              onToggle: () => _alternarSeccion('Rechazados'),
            ),
          ],
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

/// Sección plegable: el encabezado (con el conteo) siempre se ve; la lista
/// de tarjetas solo se arma y se muestra cuando [expandida] es true — así
/// el historial no abruma con todo desglosado apenas se abre la pantalla.
class _SeccionHistorial extends StatelessWidget {
  const _SeccionHistorial({
    required this.titulo,
    required this.subtitulo,
    required this.icono,
    required this.color,
    required this.pedidos,
    required this.expandida,
    required this.onToggle,
  });

  final String titulo;
  final String subtitulo;
  final IconData icono;
  final Color color;
  final List<Pedido> pedidos;
  final bool expandida;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    if (pedidos.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(icono, color: color, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      titulo,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
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
                    const Spacer(),
                    AnimatedRotation(
                      turns: expandida ? 0.5 : 0,
                      duration: 220.ms,
                      child: Icon(
                        Icons.expand_more_rounded,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Text(subtitulo, style: theme.textTheme.bodyMedium),
          ),
          if (expandida) ...[
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
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                cliente.nombreParaMostrar,
                                style: theme.textTheme.titleMedium,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '#${pedido.numeroPedidoDia}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
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
              NotaPedido(pedido: pedido),
              InfoAuditoriaPedido(pedido: pedido),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chip que muestra el día elegido (o "Todo el historial" si [verTodo] está
/// activo) y abre el calendario al tocarlo — solo permite elegir días con
/// ventas registradas (ver [_HistorialVentasPageState._seleccionarFecha]).
class _SelectorFecha extends StatelessWidget {
  const _SelectorFecha({
    required this.fecha,
    required this.verTodo,
    required this.habilitado,
    required this.onTap,
  });

  final DateTime fecha;
  final bool verTodo;
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
    final etiqueta = verTodo
        ? 'Todo el historial'
        : _esHoy
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

/// Tarjeta compacta de dinero (cobrado o deuda) — dos de estas van lado a
/// lado arriba del historial. El ícono con pulso continuo le da ese aire
/// "vivo", sin exagerar.
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
