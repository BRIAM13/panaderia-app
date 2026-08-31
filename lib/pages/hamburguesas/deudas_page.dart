import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../models/solicitud_pago_model.dart';
import '../../models/tienda_model.dart';
import '../../services/api_client.dart';
import '../../services/notificaciones_service.dart';
import '../../services/pedidos_service.dart';
import '../../services/solicitudes_pago_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/fecha_pedido_utils.dart';
import '../../widgets/escritorio.dart';
import '../../widgets/estado_error.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/pedidos_secciones.dart';
import '../../widgets/tarjeta_3d.dart';

/// Deudas pendientes (pedidos ENTREGADO con EstadoPago=DEUDA) de una tienda
/// de catálogo simple (Hamburguesas o Panadería), agrupadas por cliente con
/// su total — arriba de todo, los pagos que el cliente ya reportó (o generó
/// un QR para) desde su propia app, esperando confirmación. El pago sin
/// reporte digital solo puede confirmarse a mano (efectivo/Yape ya recibido
/// en persona).
class DeudasPage extends StatefulWidget {
  const DeudasPage({super.key, required this.tienda});

  final Tienda tienda;

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
        _pedidosService.listarDeudas(idTienda: widget.tienda.idTienda),
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
        SnackBar(
          content: Text('Deuda del pedido #${pedido.numeroPedidoDia} saldada.'),
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
      appBar: appBarGestion(
        context,
        titulo: 'Deudas',
        subtitulo: widget.tienda.nombre,
      ),
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

    if (esEscritorio(context)) return _cuerpoEscritorio(grupos);

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

  // ---------------------------------------------------------------------
  // ESCRITORIO
  // ---------------------------------------------------------------------

  /// Dos columnas: a la izquierda la COLA DE TRABAJO (pagos que el cliente
  /// reportó y hay que confirmar contra Yape/Plin), a la derecha la deuda
  /// abierta por cliente. En celular la cola queda encima de la lista y, con
  /// varias deudas, hay que desplazarse hacia arriba cada vez que se quiere
  /// volver a ella; acá las dos están a la vista al mismo tiempo.
  Widget _cuerpoEscritorio(List<_GrupoDeuda> grupos) {
    final deudaTotal = grupos.fold<double>(0, (acc, g) => acc + g.total);

    final panelSolicitudes = PanelEscritorio(
      icono: Icons.qr_code_2_rounded,
      titulo: 'Pagos reportados',
      subtitulo: 'Revisa y confirma según tu Yape/Plin/cuenta.',
      child: Column(
        children: [
          for (var i = 0; i < _solicitudes.length; i++)
            _TarjetaSolicitudPago(
                  solicitud: _solicitudes[i],
                  plana: true,
                  onConfirmar: () => _confirmarSolicitud(_solicitudes[i]),
                  onRechazar: () => _rechazarSolicitud(_solicitudes[i]),
                )
                .animate(delay: (50 * i).ms)
                .fadeIn(duration: 280.ms)
                .moveY(begin: 10, end: 0),
        ],
      ),
    );

    final panelDeudas = PanelEscritorio(
      icono: Icons.account_balance_wallet_rounded,
      titulo: 'Deuda abierta por cliente',
      subtitulo: grupos.isEmpty
          ? 'Ningún cliente debe nada ahora mismo.'
          : 'Ordenados de mayor a menor.',
      accion: grupos.isEmpty
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFC62828).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'S/ ${deudaTotal.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Color(0xFFC62828),
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
      child: grupos.isEmpty
          ? const SizedBox(
              height: 200,
              child: EstadoVacio(
                icono: Icons.check_circle_outline_rounded,
                titulo: 'Sin deudas abiertas',
              ),
            )
          : Column(
              children: [
                for (var i = 0; i < grupos.length; i++)
                  _GrupoDeudaCliente(
                        grupo: grupos[i],
                        plana: true,
                        onMarcarPagada: _marcarPagada,
                      )
                      .animate(delay: (50 * i).ms)
                      .fadeIn(duration: 280.ms)
                      .moveY(begin: 10, end: 0),
              ],
            ),
    );

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 56),
        children: [
          ContenidoCentrado(
            child: _solicitudes.isEmpty
                // Sin cola pendiente no tiene sentido reservarle media
                // pantalla: la lista de deudas se queda con todo el ancho.
                ? panelDeudas
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 2, child: panelSolicitudes),
                      const SizedBox(width: espacioEscritorio),
                      Expanded(flex: 3, child: panelDeudas),
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
    this.plana = false,
  });

  final SolicitudPagoPendiente solicitud;
  final VoidCallback onConfirmar;
  final VoidCallback onRechazar;

  /// Dentro de un [PanelEscritorio]: borde fino en vez de tarjeta con sombra
  /// (una tarjeta con sombra dentro de otra tarjeta se ve sucio).
  final bool plana;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _Marco(
        plana: plana,
        radio: 18,
        child: Container(
          color: plana ? null : AppColors.surface,
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

/// Marco de una tarjeta de esta pantalla: [Tarjeta3D] con sombra en celular,
/// contenedor con borde fino cuando ya vive dentro de un panel de
/// escritorio.
class _Marco extends StatelessWidget {
  const _Marco({required this.child, required this.plana, this.radio = 20});

  final Widget child;
  final bool plana;
  final double radio;

  @override
  Widget build(BuildContext context) {
    if (!plana) return Tarjeta3D(borderRadius: radio, child: child);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(radio),
        border: Border.all(color: AppColors.surfaceMuted, width: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _GrupoDeudaCliente extends StatelessWidget {
  const _GrupoDeudaCliente({
    required this.grupo,
    required this.onMarcarPagada,
    this.plana = false,
  });

  final _GrupoDeuda grupo;
  final ValueChanged<Pedido> onMarcarPagada;
  final bool plana;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nombreComercial = grupo.cliente.nombreComercial;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _Marco(
        plana: plana,
        child: Container(
          color: plana ? null : AppColors.surface,
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
                              'Pedido #${pedido.numeroPedidoDia} · S/ ${pedido.total.toStringAsFixed(2)}',
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
