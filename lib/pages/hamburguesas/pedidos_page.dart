import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../models/tienda_model.dart';
import '../../services/api_client.dart';
import '../../services/notificaciones_service.dart';
import '../../services/pedidos_service.dart';
import '../../widgets/estado_error.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/pedidos_secciones.dart';
import 'nuevo_pedido_page.dart';

/// Dashboard de Pedidos para el personal de una tienda de catálogo simple
/// (Hamburguesas o Panadería — Horneados tiene su propia página): primero
/// "Por confirmar" (solicitados por clientes, esperando aceptar/rechazar
/// según stock), después el resto agrupado en Atrasados / Hoy / Próximos /
/// Sin fecha. Para la vista del propio cliente ver `MisPedidosPendientesPage`.
class PedidosPage extends StatefulWidget {
  const PedidosPage({super.key, required this.tienda});

  final Tienda tienda;

  @override
  State<PedidosPage> createState() => _PedidosPageState();
}

class _PedidosPageState extends State<PedidosPage> {
  final _pedidosService = PedidosService();
  StreamSubscription<void>? _suscripcionPush;

  List<Pedido> _pedidos = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
    // Recarga sola apenas llega una notificación de cambio de pedido (nuevo
    // solicitado, cancelado, etc.) — antes había que deslizar a mano para
    // ver el cambio recién notificado.
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
      final pedidos = await _pedidosService.listar(
        idTienda: widget.tienda.idTienda,
      );
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
      (_) => NuevoPedidoPage(tienda: widget.tienda),
    );
    if (registrado == true) _cargar();
  }

  Future<void> _aprobar(Pedido pedido) async {
    try {
      await _pedidosService.aprobar(pedido.idPedido);
      NotificacionesService.avisarCambioPedido();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pedido #${pedido.numeroPedidoDia} confirmado.')),
      );
      _cargar();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.mensaje)));
    }
  }

  Future<void> _rechazar(Pedido pedido) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rechazar pedido'),
        content: Text(
          '¿Seguro que quieres rechazar el pedido #${pedido.numeroPedidoDia}? Se avisará al cliente y no podrá deshacerse.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await _pedidosService.rechazar(pedido.idPedido);
      NotificacionesService.avisarCambioPedido();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pedido #${pedido.numeroPedidoDia} rechazado.')),
      );
      _cargar();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.mensaje)));
    }
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
      appBar: AppBar(title: const Text('Pedidos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nuevoPedido,
        icon: const Icon(Icons.add_shopping_cart_rounded),
        label: const Text('Nuevo pedido'),
      ),
      body: SafeArea(child: _construirCuerpo()),
    );
  }

  Widget _construirCuerpo() {
    final theme = Theme.of(context);

    if (_cargando) {
      return const Center(child: AppLoadingIndicator());
    }

    if (_error != null) {
      return EstadoError(mensaje: _error!, onReintentar: _cargar);
    }

    if (_pedidos.isEmpty) {
      return EstadoVacio(
        icono: Icons.receipt_long_rounded,
        titulo: 'Aún no hay pedidos registrados',
        subtitulo: 'Los pedidos de tus tiendas van a aparecer acá.',
        onRefrescar: _cargar,
      );
    }

    final solicitados = _pedidos.where((p) => p.esSolicitado).toList();
    final resto = _pedidos.where((p) => !p.esSolicitado).toList();

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
        children: [
          if (solicitados.isNotEmpty) ...[
            Row(
              children: [
                const Icon(
                  Icons.hourglass_top_rounded,
                  color: Color(0xFFEA8C1B),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Por confirmar',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: const Color(0xFFEA8C1B),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEA8C1B).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${solicitados.length}',
                    style: const TextStyle(
                      color: Color(0xFFEA8C1B),
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
              child: Text(
                'Solicitados por clientes — revisa el stock',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 10),
            ...solicitados.asMap().entries.map(
              (entry) =>
                  PedidoCard(
                        pedido: entry.value,
                        colorSeccion: const Color(0xFFEA8C1B),
                        onAprobar: () => _aprobar(entry.value),
                        onRechazar: () => _rechazar(entry.value),
                      )
                      .animate(delay: (40 * entry.key).ms)
                      .fadeIn(duration: 250.ms)
                      .moveY(begin: 8, end: 0),
            ),
            const SizedBox(height: 10),
          ],
          ListaPedidosPorSeccion(
            pedidos: resto,
            onEntregar: _entregar,
            onCancelar: _cancelar,
          ),
        ],
      ),
    );
  }
}
