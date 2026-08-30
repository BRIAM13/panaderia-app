import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../services/api_client.dart';
import '../../services/horneados_service.dart';
import '../../services/notificaciones_service.dart';
import '../../services/pedidos_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../utils/fecha_pedido_utils.dart';
import '../../widgets/estado_error.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/pedidos_secciones.dart';
import '../../widgets/tarjeta_3d.dart';
import 'nuevo_pedido_horneados_page.dart';

/// Lista de pedidos de Horneados para el personal — mismo tema visual y
/// mismas acciones (entregar/cancelar) que Pedidos de Hamburguesas, pero
/// con la tarjeta propia de este rubro (carne, presentación, aderezo). Las
/// acciones pegan directo a los endpoints ya genéricos de
/// `PedidosService` — no son exclusivos de Hamburguesas, solo resuelven la
/// tienda real de cada pedido (ver pedidosController.js).
class PedidosHorneadosPage extends StatefulWidget {
  const PedidosHorneadosPage({super.key});

  @override
  State<PedidosHorneadosPage> createState() => _PedidosHorneadosPageState();
}

class _PedidosHorneadosPageState extends State<PedidosHorneadosPage> {
  final _horneadosService = HorneadosService();
  final _pedidosService = PedidosService();
  StreamSubscription<void>? _suscripcionPush;

  List<PedidoHorneado> _pedidos = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
    _suscripcionPush = NotificacionesService.eventosPedido.listen(
      (_) => _cargar(silencioso: true),
    );
  }

  @override
  void dispose() {
    _suscripcionPush?.cancel();
    super.dispose();
  }

  Future<void> _cargar({bool silencioso = false}) async {
    if (!silencioso) {
      setState(() {
        _cargando = true;
        _error = null;
      });
    }
    try {
      final pedidos = await _horneadosService.listarPedidos();
      if (mounted) setState(() => _pedidos = pedidos);
    } on ApiException catch (e) {
      if (!silencioso) setState(() => _error = e.mensaje);
    } catch (_) {
      if (!silencioso) {
        setState(() => _error = 'No se pudo cargar la lista de pedidos.');
      }
    } finally {
      if (mounted && !silencioso) setState(() => _cargando = false);
    }
  }

  Future<void> _nuevoPedido() async {
    final registrado = await pushSlideUpFade<bool>(
      context,
      (_) => const NuevoPedidoHorneadosPage(),
    );
    if (registrado == true) _cargar();
  }

  Future<void> _entregar(Pedido pedido) async {
    final pagado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Marcar como entregado'),
        content: Text(
          '¿El pedido #${pedido.numeroPedidoDia} se pagó al momento de entregarlo?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Queda como deuda'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sí, pagado'),
          ),
        ],
      ),
    );
    if (pagado == null) return;

    try {
      await _pedidosService.entregar(pedido.idPedido, pagado: pagado);
      NotificacionesService.avisarCambioPedido();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            pagado
                ? 'Pedido #${pedido.numeroPedidoDia} entregado y pagado.'
                : 'Pedido #${pedido.numeroPedidoDia} entregado — queda como deuda.',
          ),
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

  Future<void> _cancelar(Pedido pedido) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar pedido'),
        content: Text(
          '¿Seguro que quieres cancelar el pedido #${pedido.numeroPedidoDia}? '
          'Se avisará al cliente y no podrá deshacerse.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await _pedidosService.cancelar(pedido.idPedido);
      NotificacionesService.avisarCambioPedido();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pedido #${pedido.numeroPedidoDia} cancelado.')),
      );
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
      appBar: AppBar(title: const Text('Pedidos de Horneados')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nuevoPedido,
        icon: const Icon(Icons.add_shopping_cart_rounded),
        label: const Text('Nuevo pedido'),
      ),
      body: SafeArea(child: _construirCuerpo()),
    );
  }

  Widget _construirCuerpo() {
    if (_cargando) {
      return const Center(child: AppLoadingIndicator());
    }
    if (_error != null) {
      return EstadoError(mensaje: _error!, onReintentar: _cargar);
    }
    if (_pedidos.isEmpty) {
      return EstadoVacio(
        icono: Icons.bakery_dining_rounded,
        titulo: 'Aún no hay pedidos de Horneados',
        subtitulo: 'Los pedidos que registres van a aparecer acá.',
        onRefrescar: _cargar,
      );
    }

    // Hay pedidos, pero todos ya se resolvieron — sin este chequeo la
    // lista de secciones quedaba en blanco (cada una se oculta sola si no
    // tiene pedidos activos) en vez de avisar que no hay nada pendiente.
    if (_pedidos.every((p) => p.pedido.esFinalizado)) {
      return EstadoVacio(
        icono: Icons.task_alt_rounded,
        titulo: 'No hay pedidos pendientes',
        subtitulo: 'Todos los pedidos de Horneados ya se resolvieron.',
        onRefrescar: _cargar,
      );
    }

    final activos = _pedidos.where((p) => !p.pedido.esFinalizado).toList();
    final agrupados = agruparPedidosPorFecha(
      activos.map((p) => p.pedido).toList(),
    );
    final porId = {for (final p in _pedidos) p.pedido.idPedido: p};

    Widget seccion(String titulo, String subtitulo, IconData icono, Color color, List<dynamic> pedidosSeccion) {
      final lista = pedidosSeccion.cast<Pedido>();
      if (lista.isEmpty) return const SizedBox.shrink();
      final theme = Theme.of(context);
      final esEscritorio = MediaQuery.sizeOf(context).width >= Breakpoints.tablet;

      final tarjetas = lista.asMap().entries.map((entry) {
        final horneado = porId[entry.value.idPedido]!;
        return _PedidoHorneadoCard(
          horneado: horneado,
          colorSeccion: color,
          onEntregar: entry.value.estado == 'PENDIENTE'
              ? () => _entregar(entry.value)
              : null,
          onCancelar: entry.value.sePuedeCancelar
              ? () => _cancelar(entry.value)
              : null,
        ).animate(delay: (40 * entry.key).ms).fadeIn(duration: 250.ms).moveY(begin: 8, end: 0);
      });

      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icono, color: color, size: 20),
                const SizedBox(width: 8),
                Text(titulo, style: theme.textTheme.titleMedium?.copyWith(color: color)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${lista.length}',
                    style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
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
            if (!esEscritorio)
              Column(children: tarjetas.toList())
            else
              Wrap(
                spacing: 12,
                children: tarjetas.map((t) => SizedBox(width: 380, child: t)).toList(),
              ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
        children: [
          seccion('Atrasados', 'De ayer o antes — necesitan atención', Icons.warning_amber_rounded, const Color(0xFFC62828), agrupados[SeccionPedido.atrasados]!),
          seccion('Hoy', 'Programados para entregarse hoy', Icons.today_rounded, AppColors.primary, agrupados[SeccionPedido.hoy]!),
          seccion('Próximos', 'Mañana en adelante', Icons.upcoming_rounded, const Color(0xFF2563EB), agrupados[SeccionPedido.proximos]!),
          seccion('Sin fecha programada', 'A coordinar con el cliente', Icons.event_busy_rounded, AppColors.textSecondary, agrupados[SeccionPedido.sinFecha]!),
        ],
      ),
    );
  }
}

class _EstadoInfo {
  const _EstadoInfo(this.texto, this.color, this.icono);
  final String texto;
  final Color color;
  final IconData icono;
}

_EstadoInfo _infoEstado(Pedido pedido) {
  switch (pedido.estado) {
    case 'CANCELADO':
      return const _EstadoInfo('Cancelado', Color(0xFF6D4C41), Icons.block_rounded);
    case 'ENTREGADO':
      return pedido.esDeuda
          ? const _EstadoInfo('Entregado · Deuda', Color(0xFFC62828), Icons.account_balance_wallet_rounded)
          : const _EstadoInfo('Entregado · Pagado', Color(0xFF2E7D32), Icons.check_circle_rounded);
    default:
      return const _EstadoInfo('Pendiente a entrega', Color(0xFF2563EB), Icons.event_available_rounded);
  }
}

class _PedidoHorneadoCard extends StatelessWidget {
  const _PedidoHorneadoCard({
    required this.horneado,
    required this.colorSeccion,
    this.onEntregar,
    this.onCancelar,
  });

  final PedidoHorneado horneado;
  final Color colorSeccion;
  final VoidCallback? onEntregar;
  final VoidCallback? onCancelar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pedido = horneado.pedido;
    final cliente = pedido.cliente;
    final nombreComercial = cliente.nombreComercial;
    final estadoInfo = _infoEstado(pedido);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Tarjeta3D(
        borderRadius: 20,
        child: Container(
          color: AppColors.surface,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          colorSeccion.withValues(alpha: 0.20),
                          colorSeccion.withValues(alpha: 0.08),
                        ],
                      ),
                    ),
                    child: Icon(Icons.bakery_dining_rounded, color: colorSeccion, size: 20),
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
                        if (nombreComercial != null) ...[
                          const SizedBox(height: 1),
                          Text(
                            nombreComercial,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.secondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          '${horneado.carne ?? '—'} · ${horneado.presentacion ?? '—'} · ${pedido.cantidad}',
                          style: theme.textTheme.bodyMedium,
                        ),
                        if (horneado.aplicaAderezo) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Aderezo ${horneado.tipoAderezo ?? ''} · S/ ${(horneado.precioAderezo ?? 0).toStringAsFixed(2)}',
                            style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                        const SizedBox(height: 2),
                        Text(
                          'Total S/ ${pedido.total.toStringAsFixed(2)}',
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              pedido.fechaEntrega != null ? Icons.schedule_rounded : Icons.event_busy_rounded,
                              size: 14,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                pedido.fechaEntrega != null
                                    ? formatearFechaEntrega(pedido.fechaEntrega!)
                                    : 'Sin fecha programada',
                                style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: estadoInfo.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(estadoInfo.icono, size: 13, color: estadoInfo.color),
                        const SizedBox(width: 4),
                        Text(
                          estadoInfo.texto,
                          style: TextStyle(color: estadoInfo.color, fontWeight: FontWeight.w700, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              NotaPedido(pedido: pedido),
              InfoAuditoriaPedido(pedido: pedido),
              if (onEntregar != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onEntregar,
                    icon: const Icon(Icons.local_shipping_rounded, size: 18),
                    label: const Text('Marcar entregado'),
                  ),
                ),
              ],
              if (onCancelar != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onCancelar,
                    style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFC62828)),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Cancelar pedido'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
