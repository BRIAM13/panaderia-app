import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

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

  /// Solo se prende en web/escritorio — en táctil no existe el evento de
  /// hover, así que el botón se ve exactamente igual que antes.
  bool _hover = false;

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
                  PhosphorIcon(widget.icono!, size: 18, color: colorContenido),
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

    // En web/escritorio hay cursor: sin esto el botón no se distingue de
    // texto plano al pasarle el mouse por encima, y no "sube" al apuntarlo.
    return MouseRegion(
      cursor: _habilitado ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) {
        if (_habilitado) setState(() => _hover = true);
      },
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTapDown: _habilitado ? _onTapDown : null,
        onTapUp: _habilitado ? _onTapUp : null,
        onTapCancel: _habilitado ? _onTapCancel : null,
        onTap: _habilitado ? widget.onPressed : null,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final t = Curves.easeOut.transform(_controller.value);
            return Transform.translate(
              offset: Offset(0, _hover && t == 0 ? -2 : 0),
              child: Transform.scale(
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
                      color: widget.relleno || !_hover
                          ? null
                          : AppColors.primary.withValues(alpha: 0.06),
                      border: widget.relleno
                          ? null
                          : Border.all(
                              color: AppColors.primary.withValues(
                                alpha: _hover ? 0.60 : 0.35,
                              ),
                              width: 1.4,
                            ),
                      boxShadow: widget.relleno
                          ? [
                              BoxShadow(
                                color: AppColors.primary.withValues(
                                  alpha: (_hover ? 0.38 : 0.28) - (0.12 * t),
                                ),
                                blurRadius: (_hover ? 22 : 16) - (8 * t),
                                offset: Offset(0, 6 - (3 * t)),
                              ),
                            ]
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: contenido,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
