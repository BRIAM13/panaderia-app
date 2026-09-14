import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../models/tienda_model.dart';
import '../../services/api_client.dart';
import '../../services/notificaciones_service.dart';
import '../../services/pedidos_service.dart';
import '../../theme/app_theme.dart';
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
/// (Hamburguesas o Panadería — Horneados tiene su propia página): arriba las
/// dos colas que esperan una acción ahora mismo —"Pagos por verificar"
/// (Panadería: ya yapearon, falta comparar el monto contra el Yape del
/// negocio) y "Por confirmar" (esperan un aceptar/rechazar según stock)—, y
/// debajo el resto agrupado en Atrasados / Hoy / Próximos / Sin fecha.
///
/// Acá vive la verificación del pago adelantado y no en una pantalla nueva
/// porque es exactamente eso: una acción más sobre un pedido, al lado de
/// aceptar, rechazar, entregar y cancelar. Lo que NO vive acá son los saldos
/// y vueltos que quedan después (`AjustesPagoPage`): un ajuste sobrevive a
/// su pedido, y esta lista oculta lo ya entregado.
///
/// Para la vista del propio cliente ver `MisPedidosPendientesPage`.
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
    // Un pedido pagado por adelantado ya tiene su plata: preguntar "¿se pagó
    // al momento?" no tiene sentido, y responder "queda como deuda" ahí
    // significaría en los reportes que debe el TOTAL completo. Lo que le
    // falte (o le sobre) vive en su ajuste de pago, que se resuelve aparte.
    final bool? pagado = pedido.usaPagoAdelanto
        ? await _confirmarEntregaPagada(pedido)
        : await _preguntarSiPagoAlEntregar(pedido);
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

  /// La pregunta de siempre al entregar: ¿se pagó al momento o queda fiado?
  /// Solo para pedidos que NO se pagaron por adelantado.
  Future<bool?> _preguntarSiPagoAlEntregar(Pedido pedido) => showDialog<bool>(
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

  /// Confirmación de entrega de un pedido YA pagado por adelantado: no se
  /// pregunta si se pagó (ya está), solo se recuerda el saldo o el vuelto
  /// que quede por mover, que es justo el momento en que suele resolverse.
  /// Devuelve siempre `true` (pagado) o null si se cancela.
  Future<bool?> _confirmarEntregaPagada(Pedido pedido) async {
    final ajuste = pedido.ajustePago;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Marcar como entregado'),
        content: Text(
          ajuste != null && ajuste.esPendiente
              ? 'El pedido #${pedido.numeroPedidoDia} ya está pagado por Yape.\n\n'
                    '${ajuste.esVuelto ? 'Recuerda devolverle S/ ${ajuste.monto.toStringAsFixed(2)} de vuelto.' : 'Recuerda cobrarle los S/ ${ajuste.monto.toStringAsFixed(2)} que faltan.'}\n\n'
                    'Eso se marca aparte, en "Vueltos y saldos".'
              : 'El pedido #${pedido.numeroPedidoDia} ya está pagado por Yape. ¿Se lo entregaste al cliente?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sí, entregado'),
          ),
        ],
      ),
    );
    return confirmado;
  }

  /// Verificación del pago adelantado por Yape (solo pedidos web de
  /// Panadería que ya reportaron su código de operación).
  ///
  /// Se pide UN número: cuánto llegó de verdad al Yape del negocio. El
  /// resultado —justo, de menos o de más— lo deduce el backend a partir de
  /// ese monto y del total del pedido; el personal nunca lo elige de una
  /// lista, porque un menú dejaría marcar "pagado" sobre un pago incompleto.
  Future<void> _verificarPago(Pedido pedido) async {
    final monto = await showDialog<double>(
      context: context,
      builder: (context) => _DialogoVerificarPago(pedido: pedido),
    );
    if (monto == null) return;

    try {
      final resultado = await _pedidosService.confirmarPagoAdelanto(
        pedido.idPedido,
        montoConfirmado: monto,
      );
      NotificacionesService.avisarCambioPedido();
      if (!mounted) return;
      // El mensaje ya viene redactado por el backend y dice exactamente en
      // qué quedó (pagado / falta S/ X / sobra S/ X), así que el personal se
      // entera del resultado sin tener que volver a mirar la tarjeta.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Pedido #${pedido.numeroPedidoDia}: ${resultado.mensaje}'),
          duration: const Duration(seconds: 6),
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
          // Variante `compacto` y sin Padding propio: appBarGestion ya
          // centra cada acción dentro de su toolbarHeight fijo (72). El
          // PremiumButton normal mide ~54 px de alto (padding vertical 16 +
          // texto titleMedium en negrita) y dentro de esa barra se lee más
          // pesado que el propio título de la pantalla — "se ve enorme y
          // choca con la parte de arriba", reportado en producción. La
          // versión compacta mide ~40 px y deja aire arriba y abajo. Ojo
          // con volver a envolverlo en un Padding: la altura de la barra es
          // fija y AppBar recorta lo que sobre, en silencio en release (se
          // nota primero en la descendente de la "p" de "pedido").
          if (escritorio)
            PremiumButton(
              label: 'Nuevo pedido',
              icono: PhosphorIconsBold.shoppingCartSimple,
              expandido: false,
              compacto: true,
              onPressed: _nuevoPedido,
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
    final porConfirmar = _pedidos
        .where((p) => p.esSolicitado && !p.usaPagoAdelanto)
        .length;
    final pagosPorVerificar = _pedidos
        .where((p) => p.esperaVerificacionPago)
        .length;
    final activos = _pedidos.where((p) => !p.esFinalizado).length;
    if (activos == 0) return 'Todo al día — no hay pedidos pendientes';
    final partes = <String>[
      '$activos pendiente${activos == 1 ? '' : 's'}',
      if (pagosPorVerificar > 0) '$pagosPorVerificar pago(s) por verificar',
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

    // Dos colas de decisión, no una:
    //
    //   "Pagos por verificar" — pedidos web de Panadería que ya yapearon y
    //   mandaron su código. Lo que esperan no es una decisión de stock sino
    //   que alguien abra su Yape y compare el monto. Va PRIMERO porque es lo
    //   más sensible a la espera: del otro lado hay un cliente que ya pagó.
    //
    //   "Por confirmar" — la cola de siempre: pedidos que esperan un
    //   aceptar/rechazar según stock. Los pagados por adelantado quedan
    //   fuera a propósito: su camino es verificar el pago, que además los
    //   confirma (el backend rechaza aprobarlos a mano).
    final pagosPorVerificar = _pedidos
        .where((p) => p.esperaVerificacionPago)
        .toList();
    final solicitados = _pedidos
        .where((p) => p.esSolicitado && !p.usaPagoAdelanto)
        .toList();
    // Todo lo demás se agrupa por fecha como siempre — incluidos los pedidos
    // de Panadería que todavía esperan que el cliente pague: no hay nada que
    // decidir sobre ellos, solo esperar (su tarjeta lo dice).
    final resto = _pedidos
        .where((p) => !p.esSolicitado || (p.usaPagoAdelanto && !p.esperaVerificacionPago))
        .toList();
    final escritorio = esEscritorio(context);
    const ambar = Color(0xFFEA8C1B);
    const morado = Color(0xFF7B3FB5);

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
            if (pagosPorVerificar.isNotEmpty) ...[
              _bloqueCola(
                theme: theme,
                escritorio: escritorio,
                color: morado,
                icono: PhosphorIconsFill.currencyCircleDollar,
                titulo: 'Pagos por verificar',
                subtitulo: 'Ya yapearon — revisa el monto en tu Yape',
                pedidos: pagosPorVerificar,
                construirTarjeta: (pedido) => PedidoCard(
                  pedido: pedido,
                  colorSeccion: morado,
                  onVerificarPago: () => _verificarPago(pedido),
                  onCancelar: () => _cancelar(pedido),
                ),
              ),
              SizedBox(height: escritorio ? 28 : 10),
            ],
            if (solicitados.isNotEmpty) ...[
              _bloqueCola(
                theme: theme,
                escritorio: escritorio,
                color: ambar,
                icono: PhosphorIconsFill.hourglassHigh,
                titulo: 'Por confirmar',
                subtitulo: 'Solicitados por clientes — revisa el stock',
                pedidos: solicitados,
                construirTarjeta: (pedido) => PedidoCard(
                  pedido: pedido,
                  colorSeccion: ambar,
                  onAprobar: () => _aprobar(pedido),
                  onRechazar: () => _rechazar(pedido),
                ),
              ),
              SizedBox(height: escritorio ? 28 : 10),
            ],
            ListaPedidosPorSeccion(
              pedidos: resto,
              onEntregar: _entregar,
              onCancelar: _cancelar,
              onVerificarPago: _verificarPago,
            ),
          ],
        ),
      ),
    );
  }

  /// Un bloque teñido con su encabezado, su contador y su grilla — la forma
  /// que ya tenía "Por confirmar", ahora compartida con "Pagos por
  /// verificar" para que las dos colas se lean con la misma retícula y no
  /// como dos inventos distintos.
  ///
  /// El marco teñido no es decoración de escritorio: es lo que despega la
  /// cola de decisiones del resto de la lista, y en celular —donde hay menos
  /// contexto a la vista— es donde más falta hace.
  Widget _bloqueCola({
    required ThemeData theme,
    required bool escritorio,
    required Color color,
    required IconData icono,
    required String titulo,
    required String subtitulo,
    required List<Pedido> pedidos,
    required PedidoCard Function(Pedido) construirTarjeta,
  }) {
    final tarjetas = pedidos.asMap().entries.map(
      (entry) => construirTarjeta(entry.value)
          .animate(delay: (40 * entry.key).ms)
          .fadeIn(duration: 250.ms)
          .moveY(begin: 8, end: 0),
    );

    return Container(
      padding: escritorio
          ? const EdgeInsets.fromLTRB(18, 16, 18, 6)
          : const EdgeInsets.fromLTRB(14, 14, 14, 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  PhosphorIcon(icono, color: color, size: escritorio ? 22 : 20),
                  const SizedBox(width: 8),
                  Text(
                    titulo,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: color,
                      fontSize: escritorio ? 18 : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
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
                  // En escritorio la fila del título se queda corta y
                  // flotando en medio de una ventana de 1600px: la línea la
                  // cierra y hace que se lea como una separación real.
                  if (escritorio) ...[
                    const SizedBox(width: 14),
                    Expanded(
                      child: Container(
                        height: 1,
                        color: color.withValues(alpha: 0.20),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: Text(subtitulo, style: theme.textTheme.bodyMedium),
              ),
            ],
          ),
          SizedBox(height: escritorio ? 14 : 10),
          // Misma grilla justificada que las secciones de abajo, para que
          // las colas no se vean con otra retícula que el resto — y desde
          // 600 px, no solo en escritorio (ver `anchoTarjetaPedido`).
          LayoutBuilder(
            builder: (context, constraints) {
              if (MediaQuery.sizeOf(context).width < Breakpoints.tablet) {
                return Column(children: tarjetas.toList());
              }
              return Wrap(
                spacing: 14,
                runSpacing: 0,
                children: tarjetas
                    .map(
                      (t) => SizedBox(
                        width: anchoTarjetaPedido(constraints.maxWidth),
                        child: t,
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Diálogo de verificación del pago adelantado por Yape.
///
/// Un solo campo: cuánto llegó DE VERDAD a la cuenta. El resultado —pagado
/// justo, de menos o de más— no se elige de una lista, se deduce de ese
/// número contra el total del pedido; un menú de tres opciones dejaría
/// marcar "pagado" sobre un pago incompleto, que es exactamente el error
/// que esta pantalla existe para evitar.
///
/// Arriba se muestra el código de operación bien grande, porque es lo que
/// el personal tiene que buscar en su app de Yape, y el monto que el
/// cliente DIJO haber pagado, que sirve como pista y nada más.
class _DialogoVerificarPago extends StatefulWidget {
  const _DialogoVerificarPago({required this.pedido});

  final Pedido pedido;

  @override
  State<_DialogoVerificarPago> createState() => _DialogoVerificarPagoState();
}

class _DialogoVerificarPagoState extends State<_DialogoVerificarPago> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _montoController;

  @override
  void initState() {
    super.initState();
    // Precargado con lo que el cliente declaró: en la enorme mayoría de los
    // casos va a coincidir con lo que llegó, así que no hay nada que
    // teclear. Cuando NO coincide, que es el caso que importa, el personal
    // lo corrige — y esa corrección es justamente el dato que se busca.
    _montoController = TextEditingController(
      text: (widget.pedido.montoDeclaradoCliente ?? widget.pedido.total)
          .toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _montoController.dispose();
    super.dispose();
  }

  /// Vista previa del resultado mientras el personal escribe — la MISMA
  /// cuenta que hace el backend (`resolverPagoAdelanto`), en céntimos para
  /// no arrastrar errores de punto flotante. Es solo informativa: quien
  /// decide es el servidor.
  String? _adelanto() {
    final monto = double.tryParse(_montoController.text.trim());
    if (monto == null || monto <= 0) return null;
    final diferencia =
        (monto * 100).round() - (widget.pedido.total * 100).round();
    if (diferencia == 0) return 'Coincide con el total: quedará como PAGADO.';
    if (diferencia < 0) {
      return 'Faltan S/ ${(-diferencia / 100).toStringAsFixed(2)}: se registrará un saldo por cobrar.';
    }
    return 'Sobran S/ ${(diferencia / 100).toStringAsFixed(2)}: se registrará un vuelto por devolver.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pedido = widget.pedido;
    final adelanto = _adelanto();

    return AlertDialog(
      title: Text('Verificar pago · Pedido #${pedido.numeroPedidoDia}'),
      content: SizedBox(
        width: esEscritorio(context) ? 460 : null,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Busca este código en tu Yape',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      SelectableText(
                        pedido.codigoOperacionYape ?? '—',
                        style: theme.textTheme.titleLarge?.copyWith(
                          letterSpacing: 2,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Total del pedido: S/ ${pedido.total.toStringAsFixed(2)}',
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (pedido.montoDeclaradoCliente != null)
                        Text(
                          'El cliente dice haber pagado: S/ ${pedido.montoDeclaradoCliente!.toStringAsFixed(2)}',
                          style: theme.textTheme.bodyMedium,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _montoController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: '¿Cuánto llegó realmente? (S/)',
                    helperText:
                        'Escribe el monto tal como aparece en tu Yape, no el que dice el cliente.',
                    helperMaxLines: 3,
                  ),
                  validator: (v) {
                    final monto = double.tryParse((v ?? '').trim());
                    if (monto == null || monto <= 0) {
                      return 'Ingresa un monto válido';
                    }
                    return null;
                  },
                ),
                if (adelanto != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    adelanto,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.of(
              context,
            ).pop(double.parse(_montoController.text.trim()));
          },
          child: const Text('Confirmar pago'),
        ),
      ],
    );
  }
}
