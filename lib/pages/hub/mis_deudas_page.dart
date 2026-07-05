import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/medio_pago_model.dart';
import '../../models/solicitud_pago_model.dart';
import '../../services/api_client.dart';
import '../../services/medios_pago_service.dart';
import '../../services/notificaciones_service.dart';
import '../../services/solicitudes_pago_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ad_banner.dart';
import '../../widgets/loading_indicator.dart';

/// Autoservicio (rol CLIENTE): sus deudas (pedidos entregados sin pagar),
/// agrupadas por tienda — solo se pueden pagar juntas las de una misma
/// tienda a la vez, porque cada tienda tiene sus propios métodos de pago.
/// El cliente selecciona 1+, elige un medio de pago y se genera un QR
/// informativo de un solo uso con el monto total y un código de
/// referencia — el pago real se hace a mano en su Yape/Plin/banco, y
/// luego reporta "Ya pagué" para que el personal lo confirme.
class MisDeudasPage extends StatefulWidget {
  const MisDeudasPage({super.key, this.mostrarAnuncio = false});

  /// Solo debe encender esto quien la abre sabiendo que el usuario es
  /// cliente puro (no híbrido) — el anuncio existe para monetizar a
  /// quienes solo compran, no a quienes también trabajan ahí.
  final bool mostrarAnuncio;

  @override
  State<MisDeudasPage> createState() => _MisDeudasPageState();
}

class _MisDeudasPageState extends State<MisDeudasPage> {
  final _solicitudesPagoService = SolicitudesPagoService();
  final _mediosPagoService = MediosPagoService();

  bool _cargando = true;
  String? _error;
  List<Deuda> _deudas = [];
  final Set<int> _seleccionados = {};

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
      final deudas = await _solicitudesPagoService.misDeudas();
      setState(() {
        _deudas = deudas;
        _seleccionados.clear();
      });
    } on ApiException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(() => _error = 'No se pudieron cargar tus deudas.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  bool _puedeSeleccionar(Deuda deuda) => deuda.solicitudPagoActiva == null;

  int? get _idTiendaSeleccionada {
    if (_seleccionados.isEmpty) return null;
    return _deudas
        .firstWhere((d) => _seleccionados.contains(d.idPedido))
        .idTienda;
  }

  double get _totalSeleccionado => _deudas
      .where((d) => _seleccionados.contains(d.idPedido))
      .fold(0.0, (acc, d) => acc + d.total);

  void _alternarSeleccion(Deuda deuda) {
    if (!_puedeSeleccionar(deuda)) return;
    final tiendaActual = _idTiendaSeleccionada;
    if (tiendaActual != null &&
        tiendaActual != deuda.idTienda &&
        !_seleccionados.contains(deuda.idPedido)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Solo puedes pagar deudas de una misma tienda a la vez.',
          ),
        ),
      );
      return;
    }
    setState(() {
      if (_seleccionados.contains(deuda.idPedido)) {
        _seleccionados.remove(deuda.idPedido);
      } else {
        _seleccionados.add(deuda.idPedido);
      }
    });
  }

  Future<void> _pagarSeleccionadas() async {
    final idTienda = _idTiendaSeleccionada;
    if (idTienda == null) return;

    List<MedioPago> medios;
    try {
      medios = await _mediosPagoService.listarActivos(idTienda);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.mensaje)));
      return;
    }

    if (medios.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Esta tienda todavía no configuró ningún método de pago.',
          ),
        ),
      );
      return;
    }

    if (!mounted) return;
    final medioElegido = await showModalBottomSheet<MedioPago>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Elige cómo pagar',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ...medios.map(
              (m) => ListTile(
                leading: Icon(
                  m.tipo == 'TRANSFERENCIA'
                      ? Icons.account_balance_rounded
                      : Icons.phone_android_rounded,
                ),
                title: Text(m.etiquetaTipo),
                subtitle: Text('${m.titular} · ${m.numeroDestino}'),
                onTap: () => Navigator.of(context).pop(m),
              ),
            ),
          ],
        ),
      ),
    );
    if (medioElegido == null) return;

    try {
      final solicitud = await _solicitudesPagoService.crear(
        idMedioPago: medioElegido.idMedioPago,
        idsPedidos: _seleccionados.toList(),
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => _QrPagoPage(solicitud: solicitud)),
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
      appBar: AppBar(title: const Text('Mis deudas')),
      body: SafeArea(child: _construirCuerpo()),
      bottomNavigationBar: _seleccionados.isNotEmpty
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: _pagarSeleccionadas,
                  child: Text(
                    'Pagar S/ ${_totalSeleccionado.toStringAsFixed(2)}',
                  ),
                ),
              ),
            )
          : (widget.mostrarAnuncio ? const AdBanner() : null),
    );
  }

  Widget _construirCuerpo() {
    final theme = Theme.of(context);

    if (_cargando) return const Center(child: AppLoadingIndicator());

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _cargar,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_deudas.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_outline_rounded,
                size: 48,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 12),
              Text(
                'No tienes deudas pendientes',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
        itemCount: _deudas.length,
        itemBuilder: (context, index) {
          final deuda = _deudas[index];
          return _TarjetaDeuda(
                deuda: deuda,
                seleccionado: _seleccionados.contains(deuda.idPedido),
                puedeSeleccionar: _puedeSeleccionar(deuda),
                onTap: () => _alternarSeleccion(deuda),
              )
              .animate(delay: (60 * index).ms)
              .fadeIn(duration: 300.ms)
              .moveY(begin: 10, end: 0);
        },
      ),
    );
  }
}

class _TarjetaDeuda extends StatelessWidget {
  const _TarjetaDeuda({
    required this.deuda,
    required this.seleccionado,
    required this.puedeSeleccionar,
    required this.onTap,
  });

  final Deuda deuda;
  final bool seleccionado;
  final bool puedeSeleccionar;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final solicitud = deuda.solicitudPagoActiva;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: seleccionado
            ? Border.all(color: AppColors.primary, width: 2)
            : null,
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: puedeSeleccionar ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              if (puedeSeleccionar)
                Checkbox(value: seleccionado, onChanged: (_) => onTap())
              else
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(
                    Icons.hourglass_top_rounded,
                    color: Color(0xFFEA8C1B),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${deuda.tienda ?? 'Pedido'} · S/ ${deuda.total.toStringAsFixed(2)}',
                      style: theme.textTheme.titleMedium,
                    ),
                    if (deuda.fechaEntregaReal != null)
                      Text(
                        'Entregado el ${DateFormat('d/MM/yyyy', 'es').format(deuda.fechaEntregaReal!)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 12,
                        ),
                      ),
                    if (solicitud != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          solicitud.estado == 'REPORTADO'
                              ? 'Reportado (código ${solicitud.codigoReferencia}) — esperando confirmación'
                              : 'Código generado: ${solicitud.codigoReferencia} — repórtalo cuando pagues',
                          style: const TextStyle(
                            color: Color(0xFFEA8C1B),
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pantalla del QR generado: el cliente lo escanea con su Yape/Plin/banco,
/// completa el pago a mano (el QR es informativo, no auto-completa el
/// monto — ver la conversación técnica sobre por qué), y aprieta "Ya
/// pagué" cuando termine.
class _QrPagoPage extends StatefulWidget {
  const _QrPagoPage({required this.solicitud});

  final SolicitudPagoCreada solicitud;

  @override
  State<_QrPagoPage> createState() => _QrPagoPageState();
}

class _QrPagoPageState extends State<_QrPagoPage> {
  final _solicitudesPagoService = SolicitudesPagoService();
  bool _reportando = false;
  bool _reportado = false;

  Future<void> _reportarPago() async {
    setState(() => _reportando = true);
    try {
      await _solicitudesPagoService.reportar(widget.solicitud.idSolicitudPago);
      NotificacionesService.avisarCambioPedido();
      if (!mounted) return;
      setState(() => _reportado = true);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.mensaje)));
    } finally {
      if (mounted) setState(() => _reportando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final solicitud = widget.solicitud;
    final medioPago = solicitud.medioPago;

    return Scaffold(
      appBar: AppBar(title: const Text('Pagar deuda')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_reportado) ...[
                const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF2E7D32),
                  size: 64,
                ),
                const SizedBox(height: 12),
                Text(
                  'Pago reportado',
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'El personal revisará tu ${medioPago.etiquetaTipo.toLowerCase()} y confirmará tu pago pronto.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Listo'),
                ),
              ] else ...[
                Text(
                  'Escanea este código con la cámara de tu celular (no con el lector de Yape/Plin — solo aceptan su propio formato). Vas a ver los datos de abajo para transferir a mano y no olvides poner la referencia.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: QrImageView(
                      data: solicitud.contenidoQr,
                      size: 220,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FilaDato(
                        etiqueta: medioPago.etiquetaTipo,
                        valor: medioPago.numeroDestino,
                      ),
                      _FilaDato(etiqueta: 'Titular', valor: medioPago.titular),
                      if (medioPago.cci != null)
                        _FilaDato(etiqueta: 'CCI', valor: medioPago.cci!),
                      if (medioPago.nombreBanco != null)
                        _FilaDato(
                          etiqueta: 'Banco',
                          valor: medioPago.nombreBanco!,
                        ),
                      _FilaDato(
                        etiqueta: 'Monto',
                        valor: 'S/ ${solicitud.montoTotal.toStringAsFixed(2)}',
                      ),
                      _FilaDato(
                        etiqueta: 'Referencia',
                        valor: solicitud.codigoReferencia,
                        destacado: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Este código es de un solo uso y vence a las ${DateFormat('h:mm a').format(solicitud.fechaExpiracion)}.',
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _reportando ? null : _reportarPago,
                  child: _reportando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Ya pagué'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FilaDato extends StatelessWidget {
  const _FilaDato({
    required this.etiqueta,
    required this.valor,
    this.destacado = false,
  });

  final String etiqueta;
  final String valor;
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(etiqueta),
          Text(
            valor,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: destacado ? 18 : 14,
            ),
          ),
        ],
      ),
    );
  }
}
