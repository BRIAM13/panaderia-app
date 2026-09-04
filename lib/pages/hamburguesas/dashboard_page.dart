import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../models/analitica_model.dart';
import '../../models/tienda_model.dart';
import '../../models/tienda_resumen_model.dart';
import '../../models/usuario_sesion.dart';
import '../../services/api_client.dart';
import '../../services/clientes_service.dart';
import '../../services/notificaciones_service.dart';
import '../../services/tiendas_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/contacto_utils.dart';
import '../../widgets/contador_animado.dart';
import '../../widgets/dashboard/metricas_avanzadas_dashboard.dart';
import '../../widgets/escritorio.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/premium_button.dart';
import '../../widgets/selector_desplegable.dart';
import '../../widgets/selector_fecha_calendario.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/tarjeta_3d.dart';
import '../horneados/deudas_horneados_page.dart';
import '../horneados/nuevo_pedido_horneados_page.dart';
import '../horneados/pedidos_horneados_page.dart';
import 'analitica_page.dart';
import 'clientes_page.dart';
import 'deudas_page.dart';
import 'historial_ventas_page.dart';
import 'nuevo_pedido_page.dart';
import 'pedidos_page.dart';

/// Landing del ADMIN/SUPERADMIN al entrar en su vista de personal: un
/// resumen del negocio con gráficos, de un vistazo — reemplaza el grid
/// genérico "Elige tu tienda" para estos roles. Se actualiza solo cuando
/// llega una notificación push de cambio de pedido (mismo mecanismo que
/// los dashboards de Pedidos/Mis pedidos).
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.usuario});

  final UsuarioSesion usuario;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _tiendasService = TiendasService();
  final _clientesService = ClientesService();
  final _buscarClienteController = TextEditingController();
  StreamSubscription<void>? _suscripcionPush;

  bool _cargando = true;
  String? _error;
  List<Tienda> _tiendas = [];
  Tienda? _tiendaSeleccionada;
  TiendaResumen? _resumen;

  /// Día que se está mirando arriba (cobrado/deuda/ticket del día). null =
  /// hoy. El endpoint de resumen ya aceptaba `?fecha=` desde siempre, pero
  /// hasta ahora solo lo usaba Historial de ventas: desde el tablero no
  /// había forma de preguntar "¿cómo nos fue ayer?" sin entrar a otra
  /// pantalla.
  DateTime? _fechaResumen;

  /// Días de la tienda seleccionada que tienen al menos una venta, y de
  /// esos cuáles arrastran deuda — alimentan el calendario de arriba (ver
  /// [_elegirFecha]). Es la MISMA llamada que ya hacía Historial de ventas.
  List<DateTime> _fechasConDatos = [];
  List<DateTime> _fechasConDeuda = [];

  /// Cartera de clientes segmentada (`/clientes/analitica/resumen-segmentos`,
  /// solo ADMIN/SUPERADMIN). Es la MISMA llamada que ya hacía la pantalla de
  /// Analítica: acá se usa solo para sacar la lista "en riesgo" con sus
  /// teléfonos y poder llamarlos desde el tablero, sin navegar a ningún lado.
  ResumenSegmentos? _segmentos;
  bool _cargandoSegmentos = false;

  @override
  void initState() {
    super.initState();
    _cargarTiendas();
    // Recarga sola apenas cambia algún pedido/pago relevante — sin esto,
    // el panel se quedaba mostrando cifras viejas hasta refrescar a mano.
    _suscripcionPush = NotificacionesService.eventosPedido.listen(
      (_) => _cargarResumen(silencioso: true),
    );
  }

  @override
  void dispose() {
    _buscarClienteController.dispose();
    _suscripcionPush?.cancel();
    super.dispose();
  }

  /// Este Dashboard es tienda-agnóstico (el selector de abajo puede apuntar
  /// a cualquier tienda asignada), pero Horneados tiene endpoints y pantallas
  /// propias (campos custom — carne, presentación, aderezo) — sin esta rama,
  /// tocar cualquiera de esas tarjetas con Horneados seleccionado abría la
  /// pantalla de catálogo simple (vacía para Horneados, o mezclando datos de
  /// la tienda equivocada). El resto (Hamburguesas, Panadería) comparte las
  /// mismas páginas, parametrizadas por `_tiendaSeleccionada`.
  bool get _esHorneados => _tiendaSeleccionada?.slug == 'horneados';

  void _abrirPedidos() {
    if (_esHorneados) {
      pushSlideUpFade(context, (_) => const PedidosHorneadosPage());
      return;
    }
    final tienda = _tiendaSeleccionada;
    if (tienda == null) return;
    pushSlideUpFade(context, (_) => PedidosPage(tienda: tienda));
  }

  /// Acceso directo a registrar un pedido nuevo desde el propio Dashboard —
  /// antes solo se llegaba entrando primero a Pedidos y tocando su botón
  /// flotante, dos pasos que no eran obvios para quien recién entra.
  Future<void> _abrirNuevoPedido() async {
    if (_esHorneados) {
      final registrado = await pushSlideUpFade<bool>(
        context,
        (_) => const NuevoPedidoHorneadosPage(),
      );
      if (registrado == true) _cargarResumen();
      return;
    }
    final tienda = _tiendaSeleccionada;
    if (tienda == null) return;
    final registrado = await pushSlideUpFade<bool>(
      context,
      (_) => NuevoPedidoPage(tienda: tienda),
    );
    if (registrado == true) _cargarResumen();
  }

  void _abrirDeudas() {
    if (_esHorneados) {
      pushSlideUpFade(context, (_) => const DeudasHorneadosPage());
      return;
    }
    final tienda = _tiendaSeleccionada;
    if (tienda == null) return;
    pushSlideUpFade(context, (_) => DeudasPage(tienda: tienda));
  }

  /// Solo Admin/Superadmin pueden entrar al historial completo de ventas —
  /// un Trabajador raso ve la tarjeta "Ventas de hoy" igual, pero no puede
  /// tocarla (ver [_esGestorDeVentas] y su uso en build()).
  bool get _esGestorDeVentas =>
      widget.usuario.rol == 'ADMIN' || widget.usuario.rol == 'SUPERADMIN';

  void _abrirHistorialVentas() {
    final tienda = _tiendaSeleccionada;
    if (tienda == null) return;
    pushSlideUpFade(context, (_) => HistorialVentasPage(tienda: tienda));
  }

  /// Clientes, opcionalmente ya filtrado por lo que se escribió en el
  /// buscador del tablero — así "¿este DNI es cliente nuestro?" se resuelve
  /// escribiéndolo acá, sin abrir Clientes y volver a tipearlo.
  void _abrirClientes({String? busqueda}) {
    pushSlideUpFade(
      context,
      (_) => ClientesPage(usuario: widget.usuario, busquedaInicial: busqueda),
    );
  }

  void _abrirAnalitica() {
    pushSlideUpFade(context, (_) => AnaliticaPage(usuario: widget.usuario));
  }

  /// Calendario propio (el mismo de Historial de ventas) en vez del
  /// `showDatePicker` de Material, por dos razones concretas que reportó el
  /// dueño: el de Material sale en INGLÉS (nombres de mes/día, "Cancel"/
  /// "OK") y deja elegir cualquier día del último año, incluidos los cientos
  /// que no tuvieron ninguna venta — buscar "el día que vendimos harto" a
  /// ciegas, día por día. Acá solo se pueden tocar los días con ventas
  /// reales (más hoy, siempre, para volver al modo en vivo) y los que
  /// arrastran deuda salen marcados con un aro.
  Future<void> _elegirFecha() async {
    final hoy = DateTime.now();
    final soloHoy = DateTime(hoy.year, hoy.month, hoy.day);
    final elegida = await mostrarSelectorFechaVentas(
      context: context,
      fechaSeleccionada: _fechaResumen ?? soloHoy,
      fechasHabilitadas: _fechasConDatos,
      fechasConDeuda: _fechasConDeuda,
    );
    if (elegida == null) return;
    setState(() {
      // Elegir el día de hoy vuelve al modo "en vivo" (sin `?fecha=`), que
      // es lo que el push de notificaciones refresca solo.
      _fechaResumen = elegida.isAtSameMomentAs(soloHoy) ? null : elegida;
    });
    await _cargarResumen();
  }

  bool get _viendoHoy => _fechaResumen == null;

  Future<void> _cargarTiendas() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final tiendas = await _tiendasService.misTiendas();
      setState(() {
        _tiendas = tiendas;
        _tiendaSeleccionada = tiendas.isNotEmpty ? tiendas.first : null;
      });
      if (_tiendaSeleccionada != null) await _cargarResumen();
      unawaited(_cargarSegmentos());
      unawaited(_cargarFechasConVentas());
    } on ApiException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(() => _error = 'No se pudieron cargar tus tiendas.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _cargarResumen({bool silencioso = false}) async {
    if (_tiendaSeleccionada == null) return;
    if (!silencioso) {
      setState(() {
        _cargando = true;
        _error = null;
      });
    }
    try {
      final resumen = await _tiendasService.resumen(
        _tiendaSeleccionada!.idTienda,
        fecha: _fechaResumen,
      );
      if (mounted) setState(() => _resumen = resumen);
    } on ApiException catch (e) {
      if (!silencioso) setState(() => _error = e.mensaje);
    } catch (_) {
      if (!silencioso) {
        setState(() => _error = 'No se pudo cargar el resumen de la tienda.');
      }
    } finally {
      if (mounted && !silencioso) setState(() => _cargando = false);
    }
  }

  /// Días con ventas de la tienda que se está mirando — se pide aparte del
  /// resumen (y sin bloquearlo) porque solo lo consume el calendario: si
  /// falla, el tablero se dibuja igual y el calendario simplemente se abre
  /// con hoy como único día elegible.
  ///
  /// Se vuelve a pedir cada vez que cambia [_tiendaSeleccionada] — los días
  /// con ventas son de la tienda, no del usuario, y quedarse con los de la
  /// tienda anterior habilitaría días que en esta no existen.
  Future<void> _cargarFechasConVentas() async {
    final tienda = _tiendaSeleccionada;
    if (tienda == null) return;
    try {
      final fechas = await _tiendasService.fechasConVentas(tienda.idTienda);
      // Si el usuario ya cambió de tienda mientras volvía esta respuesta,
      // se descarta: son los días de la tienda equivocada.
      if (!mounted || _tiendaSeleccionada?.idTienda != tienda.idTienda) return;
      setState(() {
        _fechasConDatos = fechas.fechas;
        _fechasConDeuda = fechas.fechasConDeuda;
      });
    } catch (_) {
      // Silencioso a propósito: es el insumo de un selector, no del tablero.
    }
  }

  /// Cambiar de tienda desde cualquiera de los dos encabezados (celular y
  /// escritorio arman su propio selector) recarga las DOS cosas que dependen
  /// de la tienda: el resumen y los días elegibles del calendario.
  void _cambiarTienda(Tienda? tienda) {
    if (tienda == null) return;
    setState(() {
      _tiendaSeleccionada = tienda;
      // Los días con ventas de la tienda anterior no valen acá; se vacían
      // hasta que llegue la lista nueva, así el calendario nunca ofrece un
      // día que en esta tienda no tuvo ninguna venta.
      _fechasConDatos = [];
      _fechasConDeuda = [];
    });
    _cargarResumen();
    unawaited(_cargarFechasConVentas());
  }

  /// Una sola petición extra, en paralelo y sin bloquear el tablero: si
  /// falla (o el rol no tiene permiso) simplemente no se dibuja el bloque de
  /// "clientes en riesgo" y todo lo demás sigue igual.
  Future<void> _cargarSegmentos() async {
    if (!_esGestorDeVentas || _cargandoSegmentos) return;
    setState(() => _cargandoSegmentos = true);
    try {
      final segmentos = await _clientesService.obtenerResumenSegmentos();
      if (mounted) setState(() => _segmentos = segmentos);
    } catch (_) {
      // Silencioso a propósito: es un extra del tablero, no su contenido.
    } finally {
      if (mounted) setState(() => _cargandoSegmentos = false);
    }
  }

  Future<void> _refrescarTodo() async {
    await Future.wait([
      _cargarResumen(),
      _cargarSegmentos(),
      _cargarFechasConVentas(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_cargando && _resumen == null) {
      // La primera carga muestra el ESQUELETO del tablero (mismo layout, en
      // shimmer) en vez de un spinner centrado en medio de un océano de
      // fondo vacío: la pantalla ya cuenta qué va a llegar y dónde, así que
      // el salto al contenido real no reacomoda nada. En celular/tablet el
      // esqueleto es el mismo, con la grilla de 2 o 3 columnas que
      // corresponda a ese ancho.
      if (esEscritorio(context)) return const _EsqueletoTableroEscritorio();
      return _EsqueletoTableroCompacto(columnas: esTablet(context) ? 3 : 2);
    }

    if (_error != null && _resumen == null) {
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
                onPressed: _cargarTiendas,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_tiendas.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No tienes tiendas asignadas todavía.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }

    final resumen = _resumen;
    final escritorio = esEscritorio(context);
    // Tablet (600–900): NO es "el celular con más columnas". Cambia la
    // grilla a 3, junta los controles en una fila, acuesta la tarjeta héroe
    // y parte los gráficos en dos — cosas que a 375 px no entran y que
    // antes de este tier tampoco pasaban a 820 px.
    final tablet = esTablet(context);
    final ancho = anchoVentana(context);

    // El tablero de escritorio no es el de celular con más columnas: cambia
    // la composición entera (encabezado con acciones a la derecha, fila de
    // KPIs de alto fijo, gráficos dentro de paneles con título). Vive en su
    // propio método para que la rama de celular quede intacta y legible.
    if (escritorio && resumen != null) {
      return RefreshIndicator(
        onRefresh: _refrescarTodo,
        child: _cuerpoEscritorio(context, resumen),
      );
    }

    final graficoVentas = resumen == null
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ventas de los últimos 7 días',
                style: theme.textTheme.titleMedium,
              ).animate().fadeIn(delay: 300.ms, duration: 300.ms),
              const SizedBox(height: 12),
              _GraficoVentas7Dias(serie: resumen.ventasUltimos7Dias)
                  .animate()
                  .fadeIn(delay: 340.ms, duration: 400.ms)
                  .moveY(begin: 16, end: 0)
                  .flipH(begin: 0.1, end: 0, duration: 350.ms),
            ],
          );

    final graficoUrgencia = resumen == null
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pedidos por entregar, según urgencia',
                style: theme.textTheme.titleMedium,
              ).animate().fadeIn(delay: 380.ms, duration: 300.ms),
              const SizedBox(height: 12),
              _GraficoPendientesPorUrgencia(resumen: resumen)
                  .animate()
                  .fadeIn(delay: 420.ms, duration: 400.ms)
                  .moveY(begin: 16, end: 0)
                  .flipH(begin: 0.1, end: 0, duration: 350.ms),
            ],
          );

    // Botón principal y selector de tienda: en celular siguen apilados a lo
    // ancho (no hay lugar para otra cosa), pero desde 600 px se topan a
    // 320 px y comparten fila — antes se estiraban los dos a 780 px y
    // empujaban el primer dato del negocio debajo del pliegue.
    final controles = <Widget>[
      SizedBox(
        width: tablet ? 320 : double.infinity,
        child: PremiumButton(
          label: 'Registrar pedido',
          icono: Icons.add_shopping_cart_rounded,
          onPressed: _abrirNuevoPedido,
        ),
      ),
      if (_tiendas.length > 1)
        SizedBox(
          width: tablet ? 320 : double.infinity,
          child: SelectorDesplegable<Tienda>(
            valor: _tiendaSeleccionada,
            opciones: _tiendas,
            etiqueta: (t) => t.nombre,
            label: 'Tienda',
            icono: PhosphorIconsRegular.storefront,
            onChanged: _cambiarTienda,
          ),
        ),
      SizedBox(
        width: tablet ? 320 : double.infinity,
        child: _BotonFecha(fecha: _fechaResumen, onElegir: _elegirFecha),
      ),
    ];

    return RefreshIndicator(
      onRefresh: _refrescarTodo,
      child: ListView(
        // Antes acá había 100 px de aire al final "para el FAB": en la vista
        // de personal el Scaffold del Hub no pone ningún FAB ni barra
        // inferior sobre el tablero (ver `floatingActionButton: vistaTrabajador
        // ? null : …` en home_page), así que eran 100 px de vacío.
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Text(
            'Bienvenido, ${widget.usuario.nombreCompleto}',
            style: theme.textTheme.bodyMedium,
          ).animate().fadeIn(duration: 300.ms).moveY(begin: 6, end: 0),
          const SizedBox(height: 4),
          Text('Panel de tu negocio', style: theme.textTheme.titleLarge)
              .animate()
              .fadeIn(delay: 60.ms, duration: 300.ms)
              .moveY(begin: 6, end: 0),
          const SizedBox(height: 16),
          if (tablet)
            Wrap(spacing: 12, runSpacing: 12, children: controles)
                .animate()
                .fadeIn(delay: 90.ms, duration: 300.ms)
                .moveY(begin: 10, end: 0)
          else
            Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < controles.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      controles[i],
                    ],
                  ],
                )
                .animate()
                .fadeIn(delay: 90.ms, duration: 300.ms)
                .moveY(begin: 10, end: 0),
          const SizedBox(height: 16),
          if (resumen != null) ...[
            _bannerAtrasados(resumen),
            // Solo lo cobrado (pagado) del día — la deuda no cuenta acá. Al
            // tocarla (Admin/Superadmin) se abre Historial de ventas.
            // Desde 600 px se usa la variante ACOSTADA (la misma del
            // escritorio, 132 px de alto): la vertical estiraba una tarjeta
            // de 780 px de ancho alrededor de un número de 34 px.
            if (tablet)
              _TarjetaCobradoHoyEscritorio(
                cantidad: resumen.cobradoDiaCantidad,
                total: resumen.cobradoDiaTotal,
                etiqueta: _etiquetaDia,
                onTap: _esGestorDeVentas ? _abrirHistorialVentas : null,
              )
            else
              _TarjetaCobradoHoy(
                    cantidad: resumen.cobradoDiaCantidad,
                    total: resumen.cobradoDiaTotal,
                    etiqueta: _etiquetaDia,
                    onTap: _esGestorDeVentas ? _abrirHistorialVentas : null,
                  )
                  .animate()
                  .fadeIn(delay: 100.ms, duration: 450.ms)
                  .moveY(begin: 18, end: 0, curve: Curves.easeOutCubic)
                  .scale(
                    begin: const Offset(0.94, 0.94),
                    end: const Offset(1, 1),
                    curve: Curves.easeOutCubic,
                  )
                  .flipH(begin: 0.15, end: 0, duration: 400.ms),
            const SizedBox(height: 16),
            GridView.count(
              // 3 columnas en tablet: con 2 quedaban tarjetas de 380 px de
              // ancho, y con 4 (el tier de escritorio) no entra el texto.
              // Seis tarjetas llenan exacto las dos filas en ambos casos.
              crossAxisCount: tablet ? 3 : 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              // Más columnas ⇒ tarjeta más angosta ⇒ hace falta MÁS alto
              // relativo, no menos, para no cortar los subtítulos.
              childAspectRatio: tablet ? 1.25 : 1.05,
              children: _tarjetasEstadistica(resumen),
            ),
            const SizedBox(height: 24),
            _accesosRapidos(),
            const SizedBox(height: 24),
            _buscadorClientes(),
            const SizedBox(height: 24),
            ?_panelEnRiesgo(),
            _panelSemana(resumen),
            const SizedBox(height: 24),
            // Los dos gráficos entran uno al lado del otro bastante antes
            // de los 900 px: a 720 ya quedan ~340 px cada uno, más que los
            // ~335 de un celular, y compararlos de un vistazo es justo para
            // lo que están.
            if (ancho >= 720)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: graficoVentas),
                  const SizedBox(width: 20),
                  Expanded(child: graficoUrgencia),
                ],
              )
            else ...[
              graficoVentas,
              const SizedBox(height: 24),
              graficoUrgencia,
            ],
            const SizedBox(height: 24),
            MetricasAvanzadasDashboard(
              resumen: resumen,
              etiquetaDia: _etiquetaDia,
              enFila: ancho >= 720,
              altoGrafico: tablet ? 240 : 200,
              detallado: ancho >= 720,
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // BLOQUES COMPARTIDOS (celular, tablet y escritorio usan los mismos)
  // ---------------------------------------------------------------------

  /// "hoy" o la fecha elegida — se usa en los textos de las tarjetas del día
  /// para que nadie lea "Cobrado hoy" mirando el martes pasado.
  String get _etiquetaDia => _viendoHoy
      ? 'hoy'
      : 'el ${DateFormat('d MMM', 'es').format(_fechaResumen!)}';

  List<Widget> _tarjetasEstadistica(TiendaResumen resumen) {
    final metricas = _MetricasDerivadas.de(resumen);
    return [
      _TarjetaEstadistica(
        icono: Icons.receipt_long_rounded,
        color: AppColors.secondary,
        titulo: 'Ticket promedio',
        valor: 'S/ ${metricas.ticketPromedio.toStringAsFixed(2)}',
        subtitulo: '${resumen.cobradoDiaCantidad} cobro(s)',
        delay: 120,
        onTap: _esGestorDeVentas ? _abrirHistorialVentas : null,
      ),
      _TarjetaEstadistica(
        icono: Icons.money_off_csred_rounded,
        color: const Color(0xFFB45309),
        titulo: 'Deuda generada',
        valor: 'S/ ${resumen.deudaDiaTotal.toStringAsFixed(2)}',
        subtitulo: '${resumen.deudaDiaCantidad} pedido(s)',
        delay: 140,
        onTap: _abrirDeudas,
      ),
      _TarjetaEstadistica(
        icono: Icons.hourglass_top_rounded,
        color: const Color(0xFFEA8C1B),
        titulo: 'Por confirmar',
        valor: '${resumen.pedidosPorConfirmar}',
        delay: 160,
        onTap: _abrirPedidos,
      ),
      _TarjetaEstadistica(
        icono: Icons.local_shipping_rounded,
        color: const Color(0xFF2563EB),
        titulo: 'Por entregar',
        valor: '${resumen.pendientesTotal}',
        subtitulo: resumen.pendientesAtrasados > 0
            ? '${resumen.pendientesAtrasados} atrasado(s)'
            : null,
        subtituloColor: const Color(0xFFC62828),
        delay: 180,
        onTap: _abrirPedidos,
      ),
      _TarjetaEstadistica(
        icono: Icons.account_balance_wallet_rounded,
        color: const Color(0xFFC62828),
        titulo: 'Deuda total',
        valor: 'S/ ${resumen.deudaTotal.toStringAsFixed(2)}',
        subtitulo: '${resumen.deudaCantidad} pedido(s)',
        delay: 220,
        onTap: _abrirDeudas,
      ),
      _TarjetaEstadistica(
        icono: Icons.qr_code_2_rounded,
        // Era un marrón apagado, indistinguible de las otras tres tarjetas
        // cálidas de la grilla. Verde: es plata que ENTRA (el cliente
        // reportó el pago), y separa la tarjeta del bloque de deudas.
        color: const Color(0xFF17805A),
        titulo: 'Pagos reportados',
        valor: '${resumen.pagosReportados}',
        delay: 260,
        onTap: _abrirDeudas,
      ),
    ];
  }

  /// Los pedidos atrasados eran un subtítulo de 11 px dentro de una tarjeta.
  /// Un pedido que ya venció su fecha de entrega es LA cosa que hay que
  /// mirar primero al abrir el tablero: acá pasa a ser una franja roja
  /// tocable que lleva directo a la lista de pedidos.
  Widget _bannerAtrasados(TiendaResumen resumen) {
    if (resumen.pendientesAtrasados <= 0) return const SizedBox.shrink();
    const rojo = Color(0xFFC62828);
    final cantidad = resumen.pendientesAtrasados;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child:
          Material(
                color: rojo.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  onTap: _abrirPedidos,
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: rojo.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: rojo,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                cantidad == 1
                                    ? '1 pedido atrasado'
                                    : '$cantidad pedidos atrasados',
                                style: const TextStyle(
                                  color: rojo,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Su fecha de entrega ya pasó. Tócalo para resolverlos.',
                                style: Theme.of(
                                  context,
                                ).textTheme.bodyMedium?.copyWith(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: rojo),
                      ],
                    ),
                  ),
                ),
              )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .fadeIn(duration: 250.ms)
              .then()
              .tint(color: rojo.withValues(alpha: 0.04), duration: 1600.ms),
    );
  }

  /// Fila de atajos a pantallas que ya existen. Sin esto, llegar a Clientes
  /// desde el tablero eran tres toques por el menú lateral.
  Widget _accesosRapidos() {
    final atajos = <_AccesoRapido>[
      _AccesoRapido(
        icono: Icons.add_shopping_cart_rounded,
        etiqueta: 'Nuevo pedido',
        color: AppColors.primary,
        onTap: _abrirNuevoPedido,
      ),
      _AccesoRapido(
        icono: Icons.list_alt_rounded,
        etiqueta: 'Pedidos de hoy',
        color: const Color(0xFF2563EB),
        onTap: _abrirPedidos,
      ),
      _AccesoRapido(
        icono: Icons.person_search_rounded,
        etiqueta: 'Buscar cliente',
        color: AppColors.secondary,
        onTap: _abrirClientes,
      ),
      _AccesoRapido(
        icono: Icons.account_balance_wallet_rounded,
        etiqueta: 'Deudas',
        color: const Color(0xFFC62828),
        onTap: _abrirDeudas,
      ),
      if (_esGestorDeVentas) ...[
        _AccesoRapido(
          icono: Icons.history_rounded,
          etiqueta: 'Historial',
          color: const Color(0xFF6D4C41),
          onTap: _abrirHistorialVentas,
        ),
        _AccesoRapido(
          icono: Icons.insights_rounded,
          etiqueta: 'Analítica',
          color: const Color(0xFF7C3AED),
          onTap: _abrirAnalitica,
        ),
      ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Accesos rápidos', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: atajos),
      ],
    ).animate().fadeIn(delay: 200.ms, duration: 300.ms);
  }

  /// "¿Este DNI ya es cliente nuestro?" es una pregunta de mostrador, no de
  /// una pantalla aparte: se escribe acá y se abre Clientes ya filtrado.
  Widget _buscadorClientes() {
    void buscar() {
      final texto = _buscarClienteController.text.trim();
      if (texto.isEmpty) return;
      _abrirClientes(busqueda: texto);
    }

    return TextField(
      controller: _buscarClienteController,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => buscar(),
      decoration: InputDecoration(
        hintText: 'Buscar cliente por nombre, DNI o RUC',
        prefixIcon: const Icon(Icons.person_search_rounded),
        suffixIcon: IconButton(
          icon: const Icon(Icons.arrow_forward_rounded),
          tooltip: 'Buscar en Clientes',
          onPressed: buscar,
        ),
      ),
    );
  }

  /// Los clientes que dejaron de comprar, con su teléfono, listos para
  /// llamar. El endpoint ya devolvía esta lista con teléfonos y solo la
  /// usaba la pantalla de Analítica; acá está donde se decide el día.
  /// Devuelve null (y no un widget vacío) para que el `?` del ListView lo
  /// omita entero cuando no hay nada que mostrar.
  Widget? _panelEnRiesgo() {
    final enRiesgo = _segmentos?.enRiesgo ?? const <ClienteResumenLigero>[];
    if (enRiesgo.isEmpty) return null;
    final theme = Theme.of(context);
    const ambar = Color(0xFFEA8C1B);
    final primeros = enRiesgo.take(3).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child:
          Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: ambar.withValues(alpha: 0.30)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: ambar,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Clientes en riesgo',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: ambar.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${enRiesgo.length}',
                            style: const TextStyle(
                              color: ambar,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Compraban seguido y dejaron de hacerlo. Llámalos hoy.',
                      style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    for (final cliente in primeros)
                      _FilaClienteEnRiesgo(cliente: cliente),
                    if (_esGestorDeVentas) ...[
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _abrirAnalitica,
                          icon: const Icon(
                            Icons.arrow_forward_rounded,
                            size: 16,
                          ),
                          label: Text(
                            enRiesgo.length <= 3
                                ? 'Ver en Analítica'
                                : 'Ver los ${enRiesgo.length}',
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              )
              .animate()
              .fadeIn(delay: 240.ms, duration: 320.ms)
              .moveY(begin: 10, end: 0),
    );
  }

  /// Cómo viene la semana, con la MISMA serie de 7 días que ya alimentaba el
  /// gráfico de barras: total, promedio por día, mejor día y cómo se compara
  /// el día mostrado contra ayer y contra ese promedio.
  Widget _panelSemana(TiendaResumen resumen) {
    final theme = Theme.of(context);
    final m = _MetricasDerivadas.de(resumen);
    final mejor = m.mejorDia;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.surfaceMuted, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.calendar_month_rounded,
                size: 20,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Los últimos 7 días',
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _DatoSemana(
                  etiqueta: 'Total cobrado',
                  valor: 'S/ ${m.totalSemana.toStringAsFixed(2)}',
                ),
              ),
              Expanded(
                child: _DatoSemana(
                  etiqueta: 'Promedio por día',
                  valor: 'S/ ${m.promedioSemana.toStringAsFixed(2)}',
                ),
              ),
              Expanded(
                child: _DatoSemana(
                  etiqueta: 'Mejor día',
                  valor: mejor == null
                      ? '—'
                      : DateFormat('EEE', 'es').format(mejor.fecha),
                  detalle: mejor == null
                      ? null
                      : 'S/ ${mejor.total.toStringAsFixed(2)}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ChipVariacion(etiqueta: 'vs. ayer', variacion: m.variacionAyer),
              _ChipVariacion(
                etiqueta: 'vs. promedio de la semana',
                variacion: m.variacionPromedio,
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(delay: 260.ms, duration: 320.ms);
  }

  // ---------------------------------------------------------------------
  // ESCRITORIO
  // ---------------------------------------------------------------------

  /// Tablero para ventana ancha. Tres bandas horizontales, de arriba abajo:
  /// encabezado con las acciones a la derecha, fila de indicadores de alto
  /// fijo y, abajo, los dos gráficos dentro de paneles con título.
  Widget _cuerpoEscritorio(BuildContext context, TiendaResumen resumen) {
    // Con el panel lateral fijo del Hub comiéndose 300 px, recién a partir
    // de [Breakpoints.escritorioComodo] quedan ~800 px útiles: es el punto
    // donde 5 tarjetas en una sola fila (el héroe + 4 KPIs) siguen siendo
    // legibles. Por debajo se parte en dos bandas de 2 KPIs.
    final comodo = esEscritorioComodo(context);

    final kpis = <Widget>[
      TarjetaKpi(
        icono: Icons.hourglass_top_rounded,
        color: const Color(0xFFEA8C1B),
        titulo: 'Por confirmar',
        valor: '${resumen.pedidosPorConfirmar}',
        delay: 140,
        onTap: _abrirPedidos,
      ),
      TarjetaKpi(
        icono: Icons.local_shipping_rounded,
        color: const Color(0xFF2563EB),
        titulo: 'Por entregar',
        valor: '${resumen.pendientesTotal}',
        subtitulo: resumen.pendientesAtrasados > 0
            ? '${resumen.pendientesAtrasados} atrasado(s)'
            : null,
        subtituloColor: const Color(0xFFC62828),
        delay: 180,
        onTap: _abrirPedidos,
      ),
      TarjetaKpi(
        icono: Icons.account_balance_wallet_rounded,
        color: const Color(0xFFC62828),
        titulo: 'Deuda total',
        valor: 'S/ ${resumen.deudaTotal.toStringAsFixed(2)}',
        subtitulo: '${resumen.deudaCantidad} pedido(s)',
        delay: 220,
        onTap: _abrirDeudas,
      ),
      TarjetaKpi(
        icono: Icons.qr_code_2_rounded,
        color: const Color(0xFF17805A),
        titulo: 'Pagos reportados',
        valor: '${resumen.pagosReportados}',
        delay: 260,
        onTap: _abrirDeudas,
      ),
    ];

    final heroe = _TarjetaCobradoHoyEscritorio(
      cantidad: resumen.cobradoDiaCantidad,
      total: resumen.cobradoDiaTotal,
      etiqueta: _etiquetaDia,
      onTap: _esGestorDeVentas ? _abrirHistorialVentas : null,
    );

    final metricas = _MetricasDerivadas.de(resumen);

    // Todas las tarjetas de la banda declaran el mismo alto fijo (132), así
    // que alcanza con alinearlas arriba: no hace falta IntrinsicHeight.
    final Widget bandaIndicadores = comodo
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: heroe),
              const SizedBox(width: 16),
              for (var i = 0; i < kpis.length; i++) ...[
                if (i > 0) const SizedBox(width: 16),
                Expanded(flex: 2, child: kpis[i]),
              ],
            ],
          )
        : Column(
            children: [
              heroe,
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: kpis[0]),
                  const SizedBox(width: 16),
                  Expanded(child: kpis[1]),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: kpis[2]),
                  const SizedBox(width: 16),
                  Expanded(child: kpis[3]),
                ],
              ),
            ],
          );

    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 56),
      children: [
        ContenidoCentrado(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EncabezadoEscritorio(
                anteTitulo: 'HOLA, ${widget.usuario.nombreCompleto}',
                titulo: 'Panel de tu negocio',
                subtitulo:
                    'Cobros del día, deudas abiertas y entregas pendientes, '
                    'todo en una sola vista.',
                acciones: [
                  // En celular estos dos controles van apilados a lo ancho y
                  // empujan el primer dato debajo del pliegue. Acá caben en
                  // la misma línea del título, que era espacio muerto.
                  if (_tiendas.length > 1)
                    SizedBox(
                      width: 220,
                      child: SelectorDesplegable<Tienda>(
                        valor: _tiendaSeleccionada,
                        opciones: _tiendas,
                        etiqueta: (t) => t.nombre,
                        label: 'Tienda',
                        icono: PhosphorIconsRegular.storefront,
                        denso: true,
                        onChanged: _cambiarTienda,
                      ),
                    ),
                  SizedBox(
                    width: 200,
                    child: _BotonFecha(
                      fecha: _fechaResumen,
                      onElegir: _elegirFecha,
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: PremiumButton(
                      label: 'Registrar pedido',
                      icono: Icons.add_shopping_cart_rounded,
                      onPressed: _abrirNuevoPedido,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              bandaIndicadores,
              const SizedBox(height: espacioEscritorio),
              _bannerAtrasados(resumen),
              // Ticket promedio y deuda del día viven pegados al total
              // cobrado (son lecturas del MISMO día) y comparten fila con el
              // resumen de la semana, que los pone en contexto.
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: TarjetaKpi(
                        icono: Icons.receipt_long_rounded,
                        color: AppColors.secondary,
                        titulo: 'Ticket promedio',
                        valor:
                            'S/ ${metricas.ticketPromedio.toStringAsFixed(2)}',
                        subtitulo: '${resumen.cobradoDiaCantidad} cobro(s)',
                        delay: 280,
                        onTap: _esGestorDeVentas ? _abrirHistorialVentas : null,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TarjetaKpi(
                        icono: Icons.money_off_csred_rounded,
                        color: const Color(0xFFB45309),
                        titulo: 'Deuda generada',
                        valor: 'S/ ${resumen.deudaDiaTotal.toStringAsFixed(2)}',
                        subtitulo: '${resumen.deudaDiaCantidad} pedido(s)',
                        delay: 300,
                        onTap: _abrirDeudas,
                      ),
                    ),
                    const SizedBox(width: espacioEscritorio),
                    Expanded(flex: 2, child: _panelSemana(resumen)),
                  ],
                ),
              ),
              const SizedBox(height: espacioEscritorio),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: _accesosRapidos()),
                  const SizedBox(width: espacioEscritorio),
                  SizedBox(width: 340, child: _buscadorClientes()),
                ],
              ),
              const SizedBox(height: espacioEscritorio),
              ?_panelEnRiesgo(),
              // Los dos gráficos, uno al lado del otro y más altos que en
              // celular (300 px contra 200-220): con ese alto ya vale la
              // pena dibujar el eje de valores y las guías horizontales, así
              // que en escritorio se leen cifras concretas y no solo la
              // silueta de las barras.
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: PanelEscritorio(
                        icono: Icons.show_chart_rounded,
                        titulo: 'Ventas de los últimos 7 días',
                        subtitulo: 'Solo pedidos ya cobrados.',
                        child:
                            _GraficoVentas7Dias(
                                  serie: resumen.ventasUltimos7Dias,
                                  alto: 300,
                                  conMarco: false,
                                  detallado: true,
                                )
                                .animate()
                                .fadeIn(delay: 320.ms, duration: 400.ms)
                                .moveY(begin: 16, end: 0),
                      ),
                    ),
                    const SizedBox(width: espacioEscritorio),
                    Expanded(
                      child: PanelEscritorio(
                        icono: Icons.local_shipping_rounded,
                        titulo: 'Pedidos por entregar',
                        subtitulo: 'Agrupados por urgencia, para priorizar.',
                        child:
                            _GraficoPendientesPorUrgencia(
                                  resumen: resumen,
                                  alto: 300,
                                  conMarco: false,
                                  detallado: true,
                                )
                                .animate()
                                .fadeIn(delay: 380.ms, duration: 400.ms)
                                .moveY(begin: 16, end: 0),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: espacioEscritorio),
              MetricasAvanzadasDashboard(
                resumen: resumen,
                etiquetaDia: _etiquetaDia,
                enFila: true,
                altoGrafico: 300,
                detallado: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Versión de escritorio de "Cobrado hoy": la misma tarjeta con degradado de
/// marca, pero acostada — en una fila de indicadores de 132 px de alto, la
/// versión vertical de celular obligaría a estirar toda la banda.
class _TarjetaCobradoHoyEscritorio extends StatelessWidget {
  const _TarjetaCobradoHoyEscritorio({
    required this.cantidad,
    required this.total,
    required this.etiqueta,
    this.onTap,
  });

  final int cantidad;
  final double total;

  /// "hoy" o el día elegido en el selector de fecha — sin esto la tarjeta
  /// decía "Cobrado hoy" aunque se estuviera mirando el martes pasado.
  final String etiqueta;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TarjetaEscritorio(
          onTap: onTap,
          acento: AppColors.primary,
          alto: 132,
          bordeVisible: false,
          padding: const EdgeInsets.fromLTRB(22, 16, 20, 16),
          gradiente: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primary, AppColors.secondary],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                        Icons.trending_up_rounded,
                        color: Colors.white,
                        size: 20,
                      )
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .scale(
                        begin: const Offset(1, 1),
                        end: const Offset(1.15, 1.15),
                        duration: 1400.ms,
                        curve: Curves.easeInOut,
                      ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Cobrado $etiqueta',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(color: Colors.white),
                    ),
                  ),
                  if (onTap != null)
                    const Icon(
                      Icons.arrow_outward_rounded,
                      size: 16,
                      color: Colors.white70,
                    ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ContadorAnimado(
                    valor: total,
                    formatear: (v) => 'S/ ${v.toStringAsFixed(2)}',
                    estilo: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$cantidad pedido(s) cobrado(s) $etiqueta',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        )
        .animate()
        .fadeIn(duration: 400.ms)
        .moveY(begin: 14, end: 0, curve: Curves.easeOutCubic);
  }
}

/// Esqueleto del tablero mientras llega la primera respuesta: replica la
/// silueta real (encabezado, banda de 5 indicadores, dos paneles de
/// gráfico) con [SkeletonBox], para que la pantalla no salte al llenarse.
class _EsqueletoTableroEscritorio extends StatelessWidget {
  const _EsqueletoTableroEscritorio();

  @override
  Widget build(BuildContext context) {
    Widget marco({required double alto, required Widget child}) => Container(
      height: alto,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.surfaceMuted, width: 1.2),
      ),
      child: child,
    );

    final tarjeta = marco(
      alto: 132,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: const [
          SkeletonBox(width: 38, height: 38, borderRadius: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 96, height: 24),
              SizedBox(height: 8),
              SkeletonBox(width: 64, height: 11),
            ],
          ),
        ],
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 56),
      children: [
        ContenidoCentrado(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SkeletonBox(width: 180, height: 12),
              const SizedBox(height: 10),
              const SkeletonBox(width: 320, height: 28),
              const SizedBox(height: 32),
              Row(
                children: [
                  for (var i = 0; i < 5; i++) ...[
                    if (i > 0) const SizedBox(width: 16),
                    Expanded(child: tarjeta),
                  ],
                ],
              ),
              const SizedBox(height: espacioEscritorio),
              Row(
                children: [
                  Expanded(
                    child: marco(
                      alto: 380,
                      child: const SkeletonBox(
                        height: double.infinity,
                        borderRadius: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: espacioEscritorio),
                  Expanded(
                    child: marco(
                      alto: 380,
                      child: const SkeletonBox(
                        height: double.infinity,
                        borderRadius: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Tarjeta única "Cobrado hoy" — solo pedidos ENTREGADO+PAGADO, la deuda no
/// se cuenta acá. Al tocarla (Admin/Superadmin) se abre Historial de
/// ventas, que trae el desglose completo (cobrado/deuda por día, con
/// selector de fecha) y el historial jerárquico de pedidos resueltos.
class _TarjetaCobradoHoy extends StatelessWidget {
  const _TarjetaCobradoHoy({
    required this.cantidad,
    required this.total,
    required this.etiqueta,
    this.onTap,
  });

  final int cantidad;
  final double total;

  /// "hoy" o el día elegido en el selector de fecha.
  final String etiqueta;

  /// Solo presente para Admin/Superadmin — un Trabajador raso ve esta
  /// misma tarjeta pero no puede entrar al historial completo de ventas.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tarjeta3D(
      borderRadius: 24,
      profundidad: 0.0022,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primary, AppColors.secondary],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.trending_up_rounded, color: Colors.white, size: 20)
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .scale(
                      begin: const Offset(1, 1),
                      end: const Offset(1.15, 1.15),
                      duration: 1400.ms,
                      curve: Curves.easeInOut,
                    ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Cobrado $etiqueta',
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: Colors.white),
                  ),
                ),
                if (onTap != null)
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white70,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            ContadorAnimado(
              valor: total,
              formatear: (v) => 'S/ ${v.toStringAsFixed(2)}',
              estilo: const TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$cantidad pedido(s) cobrado(s) $etiqueta',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cifras que salen de mirar el MISMO `/tiendas/:id/resumen` que el tablero
/// ya pedía — no hay ninguna petición nueva detrás de ninguna de estas.
///
/// Nota sobre "el mismo día de la semana pasada": la serie que devuelve el
/// backend son 7 días CONTANDO hoy (hoy-6 … hoy), así que el mismo día de la
/// semana pasada (hoy-7) no está en ella y no se puede calcular sin pedirle
/// otra cosa al servidor. En su lugar se compara contra el promedio de esos
/// 7 días, que responde la misma pregunta ("¿hoy fue mejor o peor de lo
/// normal?") con los datos que sí hay.
class _MetricasDerivadas {
  const _MetricasDerivadas._({
    required this.ticketPromedio,
    required this.totalSemana,
    required this.promedioSemana,
    required this.mejorDia,
    required this.variacionAyer,
    required this.variacionPromedio,
  });

  factory _MetricasDerivadas.de(TiendaResumen resumen) {
    final serie = resumen.ventasUltimos7Dias;
    final totalSemana = serie.fold<double>(0, (acc, v) => acc + v.total);
    final promedio = serie.isEmpty ? 0.0 : totalSemana / serie.length;
    final hoy = serie.isNotEmpty ? serie.last.total : 0.0;
    final ayer = serie.length >= 2 ? serie[serie.length - 2].total : null;

    VentaDiaria? mejor;
    for (final dia in serie) {
      if (mejor == null || dia.total > mejor.total) mejor = dia;
    }

    return _MetricasDerivadas._(
      // Ticket promedio del día mostrado. Con cero cobros el promedio no
      // existe (no es cero): se muestra 0 pero el subtítulo ya dice
      // "0 cobro(s)", así que no se lee como una caída de ventas.
      ticketPromedio: resumen.cobradoDiaCantidad == 0
          ? 0
          : resumen.cobradoDiaTotal / resumen.cobradoDiaCantidad,
      totalSemana: totalSemana,
      promedioSemana: promedio,
      mejorDia: mejor != null && mejor.total > 0 ? mejor : null,
      variacionAyer: ayer == null || ayer <= 0
          ? null
          : (hoy - ayer) / ayer * 100,
      variacionPromedio: promedio <= 0
          ? null
          : (hoy - promedio) / promedio * 100,
    );
  }

  final double ticketPromedio;
  final double totalSemana;
  final double promedioSemana;

  /// null si en los 7 días no se cobró nada — un "mejor día" de S/ 0 no
  /// significa nada.
  final VentaDiaria? mejorDia;

  /// Porcentaje de cambio de hoy contra ayer / contra el promedio de la
  /// semana. null cuando la base es 0 (dividir por cero no da "+∞%", da una
  /// comparación que no existe).
  final double? variacionAyer;
  final double? variacionPromedio;
}

/// Selector del día que se está mirando arriba. Tiene el aspecto de un campo
/// del formulario (no de un botón suelto) para que se lea como "estoy
/// filtrando por esta fecha".
class _BotonFecha extends StatelessWidget {
  const _BotonFecha({required this.fecha, required this.onElegir});

  final DateTime? fecha;
  final VoidCallback onElegir;

  @override
  Widget build(BuildContext context) {
    final hoy = fecha == null;
    // Antes esto era un borde gris sobre nada: la pastilla de fecha, que es
    // uno de los dos controles del tablero, se leía como texto suelto. Los
    // dos estados pasan a ser pastillas LLENAS de la paleta — miel para
    // "Hoy" (el estado por defecto) y durazno/terracota cuando hay una fecha
    // elegida, que es justamente el estado que conviene que salte a la vista.
    final relleno = hoy ? AppColors.secondarySoft : AppColors.primaryContainer;
    final tinta = hoy ? AppColors.secondaryDeep : AppColors.primaryDeep;

    return OutlinedButton.icon(
      onPressed: onElegir,
      icon: Icon(
        hoy ? Icons.today_rounded : Icons.event_rounded,
        size: 18,
        color: tinta,
      ),
      label: Text(
        hoy ? 'Hoy' : DateFormat('d MMM yyyy', 'es').format(fecha!),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: tinta,
        backgroundColor: relleno,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        side: BorderSide(
          color: (hoy ? AppColors.secondary : AppColors.primary).withValues(
            alpha: 0.45,
          ),
          width: 1.4,
        ),
      ),
    );
  }
}

/// Atajo a una pantalla que ya existe: ícono teñido + etiqueta corta.
class _AccesoRapido extends StatelessWidget {
  const _AccesoRapido({
    required this.icono,
    required this.etiqueta,
    required this.color,
    required this.onTap,
  });

  final IconData icono;
  final String etiqueta;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ZonaHover(
      builder: (context, hover) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        transform: Matrix4.translationValues(0, hover ? -2 : 0, 0),
        decoration: BoxDecoration(
          color: color.withValues(alpha: hover ? 0.14 : 0.09),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withValues(alpha: hover ? 0.45 : 0.24),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icono, size: 18, color: color),
                  const SizedBox(width: 8),
                  Text(
                    etiqueta,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Un cliente de la lista "en riesgo" con los dos botones que resuelven el
/// problema en el acto: llamarlo o escribirle por WhatsApp.
class _FilaClienteEnRiesgo extends StatelessWidget {
  const _FilaClienteEnRiesgo({required this.cliente});

  final ClienteResumenLigero cliente;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final telefono = cliente.telefono;
    final contactable = tieneTelefonoUtil(telefono);
    final dias = cliente.diasDesdeUltimaCompra;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cliente.nombre,
                  style: theme.textTheme.titleMedium?.copyWith(fontSize: 14.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  dias == null
                      ? 'Sin compras registradas'
                      : 'Hace $dias días que no compra',
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: contactable ? () => llamarPorTelefono(telefono!) : null,
            icon: const Icon(Icons.call_rounded, size: 19),
            tooltip: contactable ? 'Llamar' : 'Sin teléfono registrado',
            visualDensity: VisualDensity.compact,
            color: const Color(0xFF2563EB),
          ),
          IconButton(
            onPressed: contactable
                ? () => abrirWhatsApp(
                    telefono!,
                    mensaje:
                        'Hola ${cliente.nombre}, te extrañamos en Panadería '
                        'Ronceros. ¿Te preparamos algo rico?',
                  )
                : null,
            icon: const Icon(Icons.chat_rounded, size: 19),
            tooltip: contactable ? 'WhatsApp' : 'Sin teléfono registrado',
            visualDensity: VisualDensity.compact,
            color: const Color(0xFF2E7D32),
          ),
        ],
      ),
    );
  }
}

/// Una cifra del bloque "los últimos 7 días".
class _DatoSemana extends StatelessWidget {
  const _DatoSemana({
    required this.etiqueta,
    required this.valor,
    this.detalle,
  });

  final String etiqueta;
  final String valor;
  final String? detalle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          valor,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        if (detalle != null)
          Text(
            detalle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(fontSize: 11.5),
          ),
        Text(
          etiqueta,
          maxLines: 2,
          style: theme.textTheme.bodyMedium?.copyWith(fontSize: 11.5),
        ),
      ],
    );
  }
}

/// "+18% vs. ayer" en verde / rojo, o un chip apagado cuando la comparación
/// no se puede hacer (ayer no se cobró nada: no hay contra qué comparar).
class _ChipVariacion extends StatelessWidget {
  const _ChipVariacion({required this.etiqueta, required this.variacion});

  final String etiqueta;
  final double? variacion;

  @override
  Widget build(BuildContext context) {
    final v = variacion;
    final sinDato = v == null;
    final sube = !sinDato && v >= 0;
    final color = sinDato
        ? AppColors.textSecondary
        : sube
        ? const Color(0xFF2E7D32)
        : const Color(0xFFC62828);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            sinDato
                ? Icons.remove_rounded
                : sube
                ? Icons.trending_up_rounded
                : Icons.trending_down_rounded,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            sinDato
                ? 'Sin datos $etiqueta'
                : '${sube ? '+' : ''}${v.toStringAsFixed(0)}% $etiqueta',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Esqueleto del tablero en celular/tablet: la misma silueta que se va a
/// llenar (encabezado, controles, tarjeta héroe, grilla de KPIs, gráfico)
/// en shimmer. Antes acá había un spinner solo en medio de la pantalla, que
/// no anticipa nada y hace que todo salte al llegar los datos.
class _EsqueletoTableroCompacto extends StatelessWidget {
  const _EsqueletoTableroCompacto({required this.columnas});

  /// 2 en celular, 3 en tablet — igual que la grilla real.
  final int columnas;

  @override
  Widget build(BuildContext context) {
    Widget marco({double? alto, Widget? child}) => Container(
      height: alto,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surfaceMuted, width: 1.2),
      ),
      child: child,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        const SkeletonBox(width: 160, height: 12),
        const SizedBox(height: 10),
        const SkeletonBox(width: 220, height: 24),
        const SizedBox(height: 20),
        const SkeletonBox(height: 52, borderRadius: 16),
        const SizedBox(height: 16),
        marco(alto: 132),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: columnas,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: columnas >= 3 ? 1.25 : 1.05,
          children: [
            for (var i = 0; i < 6; i++)
              marco(
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SkeletonBox(width: 32, height: 32, borderRadius: 12),
                    SizedBox(height: 10),
                    SkeletonBox(width: 70, height: 18),
                    SizedBox(height: 6),
                    SkeletonBox(width: 50, height: 10),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        marco(alto: 220),
      ],
    );
  }
}

class _TarjetaEstadistica extends StatelessWidget {
  const _TarjetaEstadistica({
    required this.icono,
    required this.color,
    required this.titulo,
    required this.valor,
    this.subtitulo,
    this.subtituloColor,
    required this.delay,
    this.onTap,
  });

  final IconData icono;
  final Color color;
  final String titulo;
  final String valor;
  final String? subtitulo;
  final Color? subtituloColor;
  final int delay;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final esNumero = double.tryParse(valor.replaceAll(RegExp('[^0-9.]'), ''));

    // Las cuatro tarjetas eran crema sobre crema, con un círculo pastel al
    // 12 % de opacidad: contra el fondo del tablero no contrastaban con
    // nada y las cuatro se leían como una sola mancha. Ahora cada una lleva
    // su color en tres lugares — un lavado del 9 % de fondo, el borde al
    // 30 % y la placa del ícono LLENA — así se distinguen de un vistazo sin
    // que ninguna grite: el color fuerte ocupa apenas los 32 px de la placa.
    final fondo = Color.alphaBlend(
      color.withValues(alpha: 0.11),
      AppColors.surface,
    );

    return Tarjeta3D(
          onTap: onTap,
          borderRadius: 20,
          child: Material(
            color: fondo,
            child: InkWell(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: color.withValues(alpha: 0.50),
                    width: 1.4,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Icon(icono, color: Colors.white, size: 18),
                    ),
                    const SizedBox(height: 8),
                    esNumero != null
                        ? ContadorAnimado(
                            valor: esNumero,
                            formatear: (v) => valor.startsWith('S/')
                                ? 'S/ ${v.toStringAsFixed(2)}'
                                : v.toStringAsFixed(0),
                            estilo: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          )
                        : Text(
                            valor,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                    Text(
                      titulo,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitulo != null)
                      Text(
                        subtitulo!,
                        style: TextStyle(
                          color: subtituloColor ?? AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ),
          ),
        )
        .animate(delay: delay.ms)
        .fadeIn(duration: 350.ms)
        .moveY(begin: 14, end: 0)
        .flipH(begin: 0.1, end: 0, duration: 320.ms);
  }
}

/// Gráfico de barras de ventas diarias (últimos 7 días) — fl_chart trae su
/// propia animación de entrada para las barras.
class _GraficoVentas7Dias extends StatelessWidget {
  const _GraficoVentas7Dias({
    required this.serie,
    this.alto = 220,
    this.conMarco = true,
    this.detallado = false,
  });

  final List<VentaDiaria> serie;

  /// Alto del área de dibujo. En escritorio sube a 300: con 220 las barras
  /// quedaban tan achatadas que las diferencias entre días no se veían.
  final double alto;

  /// false cuando el gráfico ya va dentro de un [PanelEscritorio] — evita
  /// una tarjeta dentro de otra tarjeta.
  final bool conMarco;

  /// Agrega eje de valores y guías horizontales. Solo tiene sentido con
  /// [alto] grande y ancho de escritorio; en celular sería ruido.
  final bool detallado;

  @override
  Widget build(BuildContext context) {
    final maximo = serie.fold<double>(
      0,
      (acc, v) => v.total > acc ? v.total : acc,
    );
    final techo = maximo <= 0 ? 10.0 : maximo * 1.25;
    final formatoDia = DateFormat('EEE', 'es');

    final grafico = Container(
      height: alto,
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
      color: conMarco ? AppColors.surface : null,
      child: BarChart(
        BarChartData(
          maxY: techo,
          alignment: BarChartAlignment.spaceAround,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                detallado
                    ? '${formatoDia.format(serie[group.x].fecha)}\nS/ ${rod.toY.toStringAsFixed(2)}'
                    : 'S/ ${rod.toY.toStringAsFixed(2)}',
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: detallado,
                reservedSize: 46,
                getTitlesWidget: (value, meta) => Text(
                  'S/ ${value.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final indice = value.toInt();
                  if (indice < 0 || indice >= serie.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      formatoDia.format(serie[indice].fecha),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          gridData: FlGridData(
            show: detallado,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) => FlLine(
              color: AppColors.surfaceMuted,
              strokeWidth: 1,
              dashArray: const [4, 6],
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: serie.asMap().entries.map((entry) {
            final esHoy = entry.key == serie.length - 1;
            return BarChartGroupData(
              x: entry.key,
              barRods: [
                BarChartRodData(
                  toY: entry.value.total,
                  color: esHoy
                      ? AppColors.primary
                      : AppColors.secondary.withValues(alpha: 0.55),
                  width: detallado ? 30 : 22,
                  borderRadius: BorderRadius.circular(6),
                ),
              ],
            );
          }).toList(),
        ),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
      ),
    );

    return conMarco ? Tarjeta3D(child: grafico) : grafico;
  }
}

/// Gráfico de barras horizontal de pedidos pendientes de entrega,
/// agrupados por urgencia — ayuda al administrador a priorizar de un
/// vistazo qué necesita atención primero.
class _GraficoPendientesPorUrgencia extends StatelessWidget {
  const _GraficoPendientesPorUrgencia({
    required this.resumen,
    this.alto = 200,
    this.conMarco = true,
    this.detallado = false,
  });

  final TiendaResumen resumen;
  final double alto;
  final bool conMarco;
  final bool detallado;

  @override
  Widget build(BuildContext context) {
    final categorias = [
      ('Atrasados', resumen.pendientesAtrasados, const Color(0xFFC62828)),
      ('Hoy', resumen.pendientesHoy, AppColors.primary),
      ('Próximos', resumen.pendientesProximos, const Color(0xFF2563EB)),
      ('Sin fecha', resumen.pendientesSinFecha, AppColors.textSecondary),
    ];
    final maximo = categorias.fold<int>(0, (acc, c) => c.$2 > acc ? c.$2 : acc);
    final techo = maximo <= 0 ? 5.0 : maximo * 1.3;

    if (resumen.pendientesTotal == 0) {
      return Container(
        height: conMarco ? 100 : alto,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: conMarco ? AppColors.surface : null,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          'No hay pedidos pendientes de entrega',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    final grafico = Container(
      height: alto,
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
      color: conMarco ? AppColors.surface : null,
      child: BarChart(
        BarChartData(
          maxY: techo,
          alignment: BarChartAlignment.spaceAround,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                detallado
                    ? '${categorias[group.x].$1}\n${rod.toY.toInt()} pedido(s)'
                    : '${rod.toY.toInt()} pedido(s)',
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: detallado,
                reservedSize: 32,
                // Solo enteros: "2.5 pedidos" no existe.
                getTitlesWidget: (value, meta) => value % 1 != 0
                    ? const SizedBox.shrink()
                    : Text(
                        value.toStringAsFixed(0),
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final indice = value.toInt();
                  if (indice < 0 || indice >= categorias.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      categorias[indice].$1,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          gridData: FlGridData(
            show: detallado,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) => FlLine(
              color: AppColors.surfaceMuted,
              strokeWidth: 1,
              dashArray: const [4, 6],
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: categorias.asMap().entries.map((entry) {
            return BarChartGroupData(
              x: entry.key,
              barRods: [
                BarChartRodData(
                  toY: entry.value.$2.toDouble(),
                  color: entry.value.$3,
                  width: detallado ? 38 : 28,
                  borderRadius: BorderRadius.circular(6),
                ),
              ],
            );
          }).toList(),
        ),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
      ),
    );

    return conMarco ? Tarjeta3D(child: grafico) : grafico;
  }
}
