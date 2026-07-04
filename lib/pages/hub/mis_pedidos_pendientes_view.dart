import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../services/api_client.dart';
import '../../services/notificaciones_service.dart';
import '../../services/pedidos_service.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/pedidos_secciones.dart';
import 'hacer_pedido_page.dart';

/// Contenido de "Mis pedidos pendientes" (rol CLIENTE): sus propios pedidos
/// agrupados en Atrasados / Hoy / Próximos / Sin fecha — mismo lenguaje
/// visual que el dashboard de personal, pero sin nombre de cliente en cada
/// tarjeta (ya sabe que son suyos). Es la pantalla principal de la vista
/// cliente en el Hub, y también se puede abrir como página completa desde
/// el drawer. El estado es público (no privado) a propósito: así el FAB
/// "Hacer pedido" de HomePage puede pedirle recargar tras registrar uno,
/// sin necesidad de levantar todo el estado al padre.
class MisPedidosPendientesView extends StatefulWidget {
  const MisPedidosPendientesView({super.key});

  @override
  State<MisPedidosPendientesView> createState() =>
      MisPedidosPendientesViewState();
}

class MisPedidosPendientesViewState extends State<MisPedidosPendientesView> {
  final _pedidosService = PedidosService();
  StreamSubscription<void>? _suscripcionPush;

  List<Pedido> _pedidos = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
    // Recarga sola apenas llega una notificación de cambio de pedido
    // (aprobado, rechazado, entregado, etc.) — antes había que deslizar a
    // mano para ver el cambio recién notificado.
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
      final pedidos = await _pedidosService.misPedidos();
      if (mounted) setState(() => _pedidos = pedidos);
    } on ApiException catch (e) {
      if (!silencioso) setState(() => _error = e.mensaje);
    } catch (_) {
      if (!silencioso) {
        setState(() => _error = 'No se pudieron cargar tus pedidos.');
      }
    } finally {
      if (mounted && !silencioso) setState(() => _cargando = false);
    }
  }

  /// Llamado desde afuera (ej. tras registrar un pedido nuevo) para
  /// refrescar la lista sin reconstruir todo el widget.
  Future<void> recargar() => _cargar();

  Future<void> _cancelar(Pedido pedido) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar pedido'),
        content: Text(
          '¿Seguro que quieres cancelar el pedido #${pedido.idPedido}? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No, mantenerlo'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await _pedidosService.cancelarMiPedido(pedido.idPedido);
      NotificacionesService.avisarCambioPedido();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pedido #${pedido.idPedido} cancelado.')),
      );
      _cargar();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.mensaje)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo cancelar el pedido.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_cargando) {
      return const Center(child: AppLoadingIndicator());
    }

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

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
        children: [
          Text(
            'Tus pedidos',
            style: theme.textTheme.titleLarge,
          ).animate().fadeIn(duration: 300.ms).moveY(begin: 6, end: 0),
          const SizedBox(height: 4),
          Text(
                'Así va tu historial con la panadería.',
                style: theme.textTheme.bodyMedium,
              )
              .animate()
              .fadeIn(delay: 60.ms, duration: 300.ms)
              .moveY(begin: 6, end: 0),
          const SizedBox(height: 20),
          if (_pedidos.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 48,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Aún no tienes pedidos registrados',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            ListaPedidosPorSeccion(
              pedidos: _pedidos,
              mostrarNombreCliente: false,
              onCancelar: _cancelar,
            ),
        ],
      ),
    );
  }
}

/// Envoltorio con Scaffold/AppBar/FAB propios, para abrir "Mis pedidos" como
/// página independiente (ej. desde el drawer) fuera del Hub.
class MisPedidosPendientesPage extends StatefulWidget {
  const MisPedidosPendientesPage({super.key});

  @override
  State<MisPedidosPendientesPage> createState() =>
      _MisPedidosPendientesPageState();
}

class _MisPedidosPendientesPageState extends State<MisPedidosPendientesPage> {
  final _contenidoKey = GlobalKey<MisPedidosPendientesViewState>();

  Future<void> _hacerPedido() async {
    final registrado = await pushSlideUpFade<bool>(
      context,
      (_) => const HacerPedidoPage(),
    );
    if (registrado == true) _contenidoKey.currentState?.recargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mis pedidos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _hacerPedido,
        icon: const Icon(Icons.add_shopping_cart_rounded),
        label: const Text('Hacer pedido'),
      ),
      body: SafeArea(child: MisPedidosPendientesView(key: _contenidoKey)),
    );
  }
}
