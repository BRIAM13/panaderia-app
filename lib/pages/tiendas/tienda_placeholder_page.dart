import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../widgets/loading_indicator.dart';

/// Pantalla marcador de posición para una tienda ya habilitada en la
/// navegación pero cuyo contenido aún se construirá en una fase futura.
class TiendaPlaceholderPage extends StatelessWidget {
  const TiendaPlaceholderPage({
    super.key,
    required this.nombreTienda,
    required this.icono,
    this.titulo,
    this.mensaje,
  });

  final String nombreTienda;
  final IconData icono;
  final String? titulo;
  final String? mensaje;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(nombreTienda)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppLoadingIndicator(
                size: 72,
              ).animate().fadeIn(duration: 400.ms),
              const SizedBox(height: 28),
              Text(
                    titulo ?? 'Tienda de $nombreTienda',
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  )
                  .animate()
                  .fadeIn(delay: 150.ms, duration: 300.ms)
                  .moveY(begin: 8, end: 0),
              const SizedBox(height: 10),
              Text(
                    mensaje ??
                        'Estamos preparando el catálogo y el flujo de compra. '
                            'Muy pronto podrás pedir aquí.',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  )
                  .animate()
                  .fadeIn(delay: 220.ms, duration: 300.ms)
                  .moveY(begin: 8, end: 0),
            ],
          ),
        ),
      ),
    );
  }
}
