import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// BottomSheet que ofrece activar el inicio de sesión biométrico.
/// Devuelve `true` si el usuario acepta, `false`/`null` si declina o lo cierra.
Future<bool?> showBiometricOfferSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const _BiometricOfferSheetContent(),
  );
}

class _BiometricOfferSheetContent extends StatelessWidget {
  const _BiometricOfferSheetContent();

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
                      colors: [scheme.primary, scheme.secondary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const PhosphorIcon(
                    PhosphorIconsRegular.fingerprint,
                    color: Colors.white,
                    size: 40,
                  ),
                )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scale(
                  begin: const Offset(0.94, 0.94),
                  end: const Offset(1.04, 1.04),
                  duration: 900.ms,
                  curve: Curves.easeInOut,
                ),
            const SizedBox(height: 20),
            Text(
                  '¿Activar inicio de sesión con huella?',
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                )
                .animate()
                .fadeIn(delay: 100.ms, duration: 280.ms)
                .moveY(begin: 8, end: 0),
            const SizedBox(height: 10),
            Text(
                  'La próxima vez podrás entrar a Panadería Ronceros solo con tu huella digital, sin escribir tu contraseña.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                )
                .animate()
                .fadeIn(delay: 160.ms, duration: 280.ms)
                .moveY(begin: 8, end: 0),
            const SizedBox(height: 24),
            SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Sí, activar'),
                  ),
                )
                .animate()
                .fadeIn(delay: 220.ms, duration: 280.ms)
                .moveY(begin: 8, end: 0),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Ahora no'),
              ),
            ).animate().fadeIn(delay: 260.ms, duration: 280.ms),
          ],
        ),
      ),
    );
  }
}
