import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../models/tienda_model.dart';
import '../../services/api_client.dart';
import '../../services/notificaciones_service.dart';
import '../../services/pedidos_service.dart';
import '../../theme/breakpoints.dart';
import '../../widgets/escritorio.dart';
import '../../widgets/estado_error.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/pedidos_secciones.dart';
import '../../widgets/premium_button.dart';
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
        SnackBar(
          content: Text('Pedido #${pedido.numeroPedidoDia} confirmado.'),
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
    final escritorio = esEscritorio(context);

    return Scaffold(
      // En escritorio la acción principal sube al AppBar: un FAB flotando
      // en la esquina inferior derecha de un monitor de 1600px queda lejos
      // de todo y tapa la última tarjeta de la lista.
      appBar: appBarGestion(
        context,
        titulo: 'Pedidos',
        subtitulo: _resumenCabecera(),
        acciones: [
          if (escritorio)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: PremiumButton(
                label: 'Nuevo pedido',
                icono: PhosphorIconsBold.shoppingCartSimple,
                expandido: false,
                onPressed: _nuevoPedido,
              ),
            ),
        ],
      ),
      floatingActionButton: escritorio
          ? null
          : FloatingActionButton.extended(
              onPressed: _nuevoPedido,
              icon: const PhosphorIcon(PhosphorIconsBold.shoppingCartSimple),
              label: const Text('Nuevo pedido'),
            ),
      body: SafeArea(child: _construirCuerpo()),
    );
  }

  /// Bajada del AppBar en escritorio — de un vistazo, cuántos pedidos
  /// esperan una decisión ahora mismo, sin tener que contar tarjetas.
  String? _resumenCabecera() {
    if (_cargando || _error != null || _pedidos.isEmpty) return null;
    final porConfirmar = _pedidos.where((p) => p.esSolicitado).length;
    final activos = _pedidos.where((p) => !p.esFinalizado).length;
    if (activos == 0) return 'Todo al día — no hay pedidos pendientes';
    final partes = <String>[
      '$activos pendiente${activos == 1 ? '' : 's'}',
      if (porConfirmar > 0) '$porConfirmar por confirmar',
    ];
    return partes.join(' · ');
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
        icono: PhosphorIconsRegular.receipt,
        titulo: 'Aún no hay pedidos registrados',
        subtitulo: 'Los pedidos de tus tiendas van a aparecer acá.',
        onRefrescar: _cargar,
      );
    }

    // Hay pedidos, pero todos ya se resolvieron (entregado/rechazado/
    // cancelado) — sin este chequeo, la lista de abajo quedaba en blanco
    // (cada sección se oculta sola si no tiene pedidos activos) en vez de
    // avisar que no hay nada pendiente ahora mismo.
    if (_pedidos.every((p) => p.esFinalizado)) {
      return EstadoVacio(
        icono: PhosphorIconsRegular.checkSquare,
        titulo: 'No hay pedidos pendientes',
        subtitulo:
            'Todos los pedidos ya se resolvieron. El historial está en Ventas de hoy.',
        onRefrescar: _cargar,
      );
    }

    final solicitados = _pedidos.where((p) => p.esSolicitado).toList();
    final resto = _pedidos.where((p) => !p.esSolicitado).toList();
    final escritorio = esEscritorio(context);
    const ambar = Color(0xFFEA8C1B);

    // "Por confirmar" es la cola de decisiones: son los pedidos que un
    // cliente mandó y están esperando que alguien acepte o rechace. En
    // escritorio se le da un bloque teñido propio para que se despegue del
    // resto de la lista, en vez de ser un encabezado más entre otros.
    final tarjetasSolicitados = solicitados.asMap().entries.map(
      (entry) =>
          PedidoCard(
                pedido: entry.value,
                colorSeccion: ambar,
                onAprobar: () => _aprobar(entry.value),
                onRechazar: () => _rechazar(entry.value),
              )
              .animate(delay: (40 * entry.key).ms)
              .fadeIn(duration: 250.ms)
              .moveY(begin: 8, end: 0),
    );

    final encabezadoSolicitados = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            PhosphorIcon(
              PhosphorIconsFill.hourglassHigh,
              color: ambar,
              size: escritorio ? 22 : 20,
            ),
            const SizedBox(width: 8),
            Text(
              'Por confirmar',
              style: theme.textTheme.titleMedium?.copyWith(
                color: ambar,
                fontSize: escritorio ? 18 : null,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: ambar.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${solicitados.length}',
                style: const TextStyle(
                  color: ambar,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
            if (escritorio) ...[
              const SizedBox(width: 14),
              Expanded(
                child: Container(
                  height: 1,
                  color: ambar.withValues(alpha: 0.20),
                ),
              ),
            ],
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
      ],
    );

    // Misma grilla justificada que usan las secciones de abajo, para que la
    // cola de decisiones no se vea con otra retícula que el resto — y desde
    // 600 px, no solo en escritorio (ver `anchoTarjetaPedido`).
    final grillaSolicitados = LayoutBuilder(
      builder: (context, constraints) {
        if (MediaQuery.sizeOf(context).width < Breakpoints.tablet) {
          return Column(children: tarjetasSolicitados.toList());
        }
        return Wrap(
          spacing: 14,
          runSpacing: 0,
          children: tarjetasSolicitados
              .map(
                (t) => SizedBox(
                  width: anchoTarjetaPedido(constraints.maxWidth),
                  child: t,
                ),
              )
              .toList(),
        );
      },
    );

    // El marco teñido no era una decoración de escritorio: es lo que hace
    // que la cola de decisiones se despegue del resto de la lista. En
    // celular, donde justamente hay MENOS contexto a la vista, era donde
    // más falta hacía y era el único sitio donde no estaba.
    final bloqueSolicitados = Container(
      padding: escritorio
          ? const EdgeInsets.fromLTRB(18, 16, 18, 6)
          : const EdgeInsets.fromLTRB(14, 14, 14, 4),
      decoration: BoxDecoration(
        color: ambar.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ambar.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          encabezadoSolicitados,
          SizedBox(height: escritorio ? 14 : 10),
          grillaSolicitados,
        ],
      ),
    );

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ContenidoCentrado(
        anchoMaximo: 1400,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            escritorio ? 28 : 20,
            escritorio ? 20 : 12,
            escritorio ? 28 : 20,
            escritorio ? 40 : 100,
          ),
          children: [
            if (solicitados.isNotEmpty) ...[
              bloqueSolicitados,
              SizedBox(height: escritorio ? 28 : 10),
            ],
            ListaPedidosPorSeccion(
              pedidos: resto,
              onEntregar: _entregar,
              onCancelar: _cancelar,
            ),
          ],
        ),
      ),
    );
  }
}
