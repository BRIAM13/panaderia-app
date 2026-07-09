import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Botón con inclinación/hundimiento suave al presionar (mismo lenguaje
/// táctil que [Tarjeta3D], pero para acciones primarias/secundarias) y
/// estado de carga integrado — reemplaza a los `ElevatedButton` por
/// defecto en formularios y pantallas de acción.
class PremiumButton extends StatefulWidget {
  const PremiumButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icono,
    this.cargando = false,
    this.relleno = true,
    this.expandido = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icono;

  /// Reemplaza la etiqueta por un spinner y deshabilita el toque, sin
  /// hacer que el botón desaparezca ni cambie de tamaño.
  final bool cargando;

  /// true: relleno con degradado de marca (acción primaria). false:
  /// contorno (acción secundaria, ej. "Cancelar"/"Reintentar").
  final bool relleno;

  final bool expandido;

  @override
  State<PremiumButton> createState() => _PremiumButtonState();
}

class _PremiumButtonState extends State<PremiumButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
    reverseDuration: const Duration(milliseconds: 220),
  );

  bool get _habilitado => widget.onPressed != null && !widget.cargando;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    if (_habilitado) _controller.forward();
  }

  void _onTapUp(TapUpDetails _) => _controller.reverse();
  void _onTapCancel() => _controller.reverse();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorContenido = widget.relleno ? Colors.white : AppColors.primary;

    final contenido = AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: widget.cargando
          ? SizedBox(
              key: const ValueKey('cargando'),
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: colorContenido,
              ),
            )
          : Row(
              key: const ValueKey('etiqueta'),
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icono != null) ...[
                  Icon(widget.icono, size: 18, color: colorContenido),
                  const SizedBox(width: 8),
                ],
                Text(
                  widget.label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colorContenido,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
    );

    return GestureDetector(
      onTapDown: _habilitado ? _onTapDown : null,
      onTapUp: _habilitado ? _onTapUp : null,
      onTapCancel: _habilitado ? _onTapCancel : null,
      onTap: _habilitado ? widget.onPressed : null,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = Curves.easeOut.transform(_controller.value);
          return Transform.scale(
            scale: 1 - (0.035 * t),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: widget.onPressed == null && !widget.cargando
                  ? 0.5
                  : 1,
              child: Container(
                width: widget.expandido ? double.infinity : null,
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 24,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: widget.relleno
                      ? const LinearGradient(
                          colors: [AppColors.primary, AppColors.secondary],
                        )
                      : null,
                  border: widget.relleno
                      ? null
                      : Border.all(
                          color: AppColors.primary.withValues(alpha: 0.35),
                          width: 1.4,
                        ),
                  boxShadow: widget.relleno
                      ? [
                          BoxShadow(
                            color: AppColors.primary.withValues(
                              alpha: 0.28 - (0.12 * t),
                            ),
                            blurRadius: 16 - (8 * t),
                            offset: Offset(0, 6 - (3 * t)),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: contenido,
              ),
            ),
          );
        },
      ),
    );
  }
}
