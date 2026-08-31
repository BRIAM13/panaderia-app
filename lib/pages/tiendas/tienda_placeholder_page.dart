import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../theme/app_theme.dart';
import '../../widgets/escritorio.dart';
import '../../widgets/loading_indicator.dart';

/// Pantalla marcador de posición para una tienda ya habilitada en la
/// navegación pero cuyo contenido aún se construirá en una fase futura.
///
/// Escritorio (>= [Breakpoints.escritorio], vía [esEscritorio]): el mensaje
/// deja de flotar suelto en medio de una ventana de 1900 px y pasa a vivir
/// dentro de una tarjeta centrada con techo de ancho, con la barra superior
/// alineada a la izquierda como el resto de las pantallas de gestión. Por
/// debajo de ese ancho el árbol es exactamente el de siempre.
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

  String get _titulo => titulo ?? 'Tienda de $nombreTienda';

  String get _mensaje =>
      mensaje ??
      'Estamos preparando el catálogo y el flujo de compra. '
          'Muy pronto podrás pedir aquí.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (esEscritorio(context)) {
      return Scaffold(
        appBar: appBarGestion(
          context,
          titulo: nombreTienda,
          subtitulo: 'Módulo en construcción',
        ),
        body: Center(
          child: ContenidoCentrado(
            anchoMaximo: 560,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: TarjetaEscritorio(
                    padding: const EdgeInsets.fromLTRB(40, 44, 40, 44),
                    radio: 28,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // El ícono de la propia tienda ancla la tarjeta: sin
                        // él, en escritorio se leía como un mensaje genérico
                        // sin saber de qué tienda hablaba.
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                AppColors.primary.withValues(alpha: 0.16),
                                AppColors.secondary.withValues(alpha: 0.10),
                              ],
                            ),
                          ),
                          child: Icon(
                            icono,
                            size: 34,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 24),
                        const AppLoadingIndicator(size: 56),
                        const SizedBox(height: 26),
                        Text(
                          _titulo,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _mensaje,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: AppColors.textSecondary,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 22),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.secondary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const PhosphorIcon(
                                PhosphorIconsRegular.wrench,
                                size: 15,
                                color: AppColors.secondary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Próximamente',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6,
                                  color: AppColors.secondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                  .animate()
                  .fadeIn(duration: 350.ms)
                  .moveY(begin: 14, end: 0, curve: Curves.easeOutCubic),
            ),
          ),
        ),
      );
    }

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
                    _titulo,
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  )
                  .animate()
                  .fadeIn(delay: 150.ms, duration: 300.ms)
                  .moveY(begin: 8, end: 0),
              const SizedBox(height: 10),
              Text(
                    _mensaje,
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
