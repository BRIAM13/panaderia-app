import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../models/usuario_sesion.dart';
import '../../widgets/page_transitions.dart';
import 'ajuste_costos_page.dart';
import 'clientes_page.dart';
import 'deudas_page.dart';
import 'medios_pago_page.dart';
import 'nuevo_pedido_page.dart';
import 'pedidos_page.dart';

/// Hub de gestión de la tienda de Hamburguesas para el personal
/// (Trabajador/Admin/SuperAdmin): acceso a Clientes, Nuevo pedido y, solo
/// para ADMIN/SUPERADMIN, Ajuste de costos.
class HamburguesasGestionPage extends StatelessWidget {
  const HamburguesasGestionPage({super.key, required this.usuario});

  final UsuarioSesion usuario;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final esAdmin = usuario.rol == 'ADMIN' || usuario.rol == 'SUPERADMIN';

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
      if (esAdmin)
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

    return Scaffold(
      appBar: AppBar(title: const Text('Gestión de Hamburguesas')),
      body: SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: opciones.length,
          itemBuilder: (context, index) {
            final opcion = opciones[index];
            return Card(
                  margin: const EdgeInsets.only(bottom: 14),
                  child: InkWell(
                    onTap: opcion.onTap,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [scheme.primary, scheme.secondary],
                              ),
                            ),
                            child: Icon(
                              opcion.icono,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  opcion.titulo,
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  opcion.subtitulo,
                                  style: theme.textTheme.bodyMedium,
                                ),
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
                  ),
                )
                .animate(delay: (80 * index).ms)
                .fadeIn(duration: 300.ms)
                .moveY(begin: 16, end: 0);
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
