import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../models/usuario_sesion.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/tarjeta_3d.dart';
import 'ajuste_costos_page.dart';
import 'clientes_page.dart';
import 'deudas_page.dart';
import 'medios_pago_page.dart';
import 'nuevo_pedido_page.dart';
import 'pedidos_page.dart';

/// Hub de gestión de la tienda de Hamburguesas para el personal
/// (Trabajador/Admin/SuperAdmin): acceso a Clientes, Nuevo pedido y, solo
/// para ADMIN/SUPERADMIN, Ajuste de costos. Métodos de pago es aún más
/// restringido: solo SUPERADMIN, al manejar las cuentas reales (Yape/
/// Plin/transferencia) donde llega el dinero de la empresa.
class HamburguesasGestionPage extends StatelessWidget {
  const HamburguesasGestionPage({super.key, required this.usuario});

  final UsuarioSesion usuario;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final esAdmin = usuario.rol == 'ADMIN' || usuario.rol == 'SUPERADMIN';
    final esSuperAdmin = usuario.rol == 'SUPERADMIN';

    final opciones = [
      _OpcionGestion(
        titulo: 'Clientes',
        subtitulo: 'Ver, registrar y contactar clientes',
        icono: Icons.groups_rounded,
        onTap: () => pushSlideUpFade(context, (_) => const ClientesPage()),
      ),
      _OpcionGestion(
        titulo: 'Pedidos',
        subtitulo: 'Hoy, atrasados y próximos, de un vistazo',
        icono: Icons.receipt_long_rounded,
        onTap: () => pushSlideUpFade(context, (_) => const PedidosPage()),
      ),
      _OpcionGestion(
        titulo: 'Nuevo pedido',
        subtitulo: 'Registrar un pedido de pan de hamburguesa',
        icono: Icons.add_shopping_cart_rounded,
        onTap: () => pushSlideUpFade(context, (_) => const NuevoPedidoPage()),
      ),
      _OpcionGestion(
        titulo: 'Deudas',
        subtitulo: 'Pedidos entregados que quedaron pendientes de pago',
        icono: Icons.account_balance_wallet_rounded,
        onTap: () => pushSlideUpFade(context, (_) => const DeudasPage()),
      ),
      if (esSuperAdmin)
        _OpcionGestion(
          titulo: 'Métodos de pago',
          subtitulo:
              'Yape, Plin, transferencia — para que los clientes paguen sus deudas',
          icono: Icons.qr_code_2_rounded,
          onTap: () => pushSlideUpFade(context, (_) => const MediosPagoPage()),
        ),
      if (esAdmin)
        _OpcionGestion(
          titulo: 'Ajuste de costos',
          subtitulo: 'Editar el precio del paquete de 12 panes',
          icono: Icons.price_change_rounded,
          onTap: () =>
              pushSlideUpFade(context, (_) => const AjusteCostosPage()),
        ),
    ];

    Widget construirTarjeta(_OpcionGestion opcion, int index) {
      return Tarjeta3D(
            borderRadius: 20,
            onTap: opcion.onTap,
            child: Container(
              color: AppColors.surface,
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [AppColors.primary, AppColors.secondary],
                      ),
                    ),
                    child: Icon(opcion.icono, color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(opcion.titulo, style: theme.textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text(opcion.subtitulo, style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: scheme.onSurface.withValues(alpha: 0.4),
                  ),
                ],
              ),
            ),
          )
          .animate(delay: (80 * index).ms)
          .fadeIn(duration: 300.ms)
          .moveY(begin: 16, end: 0)
          .flipH(begin: 0.1, end: 0, duration: 320.ms);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Gestión de Hamburguesas')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // En pantallas anchas, las opciones se acomodan en una grilla
            // de 2-3 columnas en vez de una lista larga de una sola
            // columna — se aprovecha mejor el ancho y se ve todo de un
            // vistazo, sin scrollear tanto.
            final esEscritorio = constraints.maxWidth >= Breakpoints.tablet;
            if (!esEscritorio) {
              return ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: opciones.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: construirTarjeta(opciones[index], index),
                ),
              );
            }
            final columnas = constraints.maxWidth >= Breakpoints.escritorio
                ? 3
                : 2;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: GridView.builder(
                  padding: const EdgeInsets.all(24),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columnas,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 2.6,
                  ),
                  itemCount: opciones.length,
                  itemBuilder: (context, index) =>
                      construirTarjeta(opciones[index], index),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _OpcionGestion {
  const _OpcionGestion({
    required this.titulo,
    required this.subtitulo,
    required this.icono,
    required this.onTap,
  });

  final String titulo;
  final String subtitulo;
  final IconData icono;
  final VoidCallback onTap;
}
