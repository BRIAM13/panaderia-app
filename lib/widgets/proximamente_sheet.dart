import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Muestra el BottomSheet animado que informa que una tienda todavía
/// no está disponible.
Future<void> showProximamenteSheet(
  BuildContext context, {
  required String nombreTienda,
  required IconData icono,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) =>
        _ProximamenteSheetContent(nombreTienda: nombreTienda, icono: icono),
  );
}

class _ProximamenteSheetContent extends StatelessWidget {
  const _ProximamenteSheetContent({
    required this.nombreTienda,
    required this.icono,
  });

  final String nombreTienda;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 24),
            Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [scheme.secondary, scheme.primary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Icon(icono, color: Colors.white, size: 36),
                )
                .animate()
                .scale(
                  begin: const Offset(0.6, 0.6),
                  end: const Offset(1, 1),
                  duration: 420.ms,
                  curve: Curves.easeOutBack,
                )
                .fadeIn(duration: 250.ms),
            const SizedBox(height: 20),
            Text(
                  nombreTienda,
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                )
                .animate()
                .fadeIn(delay: 120.ms, duration: 300.ms)
                .moveY(begin: 8, end: 0),
            const SizedBox(height: 8),
            Chip(
                  avatar: Icon(
                    Icons.schedule_rounded,
                    size: 16,
                    color: scheme.primary,
                  ),
                  label: const Text('PRÓXIMAMENTE'),
                )
                .animate()
                .fadeIn(delay: 180.ms, duration: 300.ms)
                .moveY(begin: 8, end: 0),
            const SizedBox(height: 16),
            Text(
                  'Estamos preparando esta tienda con mucho cariño. '
                  'Se habilitará en una futura actualización de la app.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                )
                .animate()
                .fadeIn(delay: 240.ms, duration: 300.ms)
                .moveY(begin: 8, end: 0),
            const SizedBox(height: 24),
            SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Entendido'),
                  ),
                )
                .animate()
                .fadeIn(delay: 300.ms, duration: 300.ms)
                .moveY(begin: 8, end: 0),
          ],
        ),
      ),
    );
  }
}
