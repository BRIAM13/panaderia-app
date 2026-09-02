import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../services/pedidos_service.dart';
import '../theme/app_theme.dart';
import '../theme/breakpoints.dart';
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

/// Lista completa de secciones activas (Atrasados/Hoy/Próximos/Sin fecha),
/// cada una oculta sola si no tiene pedidos. Los ya finalizados
/// (ENTREGADO/RECHAZADO/CANCELADO) no aparecen acá — se resolvieron, y
/// viven aparte en la pantalla de Historial de ventas (Dashboard → "Ventas
/// de hoy"), no agrupados por fecha programada como estos.
/// [mostrarNombreCliente] se apaga en la vista del propio cliente (ya sabe
/// quién es) y se prende en la vista de personal (necesita ver de quién es
/// cada pedido). [onEntregar] solo tiene efecto en pedidos PENDIENTE — es
/// lo que activa el botón "Marcar entregado" en la vista de personal.
/// [onCancelar] solo tiene efecto en SOLICITADO/PENDIENTE — activa
/// "Cancelar pedido" tanto en la vista del propio cliente (autoservicio,
/// solo sus pedidos) como en la de personal (cualquier pedido de su
/// tienda) — cada vista pasa su propio callback contra el endpoint que le
/// corresponde.
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
    // Los ya finalizados (entregados/rechazados/cancelados) ya no se
    // muestran acá — se movieron a la nueva pantalla de Historial de
    // ventas (Dashboard → "Ventas de hoy", solo Admin/Superadmin).
    final activos = pedidos.where((p) => !p.esFinalizado).toList();
    final agrupados = agruparPedidosPorFecha(activos);

    return Column(
      children: [
        SeccionPedidos(
          titulo: 'Atrasados',
          subtitulo: 'De ayer o antes — necesitan atención',
          icono: PhosphorIconsRegular.warning,
          color: const Color(0xFFC62828),
          pedidos: agrupados[SeccionPedido.atrasados]!,
          mostrarNombreCliente: mostrarNombreCliente,
          onEntregar: onEntregar,
          onCancelar: onCancelar,
        ),
        SeccionPedidos(
          titulo: 'Hoy',
          subtitulo: 'Programados para entregarse hoy',
          icono: PhosphorIconsRegular.calendarDots,
          color: AppColors.primary,
          pedidos: agrupados[SeccionPedido.hoy]!,
          mostrarNombreCliente: mostrarNombreCliente,
          onEntregar: onEntregar,
          onCancelar: onCancelar,
        ),
        SeccionPedidos(
          titulo: 'Próximos',
          subtitulo: 'Mañana en adelante',
          icono: PhosphorIconsRegular.calendarPlus,
          color: const Color(0xFF2563EB),
          pedidos: agrupados[SeccionPedido.proximos]!,
          mostrarNombreCliente: mostrarNombreCliente,
          onEntregar: onEntregar,
          onCancelar: onCancelar,
        ),
        SeccionPedidos(
          titulo: 'Sin fecha programada',
          subtitulo: 'A coordinar con el cliente',
          icono: PhosphorIconsRegular.calendarX,
          color: AppColors.textSecondary,
          pedidos: agrupados[SeccionPedido.sinFecha]!,
          mostrarNombreCliente: mostrarNombreCliente,
          onEntregar: onEntregar,
          onCancelar: onCancelar,
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

    final anchoVentana = MediaQuery.sizeOf(context).width;
    final escritorio = anchoVentana >= Breakpoints.escritorio;

    return Padding(
      padding: EdgeInsets.only(bottom: escritorio ? 28 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PhosphorIcon(icono, color: color, size: escritorio ? 22 : 20),
              const SizedBox(width: 8),
              Text(
                titulo,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: color,
                  fontSize: escritorio ? 18 : null,
                ),
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
              // En escritorio la fila del título se queda corta y flotando
              // en medio de una ventana de 1600px: la línea la cierra y hace
              // que se lea como una separación real entre secciones.
              if (escritorio) ...[
                const SizedBox(width: 14),
                Expanded(
                  child: Container(
                    height: 1,
                    color: color.withValues(alpha: 0.18),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Text(subtitulo, style: theme.textTheme.bodyMedium),
          ),
          SizedBox(height: escritorio ? 14 : 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final tarjetas = pedidos.asMap().entries.map(
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
              );

              if (anchoVentana < Breakpoints.tablet) {
                return Column(children: tarjetas.toList());
              }

              // Desde 600 px la grilla se JUSTIFICA en todos los anchos, no
              // solo en escritorio: con tarjetas de 380 px fijos, una tablet
              // de 820 px entraba dos y dejaba ~40 px muertos a la derecha.
              // Repartir ese sobrante entre las columnas que sí entran es la
              // misma cuenta que ya hacía la rama de escritorio.
              return Wrap(
                spacing: _separacionGrilla,
                runSpacing: 0,
                children: tarjetas
                    .map(
                      (t) => SizedBox(
                        width: anchoTarjetaPedido(constraints.maxWidth),
                        child: t,
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Separación entre tarjetas de pedido en la grilla justificada.
const double _separacionGrilla = 14;

/// Ancho objetivo de una tarjeta de pedido. Es el que se venía usando fijo;
/// ahora es solo la referencia para decidir CUÁNTAS columnas entran.
const double _anchoObjetivoTarjeta = 380;

/// Cuánto debe medir cada tarjeta para que [disponible] quede repartido
/// entero entre las columnas que entran, sin franja muerta al final.
/// Lo usan la lista por secciones y la cola "Por confirmar" de Pedidos, para
/// que las dos dibujen exactamente la misma retícula.
double anchoTarjetaPedido(double disponible) {
  final columnas =
      ((disponible + _separacionGrilla) /
              (_anchoObjetivoTarjeta + _separacionGrilla))
          .floor()
          .clamp(1, 4);
  return (disponible - _separacionGrilla * (columnas - 1)) / columnas;
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
        PhosphorIconsRegular.hourglassHigh,
      );
    case 'RECHAZADO':
      return const _EstadoPedidoInfo(
        'Rechazado',
        Color(0xFFC62828),
        PhosphorIconsFill.xCircle,
      );
    case 'CANCELADO':
      return const _EstadoPedidoInfo(
        'Cancelado',
        Color(0xFF6D4C41),
        PhosphorIconsRegular.prohibit,
      );
    case 'ENTREGADO':
      return pedido.esDeuda
          ? const _EstadoPedidoInfo(
              'Entregado · Deuda',
              Color(0xFFC62828),
              PhosphorIconsRegular.wallet,
            )
          : const _EstadoPedidoInfo(
              'Entregado · Pagado',
              Color(0xFF2E7D32),
              PhosphorIconsFill.checkCircle,
            );
    default:
      return const _EstadoPedidoInfo(
        'Pendiente a entrega',
        Color(0xFF2563EB),
        PhosphorIconsRegular.calendarCheck,
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

  /// Presente en la vista del propio cliente (cancela su propio pedido) o
  /// en la de personal (cancela cualquier pedido de su tienda) — solo se
  /// muestra si el pedido todavía se puede cancelar (SOLICITADO o
  /// PENDIENTE, no si ya fue entregado).
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
                    child: PhosphorIcon(
                      pedido.tipoPedido == 'PAQUETES'
                          ? PhosphorIconsRegular.package
                          : PhosphorIconsRegular.forkKnife,
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
                            PhosphorIcon(
                              pedido.fechaEntrega != null
                                  ? PhosphorIconsRegular.clock
                                  : PhosphorIconsRegular.calendarX,
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
                        PhosphorIcon(
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
              NotaPedido(pedido: pedido),
              InfoAuditoriaPedido(pedido: pedido),
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
              // Entregar y Cancelar: apilados a lo ancho solo en un celular
              // angosto (dedo grande, pantalla de 390 px). Desde 600 px van
              // en una sola fila — ahí el problema no es el ancho sino el
              // alto: dos botones full-width uno debajo del otro estiran
              // cada tarjeta ~90 px de más y dejan la mitad de pedidos a la
              // vista de un golpe.
              if (mostrarAccionEntregar || mostrarAccionCancelar) ...[
                const SizedBox(height: 10),
                Builder(
                  builder: (context) {
                    final botonEntregar = OutlinedButton.icon(
                      onPressed: onEntregar,
                      icon: const PhosphorIcon(
                        PhosphorIconsRegular.truck,
                        size: 18,
                      ),
                      label: const Text('Marcar entregado'),
                    );
                    final botonCancelar = OutlinedButton.icon(
                      onPressed: onCancelar,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFC62828),
                      ),
                      icon: const PhosphorIcon(PhosphorIconsBold.x, size: 18),
                      label: const Text('Cancelar pedido'),
                    );

                    final cabenEnFila =
                        MediaQuery.sizeOf(context).width >= Breakpoints.tablet;

                    if (cabenEnFila &&
                        mostrarAccionEntregar &&
                        mostrarAccionCancelar) {
                      return Row(
                        children: [
                          Expanded(child: botonEntregar),
                          const SizedBox(width: 10),
                          Expanded(child: botonCancelar),
                        ],
                      );
                    }

                    return Column(
                      children: [
                        if (mostrarAccionEntregar)
                          SizedBox(
                            width: double.infinity,
                            child: botonEntregar,
                          ),
                        if (mostrarAccionEntregar && mostrarAccionCancelar)
                          const SizedBox(height: 10),
                        if (mostrarAccionCancelar)
                          SizedBox(
                            width: double.infinity,
                            child: botonCancelar,
                          ),
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _etiquetaRolAuditoria(String? rol) {
  switch (rol) {
    case 'ADMIN':
      return 'Administrador';
    case 'SUPERADMIN':
      return 'Super administrador';
    case 'TRABAJADOR':
      return 'Trabajador';
    default:
      return rol ?? '';
  }
}

/// "Registrado por" necesita el NOMBRE de quien lo hizo, no solo su rol —
/// [Pedido.vendedor] ya trae el nombre (viene de otro campo, independiente
/// del filtro de auditoría), acá solo se combinan los dos.
String _descripcionRegistro(Pedido pedido) {
  if (pedido.registradoPorRol == 'CLIENTE') return 'el propio cliente';
  final nombre = pedido.vendedor;
  final rol = _etiquetaRolAuditoria(pedido.registradoPorRol);
  if (nombre == null) return rol;
  return '$nombre ($rol)';
}

/// Nota que dejó el cliente al registrar el pedido — si vino de la página
/// web pública, acá también va su celular de contacto (ver `notaWeb` en
/// publicoController.js). No se muestra nada si el pedido no tiene notas.
class NotaPedido extends StatelessWidget {
  const NotaPedido({super.key, required this.pedido});

  final Pedido pedido;

  @override
  Widget build(BuildContext context) {
    final notas = pedido.notas;
    if (notas == null || notas.trim().isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.secondaryContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PhosphorIcon(
              PhosphorIconsRegular.note,
              size: 15,
              color: AppColors.secondary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                notas,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Quién registró/confirmó/canceló/entregó el pedido — el backend solo
/// llena estos campos si quien pidió la lista es ADMIN o SUPERADMIN (ver
/// pedidosController.js), así que para cualquier otra vista (TRABAJADOR,
/// el propio cliente) todos llegan null y este widget no muestra nada.
class InfoAuditoriaPedido extends StatelessWidget {
  const InfoAuditoriaPedido({super.key, required this.pedido});

  final Pedido pedido;

  @override
  Widget build(BuildContext context) {
    final lineas = <String>[
      if (pedido.registradoPorRol != null)
        'Registrado por: ${_descripcionRegistro(pedido)}',
      if (pedido.aprobadoPor != null) 'Confirmado por: ${pedido.aprobadoPor}',
      if (pedido.canceladoPor != null) 'Cancelado por: ${pedido.canceladoPor}',
      if (pedido.entregadoPor != null) 'Entregado por: ${pedido.entregadoPor}',
    ];
    if (lineas.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: lineas
              .map(
                (l) => Text(
                  l,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}
