import 'package:flutter/material.dart';

import '../models/usuario_sesion.dart';
import '../theme/app_theme.dart';
import '../theme/desktop_theme.dart';

/// Barra lateral fija para escritorio (Web/Windows) — mismos datos y
/// acciones que [AppDrawerContenido] (el drawer de celular), pero con una
/// estética completamente distinta: plana, neutra, sin la tarjeta de
/// usuario en degradado ni los íconos en insignias de color. Se separó en
/// su propio widget en vez de parametrizar el drawer de celular, porque
/// son dos lenguajes visuales genuinamente distintos, no una variación
/// menor del mismo diseño.
class DesktopSidebar extends StatelessWidget {
  const DesktopSidebar({
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
    return ColoredBox(
      color: DesktopColors.superficie,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: DesktopColors.fondo,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    usuario.nombreCompleto.isNotEmpty
                        ? usuario.nombreCompleto[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: DesktopColors.textoPrimario,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        usuario.nombreCompleto,
                        style: const TextStyle(
                          color: DesktopColors.textoPrimario,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _etiquetaRol(usuario.rol),
                        style: const TextStyle(
                          color: DesktopColors.textoSecundario,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: DesktopColors.borde),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
              children: [
                if (usuario.esPersonalDeGestion) ...[
                  const _EtiquetaSeccion(texto: 'GESTIÓN'),
                  if (misSlugsTiendas.contains('hamburguesas'))
                    _ItemSidebar(
                      icono: Icons.lunch_dining_rounded,
                      titulo: 'Gestionar Hamburguesas',
                      onTap: onAbrirHamburguesas,
                    ),
                  if (misSlugsTiendas.contains('horneados'))
                    _ItemSidebar(
                      icono: Icons.bakery_dining_rounded,
                      titulo: 'Gestionar Horneados',
                      onTap: () =>
                          onAbrirGestion('Horneados', Icons.bakery_dining_rounded),
                    ),
                  if (usuario.rol == 'ADMIN' || usuario.rol == 'SUPERADMIN')
                    _ItemSidebar(
                      icono: Icons.groups_2_rounded,
                      titulo: 'Trabajadores',
                      onTap: onAbrirTrabajadores,
                    ),
                ],
                if (usuario.rol == 'SUPERADMIN') ...[
                  const SizedBox(height: 12),
                  const _EtiquetaSeccion(texto: 'SISTEMA'),
                  _ItemSidebar(
                    icono: Icons.vpn_key_rounded,
                    titulo: 'Token API Perú',
                    onTap: onAbrirTokenApiPeru,
                  ),
                ],
                if (usuario.esCliente) ...[
                  const SizedBox(height: 12),
                  const _EtiquetaSeccion(texto: 'MI CUENTA'),
                  if (usuario.esPersonalDeGestion)
                    _ItemSidebar(
                      icono: Icons.add_shopping_cart_rounded,
                      titulo: 'Hacer pedido',
                      onTap: onHacerPedido,
                    ),
                  _ItemSidebar(
                    icono: Icons.receipt_long_rounded,
                    titulo: 'Mis pedidos',
                    onTap: onAbrirMisPedidos,
                  ),
                  _ItemSidebar(
                    icono: Icons.account_balance_wallet_rounded,
                    titulo: 'Mis deudas',
                    onTap: onAbrirMisDeudas,
                  ),
                  _ItemSidebar(
                    icono: Icons.badge_outlined,
                    titulo: 'Mi perfil',
                    onTap: onAbrirMiPerfil,
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1, color: DesktopColors.borde),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _ItemSidebar(
              icono: Icons.logout_rounded,
              titulo: 'Cerrar sesión',
              onTap: onCerrarSesion,
              color: AppColors.error,
            ),
          ),
        ],
      ),
    );
  }
}

class _EtiquetaSeccion extends StatelessWidget {
  const _EtiquetaSeccion({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Text(
        texto,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: DesktopColors.textoSecundario,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// Fila del sidebar de escritorio: ícono neutro + texto, con una barra de
/// acento a la izquierda solo al pasar el mouse — sin insignias de color
/// ni fondos degradados, para que se sienta plano/de herramienta.
class _ItemSidebar extends StatefulWidget {
  const _ItemSidebar({
    required this.icono,
    required this.titulo,
    required this.onTap,
    this.color = DesktopColors.textoPrimario,
  });

  final IconData icono;
  final String titulo;
  final VoidCallback onTap;
  final Color color;

  @override
  State<_ItemSidebar> createState() => _ItemSidebarState();
}

class _ItemSidebarState extends State<_ItemSidebar> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: Material(
        color: _hover ? DesktopColors.hover : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(widget.icono, size: 18, color: widget.color),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.titulo,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: widget.color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
