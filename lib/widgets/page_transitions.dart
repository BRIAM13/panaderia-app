import 'package:flutter/material.dart';

/// Ruta con transición de deslizamiento hacia arriba + desvanecimiento
/// simultáneo, usada para navegar entre las tiendas de la Super App.
class SlideUpFadeRoute<T> extends PageRouteBuilder<T> {
  SlideUpFadeRoute({required WidgetBuilder builder, super.settings})
    : super(
        transitionDuration: const Duration(milliseconds: 450),
        reverseTransitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.08),
                end: Offset.zero,
              ).animate(curved),
              child: AnimatedBuilder(
                animation: curved,
                child: child,
                // La página nueva "se endereza" desde una leve inclinación
                // en perspectiva (como si viniera desde el fondo de la
                // pantalla) en vez de aparecer plana — el toque 3D del
                // deslizamiento hacia arriba.
                builder: (context, child) {
                  final t = curved.value;
                  final matriz = Matrix4.identity()
                    ..setEntry(3, 2, 0.0012)
                    ..rotateX((1 - t) * -0.12);
                  return Transform(
                    alignment: Alignment.center,
                    transform: matriz,
                    child: child,
                  );
                },
              ),
            ),
          );
        },
      );
}

/// Atajo para navegar usando [SlideUpFadeRoute].
Future<T?> pushSlideUpFade<T>(BuildContext context, WidgetBuilder builder) {
  return Navigator.of(context).push<T>(SlideUpFadeRoute<T>(builder: builder));
}
