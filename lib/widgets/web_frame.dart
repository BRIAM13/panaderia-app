import 'package:flutter/material.dart';

/// La app se diseñó mobile-first — en una ventana de escritorio ancha, sin
/// esto, cada pantalla se estira horizontalmente y se ve incómoda (botones
/// larguísimos, texto perdido en el medio de la pantalla).
///
/// Pantallas con su propio layout adaptativo (ver `HomePage`) no necesitan
/// esto — para el resto, que todavía no tiene un rediseño propio de
/// escritorio, este es solo un respaldo neutral: centra el contenido en un
/// ancho razonable de panel web, sin simular un marco de celular ni un
/// fondo de color alrededor.
///
/// Por debajo del punto de quiebre (celular real, o ventana angosta) no
/// hace nada — se comporta exactamente como antes.
class WebFrame extends StatelessWidget {
  const WebFrame({super.key, required this.child});

  final Widget child;

  static const _anchoMaximo = 900.0;
  static const _puntoDeQuiebre = 700.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _puntoDeQuiebre) return child;

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _anchoMaximo),
            child: child,
          ),
        );
      },
    );
  }
}
