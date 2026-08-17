import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../services/api_client.dart';
import '../../services/horneados_service.dart';
import '../../services/notificaciones_service.dart';
import '../../services/pedidos_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/fecha_pedido_utils.dart';
import '../../widgets/estado_error.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/pedidos_secciones.dart';
import '../../widgets/tarjeta_3d.dart';

/// Deudas pendientes (pedidos ENTREGADO con EstadoPago=DEUDA) de Horneados,
/// agrupadas por cliente — mismo tema que Deudas de Hamburguesas, pero sin
/// la sección de pagos reportados por QR (ese flujo de Yape/Plin todavía
/// no está conectado a Horneados).
class DeudasHorneadosPage extends StatefulWidget {
  const DeudasHorneadosPage({super.key});

  @override
  State<DeudasHorneadosPage> createState() => _DeudasHorneadosPageState();
}

class _DeudasHorneadosPageState extends State<DeudasHorneadosPage> {
  final _horneadosService = HorneadosService();
  final _pedidosService = PedidosService();

  List<PedidoHorneado> _deudas = [];
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
      final deudas = await _horneadosService.listarDeudas();
      if (mounted) setState(() => _deudas = deudas);
    } on ApiException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(() => _error = 'No se pudieron cargar las deudas.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _marcarPagada(PedidoHorneado horneado) async {
    final pedido = horneado.pedido;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Marcar deuda como pagada'),
        content: Text(
          '¿Confirmas que el pedido #${pedido.numeroPedidoDia} por S/ ${pedido.total.toStringAsFixed(2)} ya fue pagado por el cliente?',
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
        SnackBar(content: Text('Deuda del pedido #${pedido.numeroPedidoDia} saldada.')),
      );
      _cargar();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.mensaje)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Deudas de Horneados')),
      body: SafeArea(child: _construirCuerpo()),
    );
  }

  Widget _construirCuerpo() {
    if (_cargando) return const Center(child: AppLoadingIndicator());
    if (_error != null) {
      return EstadoError(mensaje: _error!, onReintentar: _cargar);
    }
    if (_deudas.isEmpty) {
      return EstadoVacio(
        icono: Icons.check_circle_outline_rounded,
        titulo: 'No hay deudas pendientes',
        subtitulo: 'Cuando algún pedido de Horneados quede como deuda, aparece acá.',
        onRefrescar: _cargar,
      );
    }

    final grupos = _agruparPorCliente(_deudas);

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: grupos
            .asMap()
            .entries
            .map(
              (entry) => _GrupoDeudaHorneado(
                    grupo: entry.value,
                    onMarcarPagada: _marcarPagada,
                  )
                  .animate(delay: (60 * entry.key).ms)
                  .fadeIn(duration: 300.ms)
                  .moveY(begin: 10, end: 0),
            )
            .toList(),
      ),
    );
  }

  List<_GrupoDeuda> _agruparPorCliente(List<PedidoHorneado> deudas) {
    final mapa = <int, List<PedidoHorneado>>{};
    for (final horneado in deudas) {
      mapa.putIfAbsent(horneado.pedido.idCliente, () => []).add(horneado);
    }
    final grupos = mapa.entries
        .map((e) => _GrupoDeuda(cliente: e.value.first.pedido.cliente, pedidos: e.value))
        .toList();
    grupos.sort((a, b) => b.total.compareTo(a.total));
    return grupos;
  }
}

class _GrupoDeuda {
  _GrupoDeuda({required this.cliente, required this.pedidos});
  final PedidoClienteResumen cliente;
  final List<PedidoHorneado> pedidos;
  double get total => pedidos.fold(0.0, (acc, p) => acc + p.pedido.total);
}

class _GrupoDeudaHorneado extends StatelessWidget {
  const _GrupoDeudaHorneado({required this.grupo, required this.onMarcarPagada});

  final _GrupoDeuda grupo;
  final ValueChanged<PedidoHorneado> onMarcarPagada;

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
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFC62828).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'S/ ${grupo.total.toStringAsFixed(2)}',
                      style: const TextStyle(color: Color(0xFFC62828), fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const Divider(height: 20),
              ...grupo.pedidos.map((horneado) {
                final pedido = horneado.pedido;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pedido #${pedido.numeroPedidoDia} · ${horneado.carne ?? '—'} · S/ ${pedido.total.toStringAsFixed(2)}',
                              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            if (pedido.fechaEntregaReal != null)
                              Text(
                                'Entregado el ${formatearFechaEntrega(pedido.fechaEntregaReal!)}',
                                style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                              ),
                            if (pedido.entregadoPor != null)
                              Text(
                                'Entregado por: ${pedido.entregadoPor}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            NotaPedido(pedido: pedido),
                          ],
                        ),
                      ),
                      OutlinedButton(
                        onPressed: () => onMarcarPagada(horneado),
                        child: const Text('Marcar pagada'),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
