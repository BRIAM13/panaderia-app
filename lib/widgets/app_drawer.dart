import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/usuario_sesion.dart';
import '../theme/app_theme.dart';

/// Drawer de perfil: sección "MENÚ" para el personal (trabajador/admin/
/// superadmin) — con "Inicio" y, directo debajo, las acciones de su tienda
/// (o de sus tiendas, si tiene más de una) — y sección "MI CUENTA" con los
/// apartados propios de cliente (pedidos, deudas, perfil). Un usuario
/// híbrido (a la vez trabajador y cliente, ej. porque todo trabajador nuevo
/// también se registra como cliente) ve AMBAS secciones a la vez, sin que
/// eso le cambie su pantalla principal: su vista de inicio sigue siendo
/// siempre la de gestión (Dashboard/tiendas), y el apartado de cliente
/// queda aquí, a un toque de distancia, en vez de intercambiar toda la
/// pantalla.
class AppDrawer extends StatelessWidget {
  const AppDrawer({
    super.key,
    required this.usuario,
    required this.onIrAInicio,
    required this.onAbrirGestion,
    required this.onAbrirClientesHamburguesas,
    required this.onAbrirPedidosHamburguesas,
    required this.onAbrirNuevoPedidoHamburguesas,
    required this.onAbrirDeudasHamburguesas,
    required this.onAbrirMediosPagoHamburguesas,
    required this.onAbrirAjusteCostosHamburguesas,
    required this.onAbrirPedidosPanaderia,
    required this.onAbrirNuevoPedidoPanaderia,
    required this.onAbrirDeudasPanaderia,
    required this.onAbrirAjustePreciosPanaderia,
    required this.onAbrirMiPerfil,
    required this.onAbrirMisPedidos,
    required this.onAbrirMisDeudas,
    required this.onAbrirTrabajadores,
    required this.onAbrirTokenApiPeru,
    required this.onAbrirVersionApp,
    required this.onCerrarSesion,
    this.misSlugsTiendas = const {},
  });

  final UsuarioSesion usuario;
  final VoidCallback onIrAInicio;
  final void Function(String nombre, IconData icono) onAbrirGestion;
  final VoidCallback onAbrirClientesHamburguesas;
  final VoidCallback onAbrirPedidosHamburguesas;
  final VoidCallback onAbrirNuevoPedidoHamburguesas;
  final VoidCallback onAbrirDeudasHamburguesas;
  final VoidCallback onAbrirMediosPagoHamburguesas;
  final VoidCallback onAbrirAjusteCostosHamburguesas;
  final VoidCallback onAbrirPedidosPanaderia;
  final VoidCallback onAbrirNuevoPedidoPanaderia;
  final VoidCallback onAbrirDeudasPanaderia;
  final VoidCallback onAbrirAjustePreciosPanaderia;
  final VoidCallback onAbrirMiPerfil;
  final VoidCallback onAbrirMisPedidos;
  final VoidCallback onAbrirMisDeudas;
  final VoidCallback onAbrirTrabajadores;
  final VoidCallback onAbrirTokenApiPeru;
  final VoidCallback onAbrirVersionApp;
  final VoidCallback onCerrarSesion;

  /// Slugs de tiendas donde este trabajador/admin tiene acceso vigente.
  /// SUPERADMIN las recibe todas.
  final Set<String> misSlugsTiendas;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.background,
      child: AppDrawerContenido(
        usuario: usuario,
        misSlugsTiendas: misSlugsTiendas,
        onIrAInicio: onIrAInicio,
        onAbrirGestion: onAbrirGestion,
        onAbrirClientesHamburguesas: onAbrirClientesHamburguesas,
        onAbrirPedidosHamburguesas: onAbrirPedidosHamburguesas,
        onAbrirNuevoPedidoHamburguesas: onAbrirNuevoPedidoHamburguesas,
        onAbrirDeudasHamburguesas: onAbrirDeudasHamburguesas,
        onAbrirMediosPagoHamburguesas: onAbrirMediosPagoHamburguesas,
        onAbrirAjusteCostosHamburguesas: onAbrirAjusteCostosHamburguesas,
        onAbrirPedidosPanaderia: onAbrirPedidosPanaderia,
        onAbrirNuevoPedidoPanaderia: onAbrirNuevoPedidoPanaderia,
        onAbrirDeudasPanaderia: onAbrirDeudasPanaderia,
        onAbrirAjustePreciosPanaderia: onAbrirAjustePreciosPanaderia,
        onAbrirMiPerfil: onAbrirMiPerfil,
        onAbrirMisPedidos: onAbrirMisPedidos,
        onAbrirMisDeudas: onAbrirMisDeudas,
        onAbrirTrabajadores: onAbrirTrabajadores,
        onAbrirTokenApiPeru: onAbrirTokenApiPeru,
        onAbrirVersionApp: onAbrirVersionApp,
        onCerrarSesion: onCerrarSesion,
      ),
    );
  }
}

/// El contenido del drawer, sin el `Drawer` (overlay deslizante) que lo
/// envuelve — separado para poder reusarlo tal cual como panel lateral fijo
/// en pantallas anchas (ver `HomePage`), donde no tiene sentido un overlay
/// que se desliza si ya está siempre visible.
///
/// `StatefulWidget` (antes era sin estado) porque ahora necesita recordar
/// qué secciones quedaron desplegadas ("Tiendas", "Hamburguesas") mientras
/// el drawer sigue abierto.
class AppDrawerContenido extends StatefulWidget {
  const AppDrawerContenido({
    super.key,
    required this.usuario,
    required this.onIrAInicio,
    required this.onAbrirGestion,
    required this.onAbrirClientesHamburguesas,
    required this.onAbrirPedidosHamburguesas,
    required this.onAbrirNuevoPedidoHamburguesas,
    required this.onAbrirDeudasHamburguesas,
    required this.onAbrirMediosPagoHamburguesas,
    required this.onAbrirAjusteCostosHamburguesas,
    required this.onAbrirPedidosPanaderia,
    required this.onAbrirNuevoPedidoPanaderia,
    required this.onAbrirDeudasPanaderia,
    required this.onAbrirAjustePreciosPanaderia,
    required this.onAbrirMiPerfil,
    required this.onAbrirMisPedidos,
    required this.onAbrirMisDeudas,
    required this.onAbrirTrabajadores,
    required this.onAbrirTokenApiPeru,
    required this.onAbrirVersionApp,
    required this.onCerrarSesion,
    this.misSlugsTiendas = const {},
  });

  final UsuarioSesion usuario;
  final VoidCallback onIrAInicio;
  final void Function(String nombre, IconData icono) onAbrirGestion;
  final VoidCallback onAbrirClientesHamburguesas;
  final VoidCallback onAbrirPedidosHamburguesas;
  final VoidCallback onAbrirNuevoPedidoHamburguesas;
  final VoidCallback onAbrirDeudasHamburguesas;
  final VoidCallback onAbrirMediosPagoHamburguesas;
  final VoidCallback onAbrirAjusteCostosHamburguesas;
  final VoidCallback onAbrirPedidosPanaderia;
  final VoidCallback onAbrirNuevoPedidoPanaderia;
  final VoidCallback onAbrirDeudasPanaderia;
  final VoidCallback onAbrirAjustePreciosPanaderia;
  final VoidCallback onAbrirMiPerfil;
  final VoidCallback onAbrirMisPedidos;
  final VoidCallback onAbrirMisDeudas;
  final VoidCallback onAbrirTrabajadores;
  final VoidCallback onAbrirTokenApiPeru;
  final VoidCallback onAbrirVersionApp;
  final VoidCallback onCerrarSesion;
  final Set<String> misSlugsTiendas;

  @override
  State<AppDrawerContenido> createState() => _AppDrawerContenidoState();
}

class _AppDrawerContenidoState extends State<AppDrawerContenido> {
  /// Claves de las secciones desplegables que están abiertas ahora mismo
  /// (ej. 'tiendas', 'hamburguesas').
  final Set<String> _abiertas = {};

  void _alternar(String clave) {
    setState(() {
      if (!_abiertas.remove(clave)) _abiertas.add(clave);
    });
  }

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

  /// Acciones reales dentro de la tienda de Hamburguesas — la única con
  /// pantallas propias hoy. Métodos de pago/Ajuste de costos quedan
  /// restringidos por rol, igual que antes.
  List<_FilaMenu> _accionesHamburguesas(UsuarioSesion usuario) {
    final esAdmin = usuario.rol == 'ADMIN' || usuario.rol == 'SUPERADMIN';
    final esSuperAdmin = usuario.rol == 'SUPERADMIN';
    return [
      _FilaMenu(
        icono: Icons.groups_rounded,
        titulo: 'Clientes',
        onTap: widget.onAbrirClientesHamburguesas,
        delay: 0,
      ),
      _FilaMenu(
        icono: Icons.receipt_long_rounded,
        titulo: 'Pedidos',
        onTap: widget.onAbrirPedidosHamburguesas,
        delay: 0,
      ),
      _FilaMenu(
        icono: Icons.add_shopping_cart_rounded,
        titulo: 'Nuevo pedido',
        onTap: widget.onAbrirNuevoPedidoHamburguesas,
        delay: 0,
      ),
      _FilaMenu(
        icono: Icons.account_balance_wallet_rounded,
        titulo: 'Deudas',
        onTap: widget.onAbrirDeudasHamburguesas,
        delay: 0,
      ),
      if (esSuperAdmin)
        _FilaMenu(
          icono: Icons.qr_code_2_rounded,
          titulo: 'Métodos de pago',
          onTap: widget.onAbrirMediosPagoHamburguesas,
          delay: 0,
        ),
      if (esAdmin)
        _FilaMenu(
          icono: Icons.price_change_rounded,
          titulo: 'Ajuste de costos',
          onTap: widget.onAbrirAjusteCostosHamburguesas,
          delay: 0,
        ),
    ];
  }

  /// Acciones de Panadería — mismo nivel operativo que Hamburguesas
  /// (Pedidos/Nuevo pedido/Deudas), reusando Clientes y Métodos de pago
  /// (ninguno de los dos es realmente "de Hamburguesas": Clientes es global
  /// y Métodos de pago ya deja elegir la tienda internamente). "Ajustar
  /// precios" reemplaza al "Ajuste de costos" de Hamburguesas (que edita el
  /// precio del PAQUETE de 12, un concepto que Panadería no tiene): en vez
  /// de un único valor global, deja elegir cualquier pan del catálogo y
  /// cambiar su precio por unidad.
  List<_FilaMenu> _accionesPanaderia(UsuarioSesion usuario) {
    final esAdmin = usuario.rol == 'ADMIN' || usuario.rol == 'SUPERADMIN';
    final esSuperAdmin = usuario.rol == 'SUPERADMIN';
    return [
      _FilaMenu(
        icono: Icons.groups_rounded,
        titulo: 'Clientes',
        onTap: widget.onAbrirClientesHamburguesas,
        delay: 0,
      ),
      _FilaMenu(
        icono: Icons.receipt_long_rounded,
        titulo: 'Pedidos',
        onTap: widget.onAbrirPedidosPanaderia,
        delay: 0,
      ),
      _FilaMenu(
        icono: Icons.add_shopping_cart_rounded,
        titulo: 'Nuevo pedido',
        onTap: widget.onAbrirNuevoPedidoPanaderia,
        delay: 0,
      ),
      _FilaMenu(
        icono: Icons.account_balance_wallet_rounded,
        titulo: 'Deudas',
        onTap: widget.onAbrirDeudasPanaderia,
        delay: 0,
      ),
      if (esSuperAdmin)
        _FilaMenu(
          icono: Icons.qr_code_2_rounded,
          titulo: 'Métodos de pago',
          onTap: widget.onAbrirMediosPagoHamburguesas,
          delay: 0,
        ),
      if (esAdmin)
        _FilaMenu(
          icono: Icons.price_change_rounded,
          titulo: 'Ajustar precios',
          onTap: widget.onAbrirAjustePreciosPanaderia,
          delay: 0,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usuario = widget.usuario;

    // Solo se listan acá las tiendas con acceso real ya construido en la
    // app (Hamburguesas y Panadería completas, Horneados con su pantalla
    // "Próximamente") — Mercadería/Pastelería todavía no tienen nada que
    // mostrar en el drawer de personal, aunque ya existan como tienda.
    final tieneHamburguesas = widget.misSlugsTiendas.contains('hamburguesas');
    final tieneHorneados = widget.misSlugsTiendas.contains('horneados');
    final tienePanaderia = widget.misSlugsTiendas.contains('panaderia');
    final cantidadTiendas =
        (tieneHamburguesas ? 1 : 0) +
        (tieneHorneados ? 1 : 0) +
        (tienePanaderia ? 1 : 0);

    Widget seccionHamburguesas({required bool anidadaEnTiendas}) {
      final acciones = _accionesHamburguesas(usuario);
      if (!anidadaEnTiendas) {
        // Única tienda del usuario: sus acciones van directo, sin un nivel
        // "Hamburguesas" de por medio que solo agregaría un toque extra.
        return Column(
          children: [
            const _EncabezadoSeccion(texto: 'HAMBURGUESAS'),
            ...acciones,
          ],
        );
      }
      return _FilaMenuExpandible(
        icono: Icons.lunch_dining_rounded,
        titulo: 'Hamburguesas',
        expandido: _abiertas.contains('hamburguesas'),
        onTap: () => _alternar('hamburguesas'),
        delay: 70,
        hijos: acciones,
      );
    }

    Widget seccionPanaderia({required bool anidadaEnTiendas}) {
      final acciones = _accionesPanaderia(usuario);
      if (!anidadaEnTiendas) {
        return Column(
          children: [
            const _EncabezadoSeccion(texto: 'PANADERÍA'),
            ...acciones,
          ],
        );
      }
      return _FilaMenuExpandible(
        icono: Icons.bakery_dining_rounded,
        titulo: 'Panadería',
        expandido: _abiertas.contains('panaderia'),
        onTap: () => _alternar('panaderia'),
        delay: 85,
        hijos: acciones,
      );
    }

    Widget filaHorneados() => _FilaMenu(
      icono: Icons.bakery_dining_rounded,
      titulo: 'Horneados',
      onTap: () => widget.onAbrirGestion('Horneados', Icons.bakery_dining_rounded),
      delay: 100,
    );

    return SafeArea(
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
                  margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
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
                  // Tocar la tarjeta del usuario lleva a "Mi perfil" — antes
                  // esa pantalla solo aparecía en "MI CUENTA", una sección
                  // que se arma a partir de si la persona tiene un perfil
                  // de Cliente activo. Un SUPERADMIN sembrado directo (sin
                  // pasar por el registro normal) puede no tener ese
                  // registro y quedarse sin forma de llegar a sus propios
                  // datos — tocar acá siempre funciona, sin importar eso.
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(22),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: widget.onAbrirMiPerfil,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 20, 14, 20),
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
                            Icon(
                              Icons.chevron_right_rounded,
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
                .animate()
                .fadeIn(duration: 300.ms)
                .moveY(begin: -10, end: 0),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                children: [
                  if (usuario.esPersonalDeGestion) ...[
                    const _EncabezadoSeccion(texto: 'MENÚ'),
                    _FilaMenu(
                      icono: Icons.home_rounded,
                      titulo: 'Inicio',
                      onTap: widget.onIrAInicio,
                      delay: 20,
                    ),
                    // Una sola tienda con acceso: sus acciones van directo,
                    // sin un nivel "Tiendas" de por medio. Dos o más: se
                    // agrupan bajo "Tiendas" para no saturar el menú.
                    if (cantidadTiendas == 1) ...[
                      if (tieneHamburguesas)
                        seccionHamburguesas(anidadaEnTiendas: false),
                      if (tienePanaderia)
                        seccionPanaderia(anidadaEnTiendas: false),
                      if (tieneHorneados) ...[
                        const _EncabezadoSeccion(texto: 'HORNEADOS'),
                        filaHorneados(),
                      ],
                    ] else if (cantidadTiendas > 1)
                      _FilaMenuExpandible(
                        icono: Icons.storefront_rounded,
                        titulo: 'Tiendas',
                        expandido: _abiertas.contains('tiendas'),
                        onTap: () => _alternar('tiendas'),
                        delay: 40,
                        hijos: [
                          if (tieneHamburguesas)
                            seccionHamburguesas(anidadaEnTiendas: true),
                          if (tienePanaderia)
                            seccionPanaderia(anidadaEnTiendas: true),
                          if (tieneHorneados) filaHorneados(),
                        ],
                      ),
                    if (usuario.rol == 'ADMIN' || usuario.rol == 'SUPERADMIN')
                      _FilaMenu(
                        icono: Icons.groups_2_rounded,
                        titulo: 'Trabajadores',
                        onTap: widget.onAbrirTrabajadores,
                        delay: 130,
                      ),
                  ],
                  if (usuario.rol == 'SUPERADMIN') ...[
                    const SizedBox(height: 8),
                    const Divider(height: 1),
                    const _EncabezadoSeccion(texto: 'SISTEMA'),
                    _FilaMenu(
                      icono: Icons.vpn_key_rounded,
                      titulo: 'Token API Perú',
                      onTap: widget.onAbrirTokenApiPeru,
                      delay: 160,
                    ),
                    _FilaMenu(
                      icono: Icons.system_update_rounded,
                      titulo: 'Versión de la app',
                      onTap: widget.onAbrirVersionApp,
                      delay: 175,
                    ),
                  ],
                  if (usuario.esCliente) ...[
                    if (usuario.esPersonalDeGestion) ...[
                      const SizedBox(height: 8),
                      const Divider(height: 1),
                    ],
                    const _EncabezadoSeccion(texto: 'MI CUENTA'),
                    _FilaMenu(
                      icono: Icons.receipt_long_rounded,
                      titulo: 'Mis pedidos',
                      onTap: widget.onAbrirMisPedidos,
                      delay: 190,
                    ),
                    _FilaMenu(
                      icono: Icons.account_balance_wallet_rounded,
                      titulo: 'Mis deudas',
                      onTap: widget.onAbrirMisDeudas,
                      delay: 220,
                    ),
                    _FilaMenu(
                      icono: Icons.badge_outlined,
                      titulo: 'Mi perfil',
                      onTap: widget.onAbrirMiPerfil,
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
                onTap: widget.onCerrarSesion,
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

/// Como [_FilaMenu], pero abre/cierra una lista de hijos debajo (ej.
/// "Tiendas" → cada tienda; "Hamburguesas" → sus acciones) en vez de
/// navegar — la flecha rota 90° y los hijos aparecen con un alto animado,
/// ligeramente sangrados para que se note que dependen de esta fila.
class _FilaMenuExpandible extends StatelessWidget {
  const _FilaMenuExpandible({
    required this.icono,
    required this.titulo,
    required this.expandido,
    required this.onTap,
    required this.delay,
    required this.hijos,
  });

  final IconData icono;
  final String titulo;
  final bool expandido;
  final VoidCallback onTap;
  final int delay;
  final List<Widget> hijos;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
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
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(icono, color: AppColors.primary, size: 19),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            titulo,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                          ),
                        ),
                        AnimatedRotation(
                          turns: expandido ? 0.25 : 0,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          child: Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: AppColors.textSecondary.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
            .animate(delay: delay.ms)
            .fadeIn(duration: 260.ms)
            .moveX(begin: -10, end: 0, curve: Curves.easeOutCubic),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: !expandido
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: Column(children: hijos),
                ),
        ),
      ],
    );
  }
}
