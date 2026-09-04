import 'package:flutter/material.dart';

/// Crédito discreto del estudio — "Powered by Ronceros Labs" en bucle
/// continuo (el anillo animado en el lugar de la "O"). Compartido entre
/// el login y el splash para no duplicar el dibujo del sello en los dos
/// lados; cada pantalla decide solo cuándo y cómo entra en escena.
class CreditoDesarrollador extends StatelessWidget {
  const CreditoDesarrollador({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Powered by',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
            color: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
          ),
        ),
        const SizedBox(height: 2),
        const _SelloRonceroLabsChico(),
      ],
    );
  }
}

/// Versión chica y en bucle continuo del sello de Ronceros Labs: "R" +
/// anillo (en el lugar de la "O") + "NCEROS", con "LABS" debajo — el mismo
/// diseño "D" que se eligió, solo miniaturizado para vivir al pie de una
/// pantalla. Sin fondo ni caja propia: los colores ya están pensados para
/// leerse directo sobre un fondo claro.
class _SelloRonceroLabsChico extends StatefulWidget {
  const _SelloRonceroLabsChico();

  @override
  State<_SelloRonceroLabsChico> createState() =>
      _SelloRonceroLabsChicoState();
}

class _SelloRonceroLabsChicoState extends State<_SelloRonceroLabsChico>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _trazoAnillo;
  late final Animation<double> _destello;

  static const _texto = Color(0xFF1A1A1A);
  static const _plataOscuro = Color(0xFF48484A);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
    _trazoAnillo = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.4, curve: Curves.easeInOutCubic),
    );
    _destello = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.8), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 0.8, end: 0.0), weight: 70),
    ]).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.35, 0.65)),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const tamanoLetra = 17.0;
    const tamanoAnillo = 15.0;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  'R',
                  style: TextStyle(
                    color: _texto,
                    fontSize: tamanoLetra,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(
                  width: tamanoAnillo,
                  height: tamanoAnillo,
                  child: CustomPaint(
                    painter: _AnilloChicoPainter(
                      progreso: _trazoAnillo.value,
                      destello: _destello.value,
                    ),
                  ),
                ),
                const Text(
                  'NCEROS',
                  style: TextStyle(
                    color: _texto,
                    fontSize: tamanoLetra,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: ShaderMask(
                shaderCallback: _degradadoPlata,
                child: const Text(
                  'LABS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3.2,
                    height: 1.3,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static Shader _degradadoPlata(Rect bounds) {
    return const LinearGradient(
      colors: [_plataOscuro, Color(0xFF6B6B68)],
    ).createShader(bounds);
  }
}

class _AnilloChicoPainter extends CustomPainter {
  const _AnilloChicoPainter({required this.progreso, required this.destello});

  final double progreso;
  final double destello;

  static const _plataClaro = Color(0xFF9C9C98);
  static const _plataOscuro = Color(0xFF48484A);

  @override
  void paint(Canvas canvas, Size size) {
    final centro = size.center(Offset.zero);
    final radio = (size.shortestSide - 3) / 2;

    if (destello > 0) {
      final halo = Paint()
        ..shader = RadialGradient(
          colors: [
            _plataOscuro.withValues(alpha: destello * 0.5),
            _plataOscuro.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: centro, radius: radio + 4));
      canvas.drawCircle(centro, radio + 4, halo);
    }

    if (progreso <= 0) return;

    final trazo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        colors: [_plataClaro, _plataOscuro],
      ).createShader(Rect.fromCircle(center: centro, radius: radio));

    final rect = Rect.fromCircle(center: centro, radius: radio);
    canvas.drawArc(
      rect,
      -1.5707963267948966,
      progreso * 6.283185307179586,
      false,
      trazo,
    );
  }

  @override
  bool shouldRepaint(covariant _AnilloChicoPainter oldDelegate) {
    return oldDelegate.progreso != progreso ||
        oldDelegate.destello != destello;
  }
}
