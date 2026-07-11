import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/usuario_sesion.dart';
import '../theme/app_theme.dart';

/// Drawer de perfil: sección "GESTIÓN" para el personal (trabajador/admin/
/// superadmin) y sección "MI CUENTA" con los apartados propios de cliente
/// (pedidos, deudas, perfil) — un usuario híbrido (a la vez trabajador y
/// cliente, ej. porque todo trabajador nuevo también se registra como
/// cliente) ve AMBAS secciones a la vez, sin que eso le cambie su pantalla
/// principal: su vista de inicio sigue siendo siempre la de gestión
/// (Dashboard/tiendas), y el apartado de cliente queda aquí, a un toque de
/// distancia, en vez de intercambiar toda la pantalla.
class AppDrawer extends StatelessWidget {
  const AppDrawer({
    super.key,
    required this.usuario,
    required this.onAbrirGestion,
    required this.onAbrirHamburguesas,
    required this.onAbrirMiPerfil,
    required this.onAbrirMisPedidos,
    required this.onAbrirMisDeudas,
    required this.onHacerPedido,
    required this.onAbrirTrabajadores,
    required this.onAbrirTokenApiPeru,
    required this.onCerrarSesion,
    this.misSlugsTiendas = const {},
  });

  final UsuarioSesion usuario;
  final void Function(String nombre, IconData icono) onAbrirGestion;
  final VoidCallback onAbrirHamburguesas;
  final VoidCallback onAbrirMiPerfil;
  final VoidCallback onAbrirMisPedidos;
  final VoidCallback onAbrirMisDeudas;
  final VoidCallback onHacerPedido;
  final VoidCallback onAbrirTrabajadores;
  final VoidCallback onAbrirTokenApiPeru;
  final VoidCallback onCerrarSesion;

  /// Slugs de tiendas donde este trabajador/admin tiene acceso vigente —
  /// controla qué "Gestionar X" se muestra. SUPERADMIN las recibe todas.
  final Set<String> misSlugsTiendas;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.background,
      child: AppDrawerContenido(
        usuario: usuario,
        misSlugsTiendas: misSlugsTiendas,
        onAbrirGestion: onAbrirGestion,
        onAbrirHamburguesas: onAbrirHamburguesas,
        onAbrirMiPerfil: onAbrirMiPerfil,
        onAbrirMisPedidos: onAbrirMisPedidos,
        onAbrirMisDeudas: onAbrirMisDeudas,
        onHacerPedido: onHacerPedido,
        onAbrirTrabajadores: onAbrirTrabajadores,
        onAbrirTokenApiPeru: onAbrirTokenApiPeru,
        onCerrarSesion: onCerrarSesion,
      ),
    );
  }
}

/// El contenido del drawer, sin el `Drawer` (overlay deslizante) que lo
/// envuelve — separado para poder reusarlo tal cual como panel lateral fijo
/// en pantallas anchas (ver `HomePage`), donde no tiene sentido un overlay
/// que se desliza si ya está siempre visible.
class AppDrawerContenido extends StatelessWidget {
  const AppDrawerContenido({
    super.key,
    required this.usuario,
    required this.onAbrirGestion,
    required this.onAbrirHamburguesas,
    required this.onAbrirMiPerfil,
    required this.onAbrirMisPedidos,
    required this.onAbrirMisDeudas,
    required this.onHacerPedido,
    required this.onAbrirTrabajadores,
    required this.onAbrirTokenApiPeru,
    required this.onCerrarSesion,
    this.misSlugsTiendas = const {},
  });

  final UsuarioSesion usuario;
  final void Function(String nombre, IconData icono) onAbrirGestion;
  final VoidCallback onAbrirHamburguesas;
  final VoidCallback onAbrirMiPerfil;
  final VoidCallback onAbrirMisPedidos;
  final VoidCallback onAbrirMisDeudas;
  final VoidCallback onHacerPedido;
  final VoidCallback onAbrirTrabajadores;
  final VoidCallback onAbrirTokenApiPeru;
  final VoidCallback onCerrarSesion;
  final Set<String> misSlugsTiendas;

  String _etiquetaRol(String rol) {
    switch (rol) {
      case 'SUPERADMIN':
        return 'Super Administrador';
      case 'ADMIN':
        return 'Administrador';
      case 'TRABAJADOR':
        return 'Trabajador';
      default:
        return 'Cliente';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary, AppColors.secondary],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.28),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.4),
                        width: 1.4,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      usuario.nombreCompleto.isNotEmpty
                          ? usuario.nombreCompleto[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          usuario.nombreCompleto,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.20),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _etiquetaRol(usuario.rol),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 300.ms).moveY(begin: -10, end: 0),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                children: [
                  if (usuario.esPersonalDeGestion) ...[
                    const _EncabezadoSeccion(texto: 'GESTIÓN'),
                    if (misSlugsTiendas.contains('hamburguesas'))
                      _FilaMenu(
                        icono: Icons.lunch_dining_rounded,
                        titulo: 'Gestionar Hamburguesas',
                        onTap: onAbrirHamburguesas,
                        delay: 40,
                      ),
                    if (misSlugsTiendas.contains('horneados'))
                      _FilaMenu(
                        icono: Icons.bakery_dining_rounded,
                        titulo: 'Gestionar Horneados',
                        onTap: () => onAbrirGestion(
                          'Horneados',
                          Icons.bakery_dining_rounded,
                        ),
                        delay: 70,
                      ),
                    if (usuario.rol == 'ADMIN' || usuario.rol == 'SUPERADMIN')
                      _FilaMenu(
                        icono: Icons.groups_2_rounded,
                        titulo: 'Trabajadores',
                        onTap: onAbrirTrabajadores,
                        delay: 100,
                      ),
                  ],
                  if (usuario.rol == 'SUPERADMIN') ...[
                    const SizedBox(height: 8),
                    const Divider(height: 1),
                    const _EncabezadoSeccion(texto: 'SISTEMA'),
                    _FilaMenu(
                      icono: Icons.vpn_key_rounded,
                      titulo: 'Token API Perú',
                      onTap: onAbrirTokenApiPeru,
                      delay: 130,
                    ),
                  ],
                  if (usuario.esCliente) ...[
                    if (usuario.esPersonalDeGestion) ...[
                      const SizedBox(height: 8),
                      const Divider(height: 1),
                    ],
                    const _EncabezadoSeccion(texto: 'MI CUENTA'),
                    if (usuario.esPersonalDeGestion)
                      _FilaMenu(
                        icono: Icons.add_shopping_cart_rounded,
                        titulo: 'Hacer pedido',
                        onTap: onHacerPedido,
                        delay: 160,
                      ),
                    _FilaMenu(
                      icono: Icons.receipt_long_rounded,
                      titulo: 'Mis pedidos',
                      onTap: onAbrirMisPedidos,
                      delay: 190,
                    ),
                    _FilaMenu(
                      icono: Icons.account_balance_wallet_rounded,
                      titulo: 'Mis deudas',
                      onTap: onAbrirMisDeudas,
                      delay: 220,
                    ),
                    _FilaMenu(
                      icono: Icons.badge_outlined,
                      titulo: 'Mi perfil',
                      onTap: onAbrirMiPerfil,
                      delay: 250,
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: _FilaMenu(
                icono: Icons.logout_rounded,
                titulo: 'Cerrar sesión',
                onTap: onCerrarSesion,
                color: AppColors.error,
                delay: 0,
              ),
            ),
          ],
        ),
      );
  }
}

class _EncabezadoSeccion extends StatelessWidget {
  const _EncabezadoSeccion({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
      child: Text(
        texto,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w800,
          color: AppColors.secondary,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// Fila táctil del drawer: ícono en una insignia redondeada de color +
/// título + flecha, con feedback de presión y entrada escalonada — en vez
/// del `ListTile` plano por defecto.
class _FilaMenu extends StatelessWidget {
  const _FilaMenu({
    required this.icono,
    required this.titulo,
    required this.onTap,
    required this.delay,
    this.color = AppColors.primary,
  });

  final IconData icono;
  final String titulo;
  final VoidCallback onTap;
  final int delay;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icono, color: color, size: 19),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        titulo,
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: color == AppColors.error
                                  ? AppColors.error
                                  : AppColors.textPrimary,
                            ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: AppColors.textSecondary.withValues(alpha: 0.6),
                    ),
                  ],
                ),
              ),
            ),
          ),
        )
        .animate(delay: delay.ms)
        .fadeIn(duration: 260.ms)
        .moveX(begin: -10, end: 0, curve: Curves.easeOutCubic);
  }
}
