import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../theme/app_theme.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/premium_button.dart';
import 'deudas_horneados_page.dart';
import '../../widgets/escritorio.dart';
import 'nuevo_pedido_horneados_page.dart';
import 'pedidos_horneados_page.dart';

/// Pantalla principal de gestión de Horneados — punto de entrada mientras
/// se construye el resto del apartado (medios de pago, ajuste de costos,
/// etc., igual que Hamburguesas).
///
/// En escritorio (>= [esEscritorio]) deja de ser una columna angosta de
/// botones apilados: pasa a un encabezado con el ícono grande a la izquierda
/// y una grilla de tarjetas de acción con hover. En móvil/tablet el árbol es
/// el de siempre.
class HorneadosHomePage extends StatelessWidget {
  const HorneadosHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    if (esEscritorio(context)) return _construirEscritorio(context);
    return _construirMovil(context);
  }

  void _irAPedidos(BuildContext context) =>
      pushSlideUpFade(context, (context) => const PedidosHorneadosPage());

  void _irANuevoPedido(BuildContext context) =>
      pushSlideUpFade(context, (context) => const NuevoPedidoHorneadosPage());

  void _irADeudas(BuildContext context) =>
      pushSlideUpFade(context, (context) => const DeudasHorneadosPage());

  // ---------------------------------------------------------------- móvil

  Widget _construirMovil(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Horneados')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PhosphorIcon(
                  PhosphorIconsDuotone.bread,
                  size: 72,
                  color: AppColors.primary,
                ).animate().fadeIn(duration: 400.ms),
                const SizedBox(height: 28),
                Text(
                      'Gestión de Horneados',
                      style: theme.textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    )
                    .animate()
                    .fadeIn(delay: 150.ms, duration: 300.ms)
                    .moveY(begin: 8, end: 0),
                const SizedBox(height: 10),
                Text(
                      'Registra pedidos de carnes horneadas con su presentación, '
                      'aderezo opcional y precio.',
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    )
                    .animate()
                    .fadeIn(delay: 220.ms, duration: 300.ms)
                    .moveY(begin: 8, end: 0),
                const SizedBox(height: 28),
                PremiumButton(
                  label: 'Ver pedidos',
                  icono: PhosphorIconsBold.receipt,
                  onPressed: () => _irAPedidos(context),
                ).animate().fadeIn(delay: 280.ms, duration: 300.ms),
                const SizedBox(height: 12),
                PremiumButton(
                  label: 'Registrar pedido',
                  icono: PhosphorIconsBold.shoppingCartSimple,
                  relleno: false,
                  onPressed: () => _irANuevoPedido(context),
                ).animate().fadeIn(delay: 330.ms, duration: 300.ms),
                const SizedBox(height: 12),
                PremiumButton(
                  label: 'Ver deudas',
                  icono: PhosphorIconsBold.wallet,
                  relleno: false,
                  onPressed: () => _irADeudas(context),
                ).animate().fadeIn(delay: 360.ms, duration: 300.ms),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------- escritorio

  Widget _construirEscritorio(BuildContext context) {
    final acciones = <_AccionHorneados>[
      _AccionHorneados(
        icono: PhosphorIconsDuotone.receipt,
        titulo: 'Ver pedidos',
        descripcion:
            'Atrasados, de hoy y próximos, con las acciones de entrega y '
            'cancelación a mano.',
        color: AppColors.primary,
        onTap: () => _irAPedidos(context),
      ),
      _AccionHorneados(
        icono: PhosphorIconsDuotone.shoppingCartSimple,
        titulo: 'Registrar pedido',
        descripcion:
            'Carne, presentación, aderezo opcional y total calculado en vivo.',
        color: AppColors.secondary,
        onTap: () => _irANuevoPedido(context),
      ),
      _AccionHorneados(
        icono: PhosphorIconsDuotone.wallet,
        titulo: 'Ver deudas',
        descripcion:
            'Pedidos ya entregados que quedaron por cobrar, agrupados por '
            'cliente.',
        color: const Color(0xFFC62828),
        onTap: () => _irADeudas(context),
      ),
    ];

    return Scaffold(
      appBar: appBarGestion(context, titulo: 'Horneados'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 48),
          child: ContenidoCentrado(
            anchoMaximo: 1120,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const EncabezadoEscritorio(
                      icono: PhosphorIconsDuotone.bread,
                      titulo: 'Gestión de Horneados',
                      subtitulo:
                          'Registra pedidos de carnes horneadas con su '
                          'presentación, aderezo opcional y precio.',
                    )
                    .animate()
                    .fadeIn(duration: 350.ms)
                    .moveY(begin: 10, end: 0),
                const SizedBox(height: 32),
                LayoutBuilder(
                  builder: (context, restricciones) {
                    final columnas = columnasGrilla(
                      restricciones.maxWidth,
                      maximo: 3,
                      minimo: 320,
                    );
                    final ancho = anchoColumna(
                      restricciones.maxWidth,
                      columnas,
                    );
                    return Wrap(
                      spacing: 20,
                      runSpacing: 20,
                      children: acciones
                          .asMap()
                          .entries
                          .map(
                            (entry) => SizedBox(
                              width: ancho,
                              child:
                                  _TarjetaAccionHorneados(
                                        accion: entry.value,
                                      )
                                      .animate(delay: (90 * entry.key).ms)
                                      .fadeIn(duration: 300.ms)
                                      .moveY(begin: 12, end: 0),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccionHorneados {
  const _AccionHorneados({
    required this.icono,
    required this.titulo,
    required this.descripcion,
    required this.color,
    required this.onTap,
  });

  final IconData icono;
  final String titulo;
  final String descripcion;
  final Color color;
  final VoidCallback onTap;
}

/// Tarjeta grande de acción del hub de escritorio — reemplaza a los
/// `PremiumButton` apilados cuando hay ancho de sobra.
class _TarjetaAccionHorneados extends StatelessWidget {
  const _TarjetaAccionHorneados({required this.accion});

  final _AccionHorneados accion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TarjetaEscritorio(
      onTap: accion.onTap,
      acento: accion.color,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ChipIcono(
            icono: accion.icono,
            tamano: 54,
            tamanoIcono: 26,
            color: accion.color,
          ),
          const SizedBox(height: 16),
          Text(
            accion.titulo,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(accion.descripcion, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                'Abrir',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: accion.color,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              PhosphorIcon(
                PhosphorIconsBold.arrowRight,
                size: 14,
                color: accion.color,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
