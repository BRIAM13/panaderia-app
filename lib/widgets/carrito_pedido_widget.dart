import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../theme/app_theme.dart';

/// Una línea ya agregada al carrito, en términos de lo que se muestra —
/// no del DTO que se enviará al backend. Las tres pantallas de creación
/// (personal, autoservicio del cliente y Horneados) arman esto a partir de
/// sus propios modelos, que no tienen los mismos campos entre sí.
class LineaCarrito {
  const LineaCarrito({
    required this.titulo,
    this.subtitulo,
    required this.cantidad,
    required this.precioUnitario,
    required this.subtotal,
    this.etiquetaUnidad = 'unidades',
  });

  /// "Pan francés", o "Pollo · Entero" en Horneados (donde el producto es
  /// siempre el mismo y lo que distingue la línea son sus atributos).
  final String titulo;

  /// Segunda línea opcional: aderezo, notas de la línea, etc.
  final String? subtitulo;

  final int cantidad;
  final double precioUnitario;
  final double subtotal;

  /// 'unidades' | 'paquetes' — solo para el texto "50 unidades × S/ 0.35".
  final String etiquetaUnidad;
}

/// Lista de las líneas ya agregadas a un pedido, con su total. Se muestra
/// entre el formulario de "arma la línea actual" y el botón de confirmar.
///
/// Cuando el carrito está vacío muestra un estado guía en vez de
/// desaparecer: sin él, la pantalla no explica que hay que agregar
/// productos antes de poder confirmar.
class CarritoPedido extends StatelessWidget {
  const CarritoPedido({
    super.key,
    required this.lineas,
    required this.onEliminar,
    this.titulo = 'Productos del pedido',
    this.mensajeVacio = 'Todavía no agregaste ningún producto. Completa los datos de arriba y toca "Agregar al pedido".',
    this.habilitado = true,
  });

  final List<LineaCarrito> lineas;

  /// Quita la línea en esa posición. La pantalla es la dueña de la lista.
  final ValueChanged<int> onEliminar;

  final String titulo;
  final String mensajeVacio;

  /// false mientras se está enviando el pedido: evita que alguien borre una
  /// línea justo cuando ya se está registrando.
  final bool habilitado;

  double get _total => lineas.fold<double>(0, (acc, l) => acc + l.subtotal);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (lineas.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.surfaceMuted,
            width: 1.4,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PhosphorIcon(
              PhosphorIconsRegular.shoppingCart,
              size: 22,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(mensajeVacio, style: theme.textTheme.bodyMedium),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surfaceMuted, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const PhosphorIcon(
                PhosphorIconsRegular.shoppingCart,
                size: 20,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(titulo, style: theme.textTheme.titleMedium)),
              _ChipContador(cantidad: lineas.length),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < lineas.length; i++) ...[
            if (i > 0) const Divider(height: 18, color: AppColors.surfaceMuted),
            _FilaLinea(
              linea: lineas[i],
              onEliminar: habilitado ? () => onEliminar(i) : null,
            ),
          ],
          const Divider(height: 22, color: AppColors.surfaceMuted),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total del pedido', style: theme.textTheme.titleMedium),
              Text(
                    'S/ ${_total.toStringAsFixed(2)}',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  )
                  .animate(target: 1)
                  .scaleXY(
                    begin: 0.92,
                    end: 1,
                    duration: 200.ms,
                    curve: Curves.easeOut,
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

/// El número de productos distintos que ya tiene el carrito.
class _ChipContador extends StatelessWidget {
  const _ChipContador({required this.cantidad});

  final int cantidad;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        cantidad == 1 ? '1 producto' : '$cantidad productos',
        style: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _FilaLinea extends StatelessWidget {
  const _FilaLinea({required this.linea, required this.onEliminar});

  final LineaCarrito linea;

  /// null deshabilita el botón (ej. mientras se envía el pedido).
  final VoidCallback? onEliminar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitulo = linea.subtitulo;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                linea.titulo,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(fontSize: 15),
              ),
              if (subtitulo != null && subtitulo.isNotEmpty)
                Text(
                  subtitulo,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                ),
              const SizedBox(height: 2),
              Text(
                '${linea.cantidad} ${linea.etiquetaUnidad} × S/ ${linea.precioUnitario.toStringAsFixed(2)}',
                style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'S/ ${linea.subtotal.toStringAsFixed(2)}',
          style: theme.textTheme.titleMedium?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        IconButton(
          onPressed: onEliminar,
          tooltip: 'Quitar del pedido',
          visualDensity: VisualDensity.compact,
          icon: const PhosphorIcon(
            PhosphorIconsRegular.trash,
            size: 18,
            color: Color(0xFFC62828),
          ),
        ),
      ],
    );
  }
}
