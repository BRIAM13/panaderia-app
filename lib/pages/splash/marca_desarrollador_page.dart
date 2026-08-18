import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../widgets/page_transitions.dart';
import 'splash_page.dart';

/// Paleta del sello de Ronceros Labs — deliberadamente independiente de la
/// paleta de Panadería Ronceros (ver AppColors): este splash se reusa tal
/// cual en cualquier otra app del estudio, así que no puede depender de los
/// colores de un solo cliente/proyecto.
class _ColoresLabs {
  _ColoresLabs._();

  static const Color fondo = Color(0xFF141414);
  static const Color texto = Color(0xFFF4F4F2);
  static const Color plataClaro = Color(0xFFE4E4E2);
  static const Color plataOscuro = Color(0xFF8C8C88);
}

/// Primera pantalla que ve cualquiera al abrir la app: un instante de marca
/// del estudio que la desarrolló ("Ronceros Labs"), antes de pasar al splash
/// real de Panadería Ronceros. Se muestra una sola vez por arranque en frío,
/// nunca al volver de segundo plano (esta página no vuelve a montarse porque
/// `SplashPage` reemplaza la ruta en vez de apilarse encima).
class MarcaDesarrolladorPage extends StatefulWidget {
  const MarcaDesarrolladorPage({super.key});

  @override
  State<MarcaDesarrolladorPage> createState() =>
      _MarcaDesarrolladorPageState();
}

class _MarcaDesarrolladorPageState extends State<MarcaDesarrolladorPage> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushReplacement(FadeRoute(builder: (_) => const SplashPage()));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ColoresLabs.fondo,
      body: Center(
        child: const _SelloRonceroLabs().animate().fadeOut(
          delay: 1150.ms,
          duration: 350.ms,
        ),
      ),
    );
  }
}

/// El sello animado en sí — "R" + anillo que se dibuja como un circuito
/// encendiéndose + el resto del nombre. Es su propio widget (no solo un
/// build() en la página) para poder aislar el AnimationController del
/// anillo del resto de animaciones de texto, que usan flutter_animate.
class _SelloRonceroLabs extends StatefulWidget {
  const _SelloRonceroLabs();

  @override
  State<_SelloRonceroLabs> createState() => _SelloRonceroLabsState();
}

class _SelloRonceroLabsState extends State<_SelloRonceroLabs>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _trazoAnillo;
  late final Animation<double> _destello;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    );
    // El anillo se dibuja entre 280ms y 780ms de la línea de tiempo total.
    _trazoAnillo = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.27, 0.74, curve: Curves.easeInOutCubic),
    );
    // El destello aparece justo cuando el anillo termina de dibujarse y se
    // apaga enseguida — el "encendido" del circuito.
    _destello = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.9), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 0.9, end: 0.0), weight: 60),
    ]).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.71, 1.0, curve: Curves.easeOut),
      ),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const tamanoAnillo = 92.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _Letra('R', const Duration(milliseconds: 0)),
            SizedBox(
              width: tamanoAnillo,
              height: tamanoAnillo,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _AnilloCircuitoPainter(
                      progreso: _trazoAnillo.value,
                      destello: _destello.value,
                    ),
                  );
                },
              ),
            ),
            _Letra('NCEROS', const Duration(milliseconds: 650)),
          ],
        ),
        const SizedBox(height: 14),
        _Labs(const Duration(milliseconds: 950)),
      ],
    );
  }
}

class _Letra extends StatelessWidget {
  const _Letra(this.texto, this.retraso);

  final String texto;
  final Duration retraso;

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: const TextStyle(
        color: _ColoresLabs.texto,
        fontSize: 56,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
      ),
    ).animate(delay: retraso).fadeIn(duration: 300.ms);
  }
}

class _Labs extends StatelessWidget {
  const _Labs(this.retraso);

  final Duration retraso;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [_ColoresLabs.plataClaro, _ColoresLabs.plataOscuro],
          ).createShader(bounds),
          child: const Text(
            'LABS',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: 11,
            ),
          ),
        )
        .animate(delay: retraso)
        .fadeIn(duration: 350.ms)
        .moveY(begin: 8, end: 0, curve: Curves.easeOut);
  }
}

/// Dibuja el anillo del sello: un arco que se completa en sentido horario
/// desde arriba (el "trazo del circuito"), con un halo que destella una vez
/// al terminar de dibujarse — el "encendido".
class _AnilloCircuitoPainter extends CustomPainter {
  const _AnilloCircuitoPainter({required this.progreso, required this.destello});

  final double progreso;
  final double destello;

  @override
  void paint(Canvas canvas, Size size) {
    final centro = size.center(Offset.zero);
    final radio = (size.shortestSide - 9) / 2;

    if (destello > 0) {
      final halo = Paint()
        ..shader = RadialGradient(
          colors: [
            _ColoresLabs.texto.withValues(alpha: destello),
            _ColoresLabs.texto.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: centro, radius: radio + 10));
      canvas.drawCircle(centro, radio + 10, halo);
    }

    if (progreso <= 0) return;

    final trazo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        colors: const [_ColoresLabs.plataClaro, _ColoresLabs.plataOscuro],
      ).createShader(Rect.fromCircle(center: centro, radius: radio));

    final rect = Rect.fromCircle(center: centro, radius: radio);
    canvas.drawArc(rect, -math.pi / 2, progreso * 2 * math.pi, false, trazo);
  }

  @override
  bool shouldRepaint(covariant _AnilloCircuitoPainter oldDelegate) {
    return oldDelegate.progreso != progreso || oldDelegate.destello != destello;
  }
}
