import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../theme/app_theme.dart';
import 'premium_button.dart';

/// Estado de error ilustrado y animado — reemplaza el patrón repetido de
/// `Text(_error!) + OutlinedButton('Reintentar')` sin ícono ni animación
/// que había en casi toda pantalla con carga de datos.
class EstadoError extends StatelessWidget {
  const EstadoError({
    super.key,
    required this.mensaje,
    required this.onReintentar,
  });

  final String mensaje;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        AppColors.error.withValues(alpha: 0.16),
                        AppColors.error.withValues(alpha: 0.06),
                      ],
                    ),
                  ),
                  child: const PhosphorIcon(
                    PhosphorIconsDuotone.warningCircle,
                    size: 38,
                    color: AppColors.error,
                  ),
                )
                .animate()
                .fadeIn(duration: 350.ms)
                .scale(
                  begin: const Offset(0.85, 0.85),
                  end: const Offset(1, 1),
                ),
            const SizedBox(height: 16),
            // Topado para que en escritorio el mensaje no se estire en una
            // sola línea de borde a borde de la ventana.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Text(
                mensaje,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(height: 1.45),
              ),
            ).animate().fadeIn(delay: 100.ms, duration: 300.ms),
            const SizedBox(height: 18),
            SizedBox(
              width: 180,
              child: PremiumButton(
                label: 'Reintentar',
                icono: PhosphorIconsBold.arrowClockwise,
                relleno: false,
                onPressed: onReintentar,
              ),
            ).animate().fadeIn(delay: 160.ms, duration: 300.ms),
          ],
        ),
      ),
    );
  }
}
