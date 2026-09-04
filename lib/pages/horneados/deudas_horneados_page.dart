import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

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
import '../../widgets/escritorio.dart';

/// Color de "deuda" — el mismo rojo ladrillo que usa Hamburguesas.
const _rojoDeuda = Color(0xFFC62828);

/// Deudas pendientes (pedidos ENTREGADO con EstadoPago=DEUDA) de Horneados,
/// agrupadas por cliente — mismo tema que Deudas de Hamburguesas, pero sin
/// la sección de pagos reportados por QR (ese flujo de Yape/Plin todavía
/// no está conectado a Horneados).
///
/// En escritorio (>= [esEscritorio]) suma una fila de KPIs (total por
/// cobrar, clientes y pedidos involucrados) y reparte los grupos en 2/3
/// columnas con hover. Por debajo del umbral, el árbol es el de siempre.
class DeudasHorneadosPage extends StatefulWidget {
  const DeudasHorneadosPage({super.key});

  @override
  State<DeudasHorneadosPage> createState() => _DeudasHorneadosPageState();
}

class _DeudasHorneadosPageState extends State<DeudasHorneadosPage> {
  final _horneadosService = HorneadosService();
  final _pedidosService = PedidosService();

  List<Pedido> _deudas = [];
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

  Future<void> _marcarPagada(Pedido pedido) async {
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
      appBar: appBarGestion(context, titulo: 'Deudas de Horneados'),
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
        icono: PhosphorIconsLight.checkCircle,
        titulo: 'No hay deudas pendientes',
        subtitulo: 'Cuando algún pedido de Horneados quede como deuda, aparece acá.',
        onRefrescar: _cargar,
      );
    }

    final grupos = _agruparPorCliente(_deudas);

    if (!esEscritorio(context)) {
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

    final totalGeneral = grupos.fold(0.0, (acc, g) => acc + g.total);

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(32, 28, 32, 48),
        children: [
          ContenidoCentrado(
            anchoMaximo: 1440,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                EncabezadoEscritorio(
                      icono: PhosphorIconsDuotone.wallet,
                      titulo: 'Deudas de Horneados',
                      subtitulo:
                          'Pedidos ya entregados que quedaron por cobrar, '
                          'agrupados por cliente y ordenados por monto.',
                      acento: _rojoDeuda,
                      acciones: [
                        OutlinedButton.icon(
                          onPressed: _cargar,
                          icon: const PhosphorIcon(
                            PhosphorIconsRegular.arrowsClockwise,
                            size: 18,
                          ),
                          label: const Text('Actualizar'),
                        ),
                      ],
                    )
                    .animate()
                    .fadeIn(duration: 300.ms)
                    .moveY(begin: 10, end: 0),
                const SizedBox(height: 26),
                LayoutBuilder(
                  builder: (context, restricciones) {
                    final ancho = anchoColumna(restricciones.maxWidth, 3, 18);
                    final kpis = <Widget>[
                      TarjetaKpi(
                        icono: PhosphorIconsDuotone.coins,
                        titulo: 'Total por cobrar',
                        valor: 'S/ ${totalGeneral.toStringAsFixed(2)}',
                        color: _rojoDeuda,
                      ),
                      TarjetaKpi(
                        icono: PhosphorIconsDuotone.users,
                        titulo: 'Clientes con deuda',
                        valor: '${grupos.length}',
                        color: AppColors.primary,
                      ),
                      TarjetaKpi(
                        icono: PhosphorIconsDuotone.receipt,
                        titulo: 'Pedidos impagos',
                        valor: '${_deudas.length}',
                        color: AppColors.secondary,
                      ),
                    ];
                    return Wrap(
                      spacing: 18,
                      runSpacing: 18,
                      children: kpis
                          .asMap()
                          .entries
                          .map(
                            (entry) => SizedBox(
                              width: ancho,
                              child: entry.value
                                  .animate(delay: (70 * entry.key).ms)
                                  .fadeIn(duration: 280.ms)
                                  .moveY(begin: 10, end: 0),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
                const SizedBox(height: 30),
                LayoutBuilder(
                  builder: (context, restricciones) {
                    final columnas = columnasGrilla(
                      restricciones.maxWidth,
                      maximo: 3,
                      minimo: 420,
                    );
                    final ancho = anchoColumna(restricciones.maxWidth, columnas, 18);
                    return Wrap(
                      spacing: 18,
                      runSpacing: 4,
                      children: grupos
                          .asMap()
                          .entries
                          .map(
                            (entry) => SizedBox(
                              width: ancho,
                              child:
                                  _GrupoDeudaHorneado(
                                        grupo: entry.value,
                                        onMarcarPagada: _marcarPagada,
                                      )
                                      .animate(delay: (60 * entry.key).ms)
                                      .fadeIn(duration: 300.ms)
                                      .moveY(begin: 10, end: 0),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
              ],
            ),
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
        .map((e) => _GrupoDeuda(cliente: e.value.first.cliente, pedidos: e.value))
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

class _GrupoDeudaHorneado extends StatelessWidget {
  const _GrupoDeudaHorneado({required this.grupo, required this.onMarcarPagada});

  final _GrupoDeuda grupo;
  final ValueChanged<Pedido> onMarcarPagada;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nombreComercial = grupo.cliente.nombreComercial;

    final contenido = Column(
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
                color: _rojoDeuda.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'S/ ${grupo.total.toStringAsFixed(2)}',
                style: const TextStyle(color: _rojoDeuda, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const Divider(height: 20),
        ...grupo.pedidos.map((pedido) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // `productoResumen` ya viene armado con la carne de
                      // cada línea ("POLLO x2, CHANCHO x1") — acá es un
                      // subtítulo compacto de cobranza, no la pantalla con
                      // la que se prepara el pedido.
                      Text(
                        'Pedido #${pedido.numeroPedidoDia} · ${pedido.productoResumen.isEmpty ? '—' : pedido.productoResumen} · S/ ${pedido.total.toStringAsFixed(2)}',
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
                  onPressed: () => onMarcarPagada(pedido),
                  child: const Text('Marcar pagada'),
                ),
              ],
            ),
          );
        }),
      ],
    );

    if (esEscritorio(context)) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: TarjetaEscritorio(
          acento: _rojoDeuda,
          padding: const EdgeInsets.all(16),
          child: contenido,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Tarjeta3D(
        child: Container(
          color: AppColors.surface,
          padding: const EdgeInsets.all(14),
          child: contenido,
        ),
      ),
    );
  }
}
