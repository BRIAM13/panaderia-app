import 'package:flutter/material.dart';

import 'tarjeta_3d.dart';

/// Tarjeta de una unidad de negocio dentro del hub de tiendas.
class TiendaCard extends StatelessWidget {
  const TiendaCard({
    super.key,
    required this.nombre,
    required this.icono,
    required this.disponible,
    required this.onTap,
  });

  final String nombre;
  final IconData icono;
  final bool disponible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Tarjeta3D(
      onTap: onTap,
      child: Material(
        color: Theme.of(context).cardColor,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: disponible
                        ? LinearGradient(
                            colors: [scheme.primary, scheme.secondary],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: disponible ? null : const Color(0xFFF0E7D8),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: disponible
                              ? Colors.white.withValues(alpha: 0.22)
                              : scheme.onSurface.withValues(alpha: 0.08),
                        ),
                        child: Icon(
                          icono,
                          size: 26,
                          color: disponible
                              ? Colors.white
                              : scheme.onSurface.withValues(alpha: 0.4),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        nombre,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: disponible
                              ? Colors.white
                              : scheme.onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        disponible ? 'Disponible' : 'Próximamente',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: disponible
                              ? Colors.white.withValues(alpha: 0.85)
                              : scheme.onSurface.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (!disponible)
                Positioned(
                  top: 12,
                  right: 12,
                  child: Icon(
                    Icons.lock_clock_rounded,
                    size: 18,
                    color: scheme.onSurface.withValues(alpha: 0.35),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
