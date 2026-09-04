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

/// Una hora del día dentro de la serie de ventas por hora. El backend
/// SIEMPRE manda las 24 (rellena con 0 las que no tuvieron ventas), y la
/// hora ya viene en hora de Perú, no UTC.
class VentaPorHora {
  const VentaPorHora({
    required this.hora,
    required this.cantidad,
    required this.total,
  });

  factory VentaPorHora.fromJson(Map<String, dynamic> json) => VentaPorHora(
    hora: json['hora'] as int,
    cantidad: json['cantidad'] as int,
    total: (json['total'] as num).toDouble(),
  );

  /// 0-23, en hora de Perú.
  final int hora;
  final int cantidad;
  final double total;
}

/// Un tramo (mes actual, mes anterior completo, o mes anterior hasta el
/// mismo día) dentro de [ComparativoMensual].
class TramoMensual {
  const TramoMensual({required this.total, required this.pedidos});

  factory TramoMensual.fromJson(Map<String, dynamic> json) => TramoMensual(
    total: (json['total'] as num).toDouble(),
    pedidos: json['pedidos'] as int,
  );

  final double total;
  final int pedidos;
}

/// Cómo viene el mes calendario actual contra el anterior. Siempre el mes
/// real actual, sin importar qué día se esté navegando en el tablero — es
/// una métrica de tendencia del negocio, no del día mostrado.
class ComparativoMensual {
  const ComparativoMensual({
    required this.mesActual,
    required this.mesAnteriorCompleto,
    required this.mesAnteriorMismoTramo,
    required this.variacionPorcentual,
  });

  factory ComparativoMensual.fromJson(Map<String, dynamic> json) =>
      ComparativoMensual(
        mesActual: TramoMensual.fromJson(
          json['mesActual'] as Map<String, dynamic>,
        ),
        mesAnteriorCompleto: TramoMensual.fromJson(
          json['mesAnteriorCompleto'] as Map<String, dynamic>,
        ),
        mesAnteriorMismoTramo: TramoMensual.fromJson(
          json['mesAnteriorMismoTramo'] as Map<String, dynamic>,
        ),
        variacionPorcentual: (json['variacionPorcentual'] as num?)?.toDouble(),
      );

  /// Lo que va del mes actual.
  final TramoMensual mesActual;

  /// El mes anterior entero (referencia de "cuánto se hizo en un mes
  /// completo"), no es contra lo que se calcula la variación.
  final TramoMensual mesAnteriorCompleto;

  /// El mes anterior hasta el MISMO día/hora transcurridos — la comparación
  /// justa, y la base de [variacionPorcentual].
  final TramoMensual mesAnteriorMismoTramo;

  /// null cuando el mismo tramo del mes anterior no vendió nada: no hay
  /// contra qué comparar (dividir por cero no da "+∞%").
  final double? variacionPorcentual;
}

/// Clientes que se registraron esta semana (lunes a hoy, hora de Perú).
/// Es de TODO EL NEGOCIO, no de una tienda: `Clientes` no tiene tienda
/// asociada, un mismo cliente compra en cualquiera de ellas.
class ClientesNuevosSemana {
  const ClientesNuevosSemana({
    required this.cantidad,
    required this.inicioSemana,
    required this.esGlobal,
  });

  factory ClientesNuevosSemana.fromJson(Map<String, dynamic> json) =>
      ClientesNuevosSemana(
        cantidad: json['cantidad'] as int,
        inicioSemana: DateTime.parse(json['inicioSemana'] as String),
        esGlobal: json['esGlobal'] as bool? ?? true,
      );

  final int cantidad;

  /// El lunes de la semana en curso.
  final DateTime inicioSemana;

  /// Siempre true por ahora — la UI lo usa para rotular la tarjeta como
  /// "todo el negocio" y que nadie la lea como propia de la tienda abierta.
  final bool esGlobal;
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
    required this.ventasPorHora,
    required this.comparativoMensual,
    required this.clientesNuevosSemana,
  });

  factory TiendaResumen.fromJson(Map<String, dynamic> json) {
    final cobradoDia = json['cobradoDia'] as Map<String, dynamic>;
    final deudaDia = json['deudaDia'] as Map<String, dynamic>;
    final pendientes = json['pedidosPendientesEntrega'] as Map<String, dynamic>;
    final deuda = json['deudaTotal'] as Map<String, dynamic>;
    final serie = json['ventasUltimos7Dias'] as List<dynamic>? ?? const [];
    final serieHoras = json['ventasPorHora'] as List<dynamic>? ?? const [];
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
      ventasPorHora: serieHoras
          .map((e) => VentaPorHora.fromJson(e as Map<String, dynamic>))
          .toList(),
      comparativoMensual: ComparativoMensual.fromJson(
        json['comparativoMensual'] as Map<String, dynamic>,
      ),
      clientesNuevosSemana: ClientesNuevosSemana.fromJson(
        json['clientesNuevosSemana'] as Map<String, dynamic>,
      ),
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

  /// Las 24 horas del día mostrado (el mismo que [fecha]), en hora de Perú.
  final List<VentaPorHora> ventasPorHora;

  /// Mes calendario REAL actual contra el anterior — no sigue el selector
  /// de fecha del tablero, a diferencia de [ventasPorHora].
  final ComparativoMensual comparativoMensual;

  /// Clientes nuevos de la semana en curso, de todo el negocio.
  final ClientesNuevosSemana clientesNuevosSemana;
}
