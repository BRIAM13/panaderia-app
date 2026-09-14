import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../models/tienda_model.dart';
import '../../services/ajustes_pago_service.dart';
import '../../services/api_client.dart';
import '../../services/notificaciones_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/fecha_pedido_utils.dart';
import '../../widgets/escritorio.dart';
import '../../widgets/estado_error.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/tarjeta_3d.dart';

/// Vueltos y saldos que quedaron abiertos después de verificar un pago
/// adelantado por Yape que no coincidió con el total del pedido.
///
/// Es una pantalla propia y no un bloque dentro de Pedidos por una razón
/// concreta: **un ajuste sobrevive a su pedido**. La lista de Pedidos oculta
/// lo ya finalizado (entregado/rechazado/cancelado), así que un vuelto que
/// no se alcanzó a devolver el día de la entrega desaparecería de la vista
/// justo cuando más falta hace recordarlo. Acá sigue estando hasta que
/// alguien lo marque resuelto.
///
/// Y por eso mismo resolver un ajuste es una acción INDEPENDIENTE de marcar
/// el pedido entregado: lo normal es hacerlo al recoger, pero el dueño puede
/// devolver un vuelto por Yape el mismo día, o cobrar un saldo la semana
/// siguiente.
class AjustesPagoPage extends StatefulWidget {
  const AjustesPagoPage({super.key, required this.tienda});

  final Tienda tienda;

  @override
  State<AjustesPagoPage> createState() => _AjustesPagoPageState();
}

class _AjustesPagoPageState extends State<AjustesPagoPage> {
  final _service = AjustesPagoService();

  List<AjustePago> _ajustes = [];
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
      final ajustes = await _service.listarPendientes(
        idTienda: widget.tienda.idTienda,
      );
      if (mounted) setState(() => _ajustes = ajustes);
    } on ApiException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(() => _error = 'No se pudieron cargar los vueltos y saldos.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _resolver(AjustePago ajuste) async {
    final notas = await showDialog<String?>(
      context: context,
      builder: (context) => _DialogoResolverAjuste(ajuste: ajuste),
    );
    // null = cerró el diálogo sin confirmar. Una cadena vacía SÍ es una
    // confirmación (resolvió sin dejar nota, que es lo más común).
    if (notas == null) return;

    try {
      await _service.resolver(ajuste.idAjuste, notas: notas);
      NotificacionesService.avisarCambioPedido();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ajuste.esVuelto
                ? 'Vuelto de S/ ${ajuste.monto.toStringAsFixed(2)} marcado como devuelto.'
                : 'Saldo de S/ ${ajuste.monto.toStringAsFixed(2)} marcado como cobrado.',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBarGestion(
        context,
        titulo: 'Vueltos y saldos',
        subtitulo: _resumenCabecera(),
      ),
      body: SafeArea(child: _construirCuerpo()),
    );
  }

  /// De un vistazo: cuánta plata hay que devolver y cuánta hay que cobrar.
  /// Son dos cifras distintas y no se suman — apuntan en direcciones
  /// contrarias.
  String? _resumenCabecera() {
    if (_cargando || _error != null || _ajustes.isEmpty) return null;
    final porDevolver = _ajustes
        .where((a) => a.esVuelto)
        .fold<double>(0, (acc, a) => acc + a.monto);
    final porCobrar = _ajustes
        .where((a) => !a.esVuelto)
        .fold<double>(0, (acc, a) => acc + a.monto);
    final partes = <String>[
      if (porDevolver > 0) 'S/ ${porDevolver.toStringAsFixed(2)} por devolver',
      if (porCobrar > 0) 'S/ ${porCobrar.toStringAsFixed(2)} por cobrar',
    ];
    return partes.join(' · ');
  }

  Widget _construirCuerpo() {
    if (_cargando) return const Center(child: AppLoadingIndicator());
    if (_error != null) {
      return EstadoError(mensaje: _error!, onReintentar: _cargar);
    }
    if (_ajustes.isEmpty) {
      return EstadoVacio(
        icono: PhosphorIconsDuotone.checkCircle,
        titulo: 'No hay vueltos ni saldos pendientes',
        subtitulo:
            'Cuando un cliente pague por Yape de más o de menos, el vuelto o '
            'el saldo van a aparecer acá hasta que lo resuelvas.',
        onRefrescar: _cargar,
      );
    }

    final escritorio = esEscritorio(context);
    final tarjetas = _ajustes.asMap().entries.map(
      (entry) =>
          _TarjetaAjuste(
                ajuste: entry.value,
                onResolver: () => _resolver(entry.value),
              )
              .animate(delay: (60 * entry.key).ms)
              .fadeIn(duration: 300.ms)
              .moveY(begin: 10, end: 0),
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
            if (!escritorio)
              ...tarjetas
            else
              // En escritorio son tarjetas cortas y de alto parejo: en grilla
              // se ven todas de un golpe, en vez de una columna de tarjetas
              // anchísimas.
              LayoutBuilder(
                builder: (context, constraints) {
                  const separacion = 16.0;
                  const anchoObjetivo = 420.0;
                  final columnas =
                      ((constraints.maxWidth + separacion) /
                              (anchoObjetivo + separacion))
                          .floor()
                          .clamp(1, 3);
                  final ancho =
                      (constraints.maxWidth - separacion * (columnas - 1)) /
                      columnas;
                  return Wrap(
                    spacing: separacion,
                    runSpacing: 0,
                    children: tarjetas
                        .map((t) => SizedBox(width: ancho, child: t))
                        .toList(),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _TarjetaAjuste extends StatelessWidget {
  const _TarjetaAjuste({required this.ajuste, required this.onResolver});

  final AjustePago ajuste;
  final VoidCallback onResolver;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Dos colores porque son dos problemas distintos: un vuelto es plata
    // nuestra que hay que sacar, un saldo es plata que falta entrar.
    final color = ajuste.esVuelto
        ? const Color(0xFFEA8C1B)
        : const Color(0xFFC62828);
    final cliente = ajuste.cliente;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Tarjeta3D(
        borderRadius: 18,
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
                      color: color.withValues(alpha: 0.12),
                    ),
                    child: PhosphorIcon(
                      ajuste.esVuelto
                          ? PhosphorIconsRegular.arrowUUpLeft
                          : PhosphorIconsRegular.wallet,
                      color: color,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ajuste.esVuelto
                              ? 'Devolver S/ ${ajuste.monto.toStringAsFixed(2)}'
                              : 'Cobrar S/ ${ajuste.monto.toStringAsFixed(2)}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: color,
                          ),
                        ),
                        if (cliente != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            cliente.nombreComercial ?? cliente.nombreParaMostrar,
                            style: theme.textTheme.bodyMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          'Pedido #${ajuste.numeroPedidoDia ?? ajuste.idPedido}'
                          '${ajuste.totalPedido != null ? ' · Total S/ ${ajuste.totalPedido!.toStringAsFixed(2)}' : ''}'
                          '${ajuste.montoConfirmadoStaff != null ? ' · Pagó S/ ${ajuste.montoConfirmadoStaff!.toStringAsFixed(2)}' : ''}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 12,
                          ),
                        ),
                        if (ajuste.codigoOperacionYape != null)
                          Text(
                            'Código Yape: ${ajuste.codigoOperacionYape}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 12,
                            ),
                          ),
                        if (ajuste.fechaCreacion != null)
                          Text(
                            'Desde ${formatearFechaEntrega(ajuste.fechaCreacion!)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onResolver,
                  icon: const PhosphorIcon(PhosphorIconsBold.check, size: 18),
                  label: Text(
                    ajuste.esVuelto
                        ? 'Ya se lo devolví'
                        : 'Ya me lo pagó',
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

/// Confirmación de "ya está saldado", con una nota opcional (ej. "se lo
/// devolví en efectivo", "lo descontó del siguiente pedido"). Devuelve la
/// nota —posiblemente vacía— al confirmar, o null si se cierra sin resolver.
class _DialogoResolverAjuste extends StatefulWidget {
  const _DialogoResolverAjuste({required this.ajuste});

  final AjustePago ajuste;

  @override
  State<_DialogoResolverAjuste> createState() => _DialogoResolverAjusteState();
}

class _DialogoResolverAjusteState extends State<_DialogoResolverAjuste> {
  final _notasController = TextEditingController();

  @override
  void dispose() {
    _notasController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ajuste = widget.ajuste;
    return AlertDialog(
      title: Text(ajuste.esVuelto ? 'Vuelto devuelto' : 'Saldo cobrado'),
      content: SizedBox(
        width: esEscritorio(context) ? 460 : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              ajuste.esVuelto
                  ? '¿Ya le devolviste los S/ ${ajuste.monto.toStringAsFixed(2)} del pedido #${ajuste.numeroPedidoDia ?? ajuste.idPedido}?'
                  : '¿Ya te pagó los S/ ${ajuste.monto.toStringAsFixed(2)} que faltaban del pedido #${ajuste.numeroPedidoDia ?? ajuste.idPedido}?',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _notasController,
              maxLength: 300,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Nota (opcional)',
                hintText: 'Ej: en efectivo al recoger',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Todavía no'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(_notasController.text.trim()),
          child: const Text('Sí, ya está'),
        ),
      ],
    );
  }
}
