import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../services/pedidos_service.dart';
import '../theme/app_theme.dart';
import '../utils/fecha_pedido_utils.dart';
import 'tarjeta_3d.dart';

/// Sección temporal a la que pertenece un pedido, según su fecha de
/// entrega comparada con hoy. No es un dato guardado — se recalcula cada
/// vez que se carga la lista, así que un pedido "cambia" de sección solo
/// con el paso del tiempo, sin que nadie tenga que moverlo a mano.
enum SeccionPedido { atrasados, hoy, proximos, sinFecha }

SeccionPedido seccionDePedido(Pedido pedido) {
  final fecha = pedido.fechaEntrega;
  if (fecha == null) return SeccionPedido.sinFecha;

  final hoy = DateTime.now();
  final soloFecha = DateTime(fecha.year, fecha.month, fecha.day);
  final soloHoy = DateTime(hoy.year, hoy.month, hoy.day);

  if (soloFecha.isBefore(soloHoy)) return SeccionPedido.atrasados;
  if (soloFecha.isAtSameMomentAs(soloHoy)) return SeccionPedido.hoy;
  return SeccionPedido.proximos;
}

Map<SeccionPedido, List<Pedido>> agruparPedidosPorFecha(List<Pedido> pedidos) {
  final mapa = <SeccionPedido, List<Pedido>>{
    SeccionPedido.atrasados: [],
    SeccionPedido.hoy: [],
    SeccionPedido.proximos: [],
    SeccionPedido.sinFecha: [],
  };
  for (final pedido in pedidos) {
    mapa[seccionDePedido(pedido)]!.add(pedido);
  }
  // Atrasados/Hoy/Próximos: el más urgente/cercano primero. Sin fecha: más
  // recién registrado primero.
  mapa[SeccionPedido.atrasados]!.sort(
    (a, b) => a.fechaEntrega!.compareTo(b.fechaEntrega!),
  );
  mapa[SeccionPedido.hoy]!.sort(
    (a, b) => a.fechaEntrega!.compareTo(b.fechaEntrega!),
  );
  mapa[SeccionPedido.proximos]!.sort(
    (a, b) => a.fechaEntrega!.compareTo(b.fechaEntrega!),
  );
  mapa[SeccionPedido.sinFecha]!.sort(
    (a, b) => b.fechaCreacion.compareTo(a.fechaCreacion),
  );
  return mapa;
}

/// Lista completa de secciones (Atrasados/Hoy/Próximos/Sin fecha + un
/// Historial aparte para los ya finalizados), cada una oculta sola si no
/// tiene pedidos. Los ENTREGADOS/RECHAZADOS/CANCELADOS nunca entran a
/// Atrasados/Hoy/Próximos — ya se resolvieron, agruparlos por fecha
/// programada solo confundiría ("Atrasado" debería significar "todavía
/// pendiente y ya se pasó la fecha", no "ya se resolvió hace unos días").
/// [mostrarNombreCliente] se apaga en la vista del propio cliente (ya sabe
/// quién es) y se prende en la vista de personal (necesita ver de quién es
/// cada pedido). [onEntregar] solo tiene efecto en pedidos PENDIENTE — es
/// lo que activa el botón "Marcar entregado" en la vista de personal.
/// [onCancelar] solo tiene efecto en SOLICITADO/PENDIENTE — es lo que
/// activa "Cancelar pedido" en la vista del propio cliente.
class ListaPedidosPorSeccion extends StatelessWidget {
  const ListaPedidosPorSeccion({
    super.key,
    required this.pedidos,
    this.mostrarNombreCliente = true,
    this.onEntregar,
    this.onCancelar,
  });

  final List<Pedido> pedidos;
  final bool mostrarNombreCliente;
  final ValueChanged<Pedido>? onEntregar;
  final ValueChanged<Pedido>? onCancelar;

  @override
  Widget build(BuildContext context) {
    final historial = pedidos.where((p) => p.esFinalizado).toList()
      ..sort(
        (a, b) => (b.fechaEntregaReal ?? b.fechaCreacion).compareTo(
          a.fechaEntregaReal ?? a.fechaCreacion,
        ),
      );
    final activos = pedidos.where((p) => !p.esFinalizado).toList();
    final agrupados = agruparPedidosPorFecha(activos);

    return Column(
      children: [
        SeccionPedidos(
          titulo: 'Atrasados',
          subtitulo: 'De ayer o antes — necesitan atención',
          icono: Icons.warning_amber_rounded,
          color: const Color(0xFFC62828),
          pedidos: agrupados[SeccionPedido.atrasados]!,
          mostrarNombreCliente: mostrarNombreCliente,
          onEntregar: onEntregar,
          onCancelar: onCancelar,
        ),
        SeccionPedidos(
          titulo: 'Hoy',
          subtitulo: 'Programados para entregarse hoy',
          icono: Icons.today_rounded,
          color: AppColors.primary,
          pedidos: agrupados[SeccionPedido.hoy]!,
          mostrarNombreCliente: mostrarNombreCliente,
          onEntregar: onEntregar,
          onCancelar: onCancelar,
        ),
        SeccionPedidos(
          titulo: 'Próximos',
          subtitulo: 'Mañana en adelante',
          icono: Icons.upcoming_rounded,
          color: const Color(0xFF2563EB),
          pedidos: agrupados[SeccionPedido.proximos]!,
          mostrarNombreCliente: mostrarNombreCliente,
          onEntregar: onEntregar,
          onCancelar: onCancelar,
        ),
        SeccionPedidos(
          titulo: 'Sin fecha programada',
          subtitulo: 'A coordinar con el cliente',
          icono: Icons.event_busy_rounded,
          color: AppColors.textSecondary,
          pedidos: agrupados[SeccionPedido.sinFecha]!,
          mostrarNombreCliente: mostrarNombreCliente,
          onEntregar: onEntregar,
          onCancelar: onCancelar,
        ),
        SeccionPedidos(
          titulo: 'Historial',
          subtitulo: 'Entregados, rechazados o cancelados',
          icono: Icons.inventory_rounded,
          color: const Color(0xFF6D4C41),
          pedidos: historial,
          mostrarNombreCliente: mostrarNombreCliente,
        ),
      ],
    );
  }
}

class SeccionPedidos extends StatelessWidget {
  const SeccionPedidos({
    super.key,
    required this.titulo,
    required this.subtitulo,
    required this.icono,
    required this.color,
    required this.pedidos,
    this.mostrarNombreCliente = true,
    this.onEntregar,
    this.onCancelar,
  });

  final String titulo;
  final String subtitulo;
  final IconData icono;
  final Color color;
  final List<Pedido> pedidos;
  final bool mostrarNombreCliente;
  final ValueChanged<Pedido>? onEntregar;
  final ValueChanged<Pedido>? onCancelar;

  @override
  Widget build(BuildContext context) {
    if (pedidos.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                titulo,
                style: theme.textTheme.titleMedium?.copyWith(color: color),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${pedidos.length}',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Text(subtitulo, style: theme.textTheme.bodyMedium),
          ),
          const SizedBox(height: 10),
          ...pedidos.asMap().entries.map(
            (entry) =>
                PedidoCard(
                      pedido: entry.value,
                      colorSeccion: color,
                      mostrarNombreCliente: mostrarNombreCliente,
                      onEntregar: onEntregar == null
                          ? null
                          : () => onEntregar!(entry.value),
                      onCancelar: onCancelar == null
                          ? null
                          : () => onCancelar!(entry.value),
                    )
                    .animate(delay: (40 * entry.key).ms)
                    .fadeIn(duration: 250.ms)
                    .moveY(begin: 8, end: 0)
                    .flipH(begin: 0.12, end: 0, duration: 320.ms),
          ),
        ],
      ),
    );
  }
}

class _EstadoPedidoInfo {
  const _EstadoPedidoInfo(this.texto, this.color, this.icono);
  final String texto;
  final Color color;
  final IconData icono;
}

_EstadoPedidoInfo _infoEstado(Pedido pedido) {
  switch (pedido.estado) {
    case 'SOLICITADO':
      return const _EstadoPedidoInfo(
        'Por confirmar',
        Color(0xFFEA8C1B),
        Icons.hourglass_top_rounded,
      );
    case 'RECHAZADO':
      return const _EstadoPedidoInfo(
        'Rechazado',
        Color(0xFFC62828),
        Icons.cancel_rounded,
      );
    case 'CANCELADO':
      return const _EstadoPedidoInfo(
        'Cancelado',
        Color(0xFF6D4C41),
        Icons.block_rounded,
      );
    case 'ENTREGADO':
      return pedido.esDeuda
          ? const _EstadoPedidoInfo(
              'Entregado · Deuda',
              Color(0xFFC62828),
              Icons.account_balance_wallet_rounded,
            )
          : const _EstadoPedidoInfo(
              'Entregado · Pagado',
              Color(0xFF2E7D32),
              Icons.check_circle_rounded,
            );
    default:
      return const _EstadoPedidoInfo(
        'Pendiente a entrega',
        Color(0xFF2563EB),
        Icons.event_available_rounded,
      );
  }
}

class PedidoCard extends StatelessWidget {
  const PedidoCard({
    super.key,
    required this.pedido,
    required this.colorSeccion,
    this.mostrarNombreCliente = true,
    this.onAprobar,
    this.onRechazar,
    this.onEntregar,
    this.onCancelar,
  });

  final Pedido pedido;
  final Color colorSeccion;
  final bool mostrarNombreCliente;

  /// Presentes solo en la vista de personal — su sola presencia no basta:
  /// el botón correspondiente solo se muestra si además el estado del
  /// pedido lo permite (SOLICITADO para aprobar/rechazar, PENDIENTE para
  /// entregar).
  final VoidCallback? onAprobar;
  final VoidCallback? onRechazar;
  final VoidCallback? onEntregar;

  /// Presente solo en la vista del propio cliente — igual que las de
  /// arriba, solo se muestra si el pedido todavía se puede cancelar
  /// (SOLICITADO o PENDIENTE, no si ya fue entregado).
  final VoidCallback? onCancelar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cliente = pedido.cliente;
    final nombreComercial = cliente.nombreComercial;
    final estadoInfo = _infoEstado(pedido);
    final mostrarAccionesSolicitud =
        pedido.esSolicitado && (onAprobar != null || onRechazar != null);
    final mostrarAccionEntregar =
        pedido.estado == 'PENDIENTE' && onEntregar != null;
    final mostrarAccionCancelar = pedido.sePuedeCancelar && onCancelar != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Tarjeta3D(
        borderRadius: 20,
        child: Container(
          color: AppColors.surface,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          colorSeccion.withValues(alpha: 0.20),
                          colorSeccion.withValues(alpha: 0.08),
                        ],
                      ),
                    ),
                    child: Icon(
                      pedido.tipoPedido == 'PAQUETES'
                          ? Icons.inventory_2_rounded
                          : Icons.local_dining_rounded,
                      color: colorSeccion,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (mostrarNombreCliente) ...[
                          Text(
                            cliente.nombreParaMostrar,
                            style: theme.textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (nombreComercial != null) ...[
                            const SizedBox(height: 1),
                            Text(
                              nombreComercial,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.secondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: 4),
                        ],
                        Text(
                          '${pedido.tipoPedido == 'PAQUETES' ? 'Paquetes' : 'Unidades'} · ${pedido.cantidad} · S/ ${pedido.total.toStringAsFixed(2)}',
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              pedido.fechaEntrega != null
                                  ? Icons.schedule_rounded
                                  : Icons.event_busy_rounded,
                              size: 14,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                pedido.fechaEntrega != null
                                    ? formatearFechaEntrega(
                                        pedido.fechaEntrega!,
                                      )
                                    : 'Sin fecha programada',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: estadoInfo.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          estadoInfo.icono,
                          size: 13,
                          color: estadoInfo.color,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          estadoInfo.texto,
                          style: TextStyle(
                            color: estadoInfo.color,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (mostrarAccionesSolicitud) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (onRechazar != null)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onRechazar,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFC62828),
                          ),
                          child: const Text('Rechazar'),
                        ),
                      ),
                    if (onRechazar != null && onAprobar != null)
                      const SizedBox(width: 10),
                    if (onAprobar != null)
                      Expanded(
                        child: FilledButton(
                          onPressed: onAprobar,
                          child: const Text('Aceptar'),
                        ),
                      ),
                  ],
                ),
              ],
              if (mostrarAccionEntregar) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onEntregar,
                    icon: const Icon(Icons.local_shipping_rounded, size: 18),
                    label: const Text('Marcar entregado'),
                  ),
                ),
              ],
              if (mostrarAccionCancelar) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onCancelar,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFC62828),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Cancelar pedido'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
