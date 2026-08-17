import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../theme/app_theme.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/premium_button.dart';
import 'deudas_horneados_page.dart';
import 'nuevo_pedido_horneados_page.dart';
import 'pedidos_horneados_page.dart';

/// Pantalla principal de gestión de Horneados — punto de entrada mientras
/// se construye el resto del apartado (medios de pago, ajuste de costos,
/// etc., igual que Hamburguesas).
class HorneadosHomePage extends StatelessWidget {
  const HorneadosHomePage({super.key});

  @override
  Widget build(BuildContext context) {
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
                Icon(
                  Icons.bakery_dining_rounded,
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
                  icono: Icons.receipt_long_rounded,
                  onPressed: () => pushSlideUpFade(
                    context,
                    (context) => const PedidosHorneadosPage(),
                  ),
                ).animate().fadeIn(delay: 280.ms, duration: 300.ms),
                const SizedBox(height: 12),
                PremiumButton(
                  label: 'Registrar pedido',
                  icono: Icons.add_shopping_cart_rounded,
                  relleno: false,
                  onPressed: () => pushSlideUpFade(
                    context,
                    (context) => const NuevoPedidoHorneadosPage(),
                  ),
                ).animate().fadeIn(delay: 330.ms, duration: 300.ms),
                const SizedBox(height: 12),
                PremiumButton(
                  label: 'Ver deudas',
                  icono: Icons.account_balance_wallet_rounded,
                  relleno: false,
                  onPressed: () => pushSlideUpFade(
                    context,
                    (context) => const DeudasHorneadosPage(),
                  ),
                ).animate().fadeIn(delay: 360.ms, duration: 300.ms),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
