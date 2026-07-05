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
          // Nota: aquí NO se debe aplicar ningún Transform en 3D (rotateX/Y,
          // perspectiva) — las páginas pueden contener vistas nativas de
          // Android incrustadas (el AdWidget de google_mobile_ads es una de
          // ellas), que no se recomponen bien bajo una rotación 3D de sus
          // ancestros: el anuncio terminaba apareciendo desubicado y por
          // encima de todo lo demás tras la transición. Un slide+fade en 2D
          // sí es seguro.
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.08),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      );
}

/// Atajo para navegar usando [SlideUpFadeRoute].
Future<T?> pushSlideUpFade<T>(BuildContext context, WidgetBuilder builder) {
  return Navigator.of(context).push<T>(SlideUpFadeRoute<T>(builder: builder));
}
