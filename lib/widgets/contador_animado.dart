import 'package:flutter/material.dart';

/// Cuenta hacia arriba desde 0 hasta [valor] con una animación suave — se
/// usa en cualquier tarjeta de estadística/dinero que quiera sentirse viva
/// al aparecer, en vez de mostrar el número de golpe.
class ContadorAnimado extends StatelessWidget {
  const ContadorAnimado({
    super.key,
    required this.valor,
    required this.formatear,
    required this.estilo,
  });

  final double valor;
  final String Function(double) formatear;
  final TextStyle? estilo;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: valor),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, valorActual, _) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(formatear(valorActual), style: estilo, maxLines: 1),
      ),
    );
  }
}
