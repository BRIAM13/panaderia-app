import 'package:flutter/material.dart';

import '../models/usuario_sesion.dart';

/// Drawer de perfil con el switch "Cambiar de vista" para usuarios
/// híbridos (Cliente + Trabajador) y el menú de gestión para el personal.
class AppDrawer extends StatelessWidget {
  const AppDrawer({
    super.key,
    required this.usuario,
    required this.vistaTrabajador,
    required this.onCambiarVista,
    required this.onAbrirGestion,
    required this.onAbrirHamburguesas,
    required this.onAbrirMiPerfil,
    required this.onAbrirMisPedidos,
    required this.onAbrirMisDeudas,
    required this.onAbrirTrabajadores,
    required this.onCerrarSesion,
    this.misSlugsTiendas = const {},
  });

  final UsuarioSesion usuario;
  final bool vistaTrabajador;
  final ValueChanged<bool> onCambiarVista;
  final void Function(String nombre, IconData icono) onAbrirGestion;
  final VoidCallback onAbrirHamburguesas;
  final VoidCallback onAbrirMiPerfil;
  final VoidCallback onAbrirMisPedidos;
  final VoidCallback onAbrirMisDeudas;
  final VoidCallback onAbrirTrabajadores;
  final VoidCallback onCerrarSesion;

  /// Slugs de tiendas donde este trabajador/admin tiene acceso vigente —
  /// controla qué "Gestionar X" se muestra. SUPERADMIN las recibe todas.
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
    final scheme = theme.colorScheme;

    return Drawer(
      backgroundColor: scheme.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: scheme.primary,
                    child: Text(
                      usuario.nombreCompleto.isNotEmpty
                          ? usuario.nombreCompleto[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
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
                          style: theme.textTheme.titleMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Chip(
                          label: Text(_etiquetaRol(usuario.rol)),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (usuario.esHibrido) ...[
              SwitchListTile(
                value: vistaTrabajador,
                onChanged: onCambiarVista,
                secondary: Icon(
                  vistaTrabajador
                      ? Icons.storefront_rounded
                      : Icons.shopping_bag_rounded,
                ),
                title: const Text('Cambiar de vista'),
                subtitle: Text(
                  vistaTrabajador
                      ? 'Viendo como Trabajador'
                      : 'Viendo como Cliente',
                ),
              ),
              const Divider(height: 1),
            ],
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  if (vistaTrabajador) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(
                        'GESTIÓN',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (misSlugsTiendas.contains('hamburguesas'))
                      ListTile(
                        leading: const Icon(Icons.lunch_dining_rounded),
                        title: const Text('Gestionar Hamburguesas'),
                        onTap: onAbrirHamburguesas,
                      ),
                    if (misSlugsTiendas.contains('horneados'))
                      ListTile(
                        leading: const Icon(Icons.bakery_dining_rounded),
                        title: const Text('Gestionar Horneados'),
                        onTap: () => onAbrirGestion(
                          'Horneados',
                          Icons.bakery_dining_rounded,
                        ),
                      ),
                    if (usuario.rol == 'ADMIN' || usuario.rol == 'SUPERADMIN')
                      ListTile(
                        leading: const Icon(Icons.groups_2_rounded),
                        title: const Text('Trabajadores'),
                        onTap: onAbrirTrabajadores,
                      ),
                  ] else ...[
                    ListTile(
                      leading: const Icon(Icons.receipt_long_rounded),
                      title: const Text('Mis pedidos'),
                      onTap: onAbrirMisPedidos,
                    ),
                    ListTile(
                      leading: const Icon(Icons.account_balance_wallet_rounded),
                      title: const Text('Mis deudas'),
                      onTap: onAbrirMisDeudas,
                    ),
                    ListTile(
                      leading: const Icon(Icons.badge_outlined),
                      title: const Text('Mi perfil'),
                      onTap: onAbrirMiPerfil,
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.logout_rounded, color: scheme.error),
              title: Text(
                'Cerrar sesión',
                style: TextStyle(color: scheme.error),
              ),
              onTap: onCerrarSesion,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
