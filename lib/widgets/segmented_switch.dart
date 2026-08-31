import 'package:flutter/material.dart';

/// Selector tipo "sliding switch" entre 2+ opciones, con la píldora de
/// fondo deslizándose de forma fluida hacia la opción elegida.
class SegmentedSwitch extends StatelessWidget {
  const SegmentedSwitch({
    super.key,
    required this.opciones,
    required this.indiceSeleccionado,
    required this.onChanged,
  });

  final List<String> opciones;
  final int indiceSeleccionado;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final anchoOpcion = constraints.maxWidth / opciones.length;

        return Container(
          height: 48,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                left: anchoOpcion * indiceSeleccionado,
                top: 0,
                bottom: 0,
                width: anchoOpcion,
                child: Container(
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [scheme.primary, scheme.secondary],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
              Row(
                children: List.generate(opciones.length, (index) {
                  final seleccionado = index == indiceSeleccionado;
                  return Expanded(
                    // En web el cursor tiene que decir "esto se hace clic";
                    // sin esto el selector parece una etiqueta decorativa.
                    child: MouseRegion(
                      cursor: seleccionado
                          ? SystemMouseCursors.basic
                          : SystemMouseCursors.click,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(index),
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: seleccionado
                                  ? Colors.white
                                  : scheme.onSurface.withValues(alpha: 0.6),
                            ),
                            child: Text(opciones[index]),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }
}
