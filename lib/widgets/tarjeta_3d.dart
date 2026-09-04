import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Envoltura reutilizable que le da profundidad 3D a cualquier tarjeta:
/// al presionar, se inclina levemente en perspectiva (como si se hundiera
/// en la pantalla) y la sombra se acerca; al soltar, vuelve a su lugar con
/// un rebote suave. Se usa en todas las tarjetas táctiles de la app
/// (pedidos, clientes, tiendas, trabajadores, deudas, métodos de pago)
/// para que se sientan consistentemente "vivas" al tocarlas.
class Tarjeta3D extends StatefulWidget {
  const Tarjeta3D({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius = 20,
    this.profundidad = 0.0016,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double borderRadius;

  /// Qué tan pronunciada es la inclinación al presionar (valores muy
  /// altos se ven irreales; 0.0012–0.002 es el rango que funciona bien).
  final double profundidad;

  @override
  State<Tarjeta3D> createState() => _Tarjeta3DState();
}

class _Tarjeta3DState extends State<Tarjeta3D>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    reverseDuration: const Duration(milliseconds: 420),
  );

  // Signo aleatorio-pero-fijo del tilt por tarjeta, para que en una grilla
  // no todas se inclinen exactamente igual (se ve más orgánico).
  late final double _signoX = (hashCode.isEven) ? 1 : -1;
  late final double _signoY = (hashCode.isOdd) ? 1 : -1;

  // El tilt táctil no existe en escritorio (no hay "presionar y soltar"
  // con el mouse igual que con el dedo): sin hover, una grilla de tarjetas
  // clicables en web se ve completamente inerte hasta que ya hiciste clic.
  bool _hover = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) => _controller.forward();
  void _onTapUp(TapUpDetails _) => _controller.reverse();
  void _onTapCancel() => _controller.reverse();

  @override
  Widget build(BuildContext context) {
    final clicable = widget.onTap != null;

    return MouseRegion(
      cursor: clicable ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) {
        if (clicable) setState(() => _hover = true);
      },
      onExit: (_) {
        if (clicable) setState(() => _hover = false);
      },
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: widget.onTap == null ? null : _onTapDown,
        onTapUp: widget.onTap == null ? null : _onTapUp,
        onTapCancel: widget.onTap == null ? null : _onTapCancel,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final t = Curves.easeOut.transform(_controller.value);
            // El hover levanta la tarjeta; presionarla la vuelve a hundir,
            // así que el desplazamiento se apaga a medida que entra el tilt.
            final alza = _hover ? -3.0 * (1 - t) : 0.0;
            final matriz = Matrix4.identity()
              ..setEntry(3, 2, widget.profundidad)
              ..translateByDouble(0, alza, 0, 1)
              ..rotateX(0.05 * t * _signoY)
              ..rotateY(0.05 * t * _signoX)
              ..scaleByDouble(1 - (0.02 * t), 1 - (0.02 * t), 1, 1);
            return Transform(
              alignment: Alignment.center,
              transform: matriz,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                  // Reposo más marcado (16% → 24%, blur 18 → 24, offset 8 →
                  // 11) — mismo criterio que TarjetaEscritorio, para que el
                  // efecto de profundidad sea consistente en toda la app,
                  // no solo en las tarjetas KPI del dashboard.
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: (_hover ? 0.30 : 0.24) + (0.10 * t),
                      ),
                      blurRadius: (_hover ? 32 : 24) - (10 * t),
                      offset: Offset(0, (_hover ? 15 : 11) - (6 * t)),
                    ),
                  ],
                ),
                child: child,
              ),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Rotación de entrada en 3D (como si la tarjeta cayera desde de canto)
/// para usar junto con flutter_animate en listas/grillas escalonadas.
/// Se aplica ANTES de las animaciones de flutter_animate de cada pantalla:
/// `Tarjeta3D(child: ...).animate().fadeIn()...` ya incluye el tilt táctil;
/// esta función es para el efecto de aparición inicial con .custom().
double calcularAnguloEntrada3D(double progreso) {
  return (1 - progreso) * (math.pi / 10);
}
