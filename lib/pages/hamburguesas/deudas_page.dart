import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../models/solicitud_pago_model.dart';
import '../../services/api_client.dart';
import '../../services/notificaciones_service.dart';
import '../../services/pedidos_service.dart';
import '../../services/solicitudes_pago_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/fecha_pedido_utils.dart';
import '../../widgets/estado_error.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/tarjeta_3d.dart';

/// Deudas pendientes (pedidos ENTREGADO con EstadoPago=DEUDA) de las
/// tiendas asignadas al personal, agrupadas por cliente con su total —
/// arriba de todo, los pagos que el cliente ya reportó (o generó un QR
/// para) desde su propia app, esperando confirmación. El pago sin reporte
/// digital solo puede confirmarse a mano (efectivo/Yape ya recibido en
/// persona).
class DeudasPage extends StatefulWidget {
  const DeudasPage({super.key});

  @override
  State<DeudasPage> createState() => _DeudasPageState();
}

class _DeudasPageState extends State<DeudasPage> {
  final _pedidosService = PedidosService();
  final _solicitudesPagoService = SolicitudesPagoService();

  List<Pedido> _deudas = [];
  List<SolicitudPagoPendiente> _solicitudes = [];
  bool _cargando = true;
  String? _error;

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
        _pedidosService.listarDeudas(),
        _solicitudesPagoService.listarPendientes(),
      ]);
      setState(() {
        _deudas = resultados[0] as List<Pedido>;
        _solicitudes = resultados[1] as List<SolicitudPagoPendiente>;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(() => _error = 'No se pudieron cargar las deudas.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _confirmarSolicitud(SolicitudPagoPendiente solicitud) async {
    try {
      await _solicitudesPagoService.confirmar(solicitud.idSolicitudPago);
      NotificacionesService.avisarCambioPedido();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Pago de ${solicitud.nombreParaMostrar} confirmado.'),
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

  Future<void> _rechazarSolicitud(SolicitudPagoPendiente solicitud) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rechazar pago'),
        content: Text(
          '¿Seguro que no encontraste la transferencia de ${solicitud.nombreParaMostrar} por S/ ${solicitud.montoTotal.toStringAsFixed(2)}?',
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
      await _solicitudesPagoService.rechazar(solicitud.idSolicitudPago);
      NotificacionesService.avisarCambioPedido();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Pago rechazado.')));
      _cargar();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.mensaje)));
    }
  }

  Future<void> _marcarPagada(Pedido pedido) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Marcar deuda como pagada'),
        content: Text(
          '¿Confirmas que el pedido #${pedido.idPedido} por S/ ${pedido.total.toStringAsFixed(2)} ya fue pagado por el cliente?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirmar pago'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await _pedidosService.marcarDeudaPagada(pedido.idPedido);
      NotificacionesService.avisarCambioPedido();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Deuda del pedido #${pedido.idPedido} saldada.'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Deudas')),
      body: SafeArea(child: _construirCuerpo()),
    );
  }

  Widget _construirCuerpo() {
    final theme = Theme.of(context);

    if (_cargando) return const Center(child: AppLoadingIndicator());

    if (_error != null) {
      return EstadoError(mensaje: _error!, onReintentar: _cargar);
    }

    if (_deudas.isEmpty && _solicitudes.isEmpty) {
      return EstadoVacio(
        icono: Icons.check_circle_outline_rounded,
        titulo: 'No hay deudas pendientes',
        subtitulo: 'Cuando algún pedido quede como deuda, aparece acá.',
        onRefrescar: _cargar,
      );
    }

    final grupos = _agruparPorCliente(_deudas);

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          if (_solicitudes.isNotEmpty) ...[
            Row(
              children: [
                const Icon(
                  Icons.qr_code_2_rounded,
                  color: Color(0xFFEA8C1B),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Pagos reportados',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: const Color(0xFFEA8C1B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(left: 28),
              child: Text(
                'Revisa y confirma según tu Yape/Plin/cuenta',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 10),
            ..._solicitudes.asMap().entries.map(
              (entry) =>
                  _TarjetaSolicitudPago(
                        solicitud: entry.value,
                        onConfirmar: () => _confirmarSolicitud(entry.value),
                        onRechazar: () => _rechazarSolicitud(entry.value),
                      )
                      .animate(delay: (60 * entry.key).ms)
                      .fadeIn(duration: 300.ms)
                      .moveY(begin: 10, end: 0)
                      .flipH(begin: 0.12, end: 0, duration: 320.ms),
            ),
            const SizedBox(height: 20),
          ],
          ...grupos.asMap().entries.map(
            (entry) =>
                _GrupoDeudaCliente(
                      grupo: entry.value,
                      onMarcarPagada: _marcarPagada,
                    )
                    .animate(delay: (60 * entry.key).ms)
                    .fadeIn(duration: 300.ms)
                    .moveY(begin: 10, end: 0),
          ),
        ],
      ),
    );
  }

  List<_GrupoDeuda> _agruparPorCliente(List<Pedido> deudas) {
    final mapa = <int, List<Pedido>>{};
    for (final pedido in deudas) {
      mapa.putIfAbsent(pedido.idCliente, () => []).add(pedido);
    }
    final grupos = mapa.entries
        .map(
          (e) => _GrupoDeuda(cliente: e.value.first.cliente, pedidos: e.value),
        )
        .toList();
    grupos.sort((a, b) => b.total.compareTo(a.total));
    return grupos;
  }
}

class _GrupoDeuda {
  _GrupoDeuda({required this.cliente, required this.pedidos});
  final PedidoClienteResumen cliente;
  final List<Pedido> pedidos;
  double get total => pedidos.fold(0.0, (acc, p) => acc + p.total);
}

class _TarjetaSolicitudPago extends StatelessWidget {
  const _TarjetaSolicitudPago({
    required this.solicitud,
    required this.onConfirmar,
    required this.onRechazar,
  });

  final SolicitudPagoPendiente solicitud;
  final VoidCallback onConfirmar;
  final VoidCallback onRechazar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Tarjeta3D(
        borderRadius: 18,
        child: Container(
          color: AppColors.surface,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          solicitud.nombreParaMostrar,
                          style: theme.textTheme.titleMedium,
                        ),
                        Text(
                          '${solicitud.medioPago} · Ref: ${solicitud.codigoReferencia}',
                          style: theme.textTheme.bodyMedium,
                        ),
                        Text(
                          solicitud.estado == 'REPORTADO'
                              ? 'El cliente ya reportó el pago'
                              : 'Aún no lo reporta',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'S/ ${solicitud.montoTotal.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onRechazar,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFC62828),
                      ),
                      child: const Text('Rechazar'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: onConfirmar,
                      child: const Text('Confirmar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GrupoDeudaCliente extends StatelessWidget {
  const _GrupoDeudaCliente({required this.grupo, required this.onMarcarPagada});

  final _GrupoDeuda grupo;
  final ValueChanged<Pedido> onMarcarPagada;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nombreComercial = grupo.cliente.nombreComercial;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Tarjeta3D(
        child: Container(
          color: AppColors.surface,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          grupo.cliente.nombreParaMostrar,
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
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFC62828).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'S/ ${grupo.total.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Color(0xFFC62828),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 20),
              ...grupo.pedidos.map(
                (pedido) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pedido #${pedido.idPedido} · S/ ${pedido.total.toStringAsFixed(2)}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (pedido.fechaEntregaReal != null)
                              Text(
                                'Entregado el ${formatearFechaEntrega(pedido.fechaEntregaReal!)}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontSize: 12,
                                ),
                              ),
                            // Solo llega si quien ve esta pantalla es
                            // ADMIN/SUPERADMIN (el backend lo filtra según
                            // el rol, ver pedidosController.js).
                            if (pedido.entregadoPor != null)
                              Text(
                                'Entregado por: ${pedido.entregadoPor}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ),
                      OutlinedButton(
                        onPressed: () => onMarcarPagada(pedido),
                        child: const Text('Marcar pagada'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
