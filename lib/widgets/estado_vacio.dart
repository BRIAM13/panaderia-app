import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/app_theme.dart';

/// Estado vacío ilustrado y animado, genérico para cualquier lista sin
/// datos — círculo con degradado de marca + ícono, título y subtítulo
/// opcional, todo con entrada escalonada. Si se pasa [onRefrescar], el
/// contenido queda dentro de un [RefreshIndicator] que sigue funcionando
/// aunque no haya nada que mostrar.
class EstadoVacio extends StatelessWidget {
  const EstadoVacio({
    super.key,
    required this.icono,
    required this.titulo,
    this.subtitulo,
    this.onRefrescar,
  });

  final IconData icono;
  final String titulo;
  final String? subtitulo;
  final Future<void> Function()? onRefrescar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final contenido = Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.18),
                      AppColors.secondary.withValues(alpha: 0.10),
                    ],
                  ),
                ),
                child: Icon(icono, size: 40, color: AppColors.primary),
              )
              .animate()
              .fadeIn(duration: 350.ms)
              .scale(begin: const Offset(0.85, 0.85), end: const Offset(1, 1)),
          const SizedBox(height: 16),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ).animate().fadeIn(delay: 100.ms, duration: 300.ms),
          if (subtitulo != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitulo!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ).animate().fadeIn(delay: 140.ms, duration: 300.ms),
          ],
        ],
      ),
    );

    final refrescar = onRefrescar;
    if (refrescar == null) return Center(child: contenido);

    return RefreshIndicator(
      onRefresh: refrescar,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: contenido),
          ),
        ),
      ),
    );
  }
}
