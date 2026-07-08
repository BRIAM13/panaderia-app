/// Un día dentro de la serie de ventas de los últimos 7 días.
class VentaDiaria {
  const VentaDiaria({
    required this.fecha,
    required this.cantidad,
    required this.total,
  });

  factory VentaDiaria.fromJson(Map<String, dynamic> json) => VentaDiaria(
    fecha: DateTime.parse(json['fecha'] as String),
    cantidad: json['cantidad'] as int,
    total: (json['total'] as num).toDouble(),
  );

  final DateTime fecha;
  final int cantidad;
  final double total;
}

/// Resumen/dashboard de una tienda, tal como lo devuelve
/// `GET /tiendas/:idTienda/resumen` — [cobradoDiaTotal]/[deudaDiaTotal]
/// corresponden al día pedido (hoy por defecto, o el elegido con
/// `?fecha=YYYY-MM-DD`); el resto (pendientes de entrega, deuda TOTAL
/// acumulada) siempre mira el día real de hoy, sin importar qué día se
/// esté navegando arriba.
class TiendaResumen {
  const TiendaResumen({
    required this.fecha,
    required this.cobradoDiaCantidad,
    required this.cobradoDiaTotal,
    required this.deudaDiaCantidad,
    required this.deudaDiaTotal,
    required this.pedidosPorConfirmar,
    required this.pendientesTotal,
    required this.pendientesSinFecha,
    required this.pendientesAtrasados,
    required this.pendientesHoy,
    required this.pendientesProximos,
    required this.deudaCantidad,
    required this.deudaTotal,
    required this.pagosReportados,
    required this.ventasUltimos7Dias,
  });

  factory TiendaResumen.fromJson(Map<String, dynamic> json) {
    final cobradoDia = json['cobradoDia'] as Map<String, dynamic>;
    final deudaDia = json['deudaDia'] as Map<String, dynamic>;
    final pendientes = json['pedidosPendientesEntrega'] as Map<String, dynamic>;
    final deuda = json['deudaTotal'] as Map<String, dynamic>;
    final serie = json['ventasUltimos7Dias'] as List<dynamic>? ?? const [];
    return TiendaResumen(
      fecha: DateTime.parse(json['fecha'] as String),
      cobradoDiaCantidad: cobradoDia['cantidad'] as int,
      cobradoDiaTotal: (cobradoDia['total'] as num).toDouble(),
      deudaDiaCantidad: deudaDia['cantidad'] as int,
      deudaDiaTotal: (deudaDia['total'] as num).toDouble(),
      pedidosPorConfirmar: json['pedidosPorConfirmar'] as int,
      pendientesTotal: pendientes['total'] as int,
      pendientesSinFecha: pendientes['sinFecha'] as int,
      pendientesAtrasados: pendientes['atrasados'] as int,
      pendientesHoy: pendientes['hoy'] as int,
      pendientesProximos: pendientes['proximos'] as int,
      deudaCantidad: deuda['cantidad'] as int,
      deudaTotal: (deuda['total'] as num).toDouble(),
      pagosReportados: json['pagosReportados'] as int,
      ventasUltimos7Dias: serie
          .map((e) => VentaDiaria.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  final DateTime fecha;
  final int cobradoDiaCantidad;
  final double cobradoDiaTotal;
  final int deudaDiaCantidad;
  final double deudaDiaTotal;
  final int pedidosPorConfirmar;
  final int pendientesTotal;
  final int pendientesSinFecha;
  final int pendientesAtrasados;
  final int pendientesHoy;
  final int pendientesProximos;
  final int deudaCantidad;
  final double deudaTotal;
  final int pagosReportados;
  final List<VentaDiaria> ventasUltimos7Dias;
}
