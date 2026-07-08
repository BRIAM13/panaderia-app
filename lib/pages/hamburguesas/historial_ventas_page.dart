import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../models/tienda_model.dart';
import '../../services/api_client.dart';
import '../../services/pedidos_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/fecha_pedido_utils.dart';
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

  bool _cargando = true;
  String? _error;
  List<Pedido> _pedidos = [];

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
      final pedidos = await _pedidosService.listar();
      if (!mounted) return;
      setState(() {
        _pedidos = pedidos
            .where(
              (p) => p.idTienda == widget.tienda.idTienda && p.esFinalizado,
            )
            .toList();
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 44,
                color: AppColors.error.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _cargar, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
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
      return _EstadoVacioHistorial(onRefrescar: _cargar);
    }

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
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

class _EstadoVacioHistorial extends StatelessWidget {
  const _EstadoVacioHistorial({required this.onRefrescar});

  final Future<void> Function() onRefrescar;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefrescar,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                AppColors.primary.withValues(alpha: 0.18),
                                AppColors.secondary.withValues(alpha: 0.10),
                              ],
                            ),
                          ),
                          child: const Icon(
                            Icons.receipt_long_rounded,
                            size: 40,
                            color: AppColors.primary,
                          ),
                        )
                        .animate()
                        .fadeIn(duration: 350.ms)
                        .scale(
                          begin: const Offset(0.85, 0.85),
                          end: const Offset(1, 1),
                        ),
                    const SizedBox(height: 16),
                    Text(
                      'Todavía no hay ventas en el historial',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ).animate().fadeIn(delay: 100.ms, duration: 300.ms),
                    const SizedBox(height: 6),
                    Text(
                      'Los pedidos entregados, cancelados o rechazados de '
                      'esta tienda van a aparecer acá.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ).animate().fadeIn(delay: 140.ms, duration: 300.ms),
                  ],
                ),
              ),
            ),
          ),
        ),
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
