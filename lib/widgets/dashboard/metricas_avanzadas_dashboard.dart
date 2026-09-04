import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import '../../models/tienda_resumen_model.dart';
import '../../theme/app_theme.dart';

/// Las tres métricas "de tendencia" del tablero: a qué hora se vende, cómo
/// viene el mes contra el anterior, y cuántos clientes nuevos entraron esta
/// semana. Todas salen del MISMO `GET /tiendas/:id/resumen` que el tablero ya
/// pedía — no hay ninguna petición extra detrás de ninguna.
///
/// Vive en su propio archivo (y no dentro de `dashboard_page.dart`, que ya
/// pasa las 2200 líneas) porque es un bloque autocontenido: recibe el
/// resumen y no toca nada del estado de la página.
class MetricasAvanzadasDashboard extends StatelessWidget {
  const MetricasAvanzadasDashboard({
    super.key,
    required this.resumen,
    required this.etiquetaDia,
    this.enFila = false,
    this.altoGrafico = 200,
    this.detallado = false,
  });

  final TiendaResumen resumen;

  /// "hoy" o "el 12 sep" — el mismo texto que usan las tarjetas del día
  /// arriba, para que nadie lea "ventas por hora" pensando en hoy cuando
  /// está mirando el martes pasado.
  final String etiquetaDia;

  /// true en tablet/escritorio: el comparativo mensual y los clientes nuevos
  /// van uno al lado del otro en vez de apilados.
  final bool enFila;

  /// Alto del área del gráfico por hora. 200 en celular, 280+ en escritorio.
  final double altoGrafico;

  /// Agrega eje de valores y guías horizontales al gráfico por hora — solo
  /// tiene sentido con [altoGrafico] grande y ancho de escritorio.
  final bool detallado;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final tarjetas = <Widget>[
      _TarjetaComparativoMensual(comparativo: resumen.comparativoMensual),
      _TarjetaClientesNuevosSemana(datos: resumen.clientesNuevosSemana),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'A qué hora se vende ($etiquetaDia)',
          style: theme.textTheme.titleMedium,
        ).animate().fadeIn(delay: 440.ms, duration: 300.ms),
        const SizedBox(height: 12),
        _GraficoVentasPorHora(
              serie: resumen.ventasPorHora,
              alto: altoGrafico,
              detallado: detallado,
            )
            .animate()
            .fadeIn(delay: 480.ms, duration: 400.ms)
            .moveY(begin: 16, end: 0)
            .flipH(begin: 0.1, end: 0, duration: 350.ms),
        const SizedBox(height: 24),
        if (enFila)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 2, child: tarjetas[0]),
                const SizedBox(width: 16),
                Expanded(child: tarjetas[1]),
              ],
            ),
          )
        else ...[
          tarjetas[0],
          const SizedBox(height: 16),
          tarjetas[1],
        ],
      ],
    );
  }
}

/// Barras de las 24 horas del día mostrado. El backend siempre manda las 24
/// (rellena con 0 las que no vendieron), así que la silueta del día se lee
/// completa: no hay huecos que confundan "no vendí" con "no hay dato".
class _GraficoVentasPorHora extends StatelessWidget {
  const _GraficoVentasPorHora({
    required this.serie,
    this.alto = 200,
    this.detallado = false,
  });

  final List<VentaPorHora> serie;
  final double alto;
  final bool detallado;

  /// "14h" — etiqueta corta, porque a 24 barras no entra nada más largo.
  String _etiquetaHora(int hora) => '${hora}h';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (serie.isEmpty) {
      return _MarcoTarjeta(
        alto: alto,
        child: Center(
          child: Text(
            'Sin datos de ventas por hora.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }

    final maximo = serie.fold<double>(
      0,
      (acc, v) => v.total > acc ? v.total : acc,
    );
    final sinVentas = maximo <= 0;
    final techo = sinVentas ? 10.0 : maximo * 1.25;

    // La hora con más ventas se pinta en color de marca; el resto en bronce
    // apagado — de un vistazo se ve cuál es la hora punta del día.
    var horaPunta = -1;
    for (final v in serie) {
      if (v.total > 0 && (horaPunta < 0 || v.total > serie[horaPunta].total)) {
        horaPunta = v.hora;
      }
    }

    final grafico = Container(
      height: alto,
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
      color: AppColors.surface,
      child: BarChart(
        BarChartData(
          maxY: techo,
          alignment: BarChartAlignment.spaceBetween,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final dato = serie[group.x];
                return BarTooltipItem(
                  '${_etiquetaHora(dato.hora)}\n'
                  'S/ ${dato.total.toStringAsFixed(2)}\n'
                  '${dato.cantidad} pedido(s)',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: detallado,
                reservedSize: 46,
                getTitlesWidget: (value, meta) => Text(
                  'S/ ${value.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final indice = value.toInt();
                  if (indice < 0 || indice >= serie.length) {
                    return const SizedBox.shrink();
                  }
                  // 24 etiquetas no entran ni en escritorio: se rotula cada
                  // 3 horas en pantalla ancha y cada 6 en celular.
                  final paso = detallado ? 3 : 6;
                  if (serie[indice].hora % paso != 0) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _etiquetaHora(serie[indice].hora),
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          gridData: FlGridData(
            show: detallado,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) => FlLine(
              color: AppColors.surfaceMuted,
              strokeWidth: 1,
              dashArray: const [4, 6],
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: serie
              .map(
                (v) => BarChartGroupData(
                  x: v.hora,
                  barRods: [
                    BarChartRodData(
                      toY: v.total,
                      color: v.hora == horaPunta
                          ? AppColors.primary
                          : AppColors.secondary.withValues(alpha: 0.55),
                      width: detallado ? 14 : 7,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4),
                      ),
                    ),
                  ],
                ),
              )
              .toList(),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.surfaceMuted, width: 1.2),
              borderRadius: BorderRadius.circular(22),
            ),
            child: grafico,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          sinVentas
              ? 'Todavía no hay entregas cobradas en este día.'
              : 'Solo pedidos ya entregados. La hora punta va resaltada.',
          style: theme.textTheme.bodyMedium?.copyWith(fontSize: 11.5),
        ),
      ],
    );
  }
}

/// Cómo viene el mes contra el anterior. La comparación es contra el MISMO
/// tramo de días del mes pasado (no el mes completo): comparar 5 días de
/// setiembre contra los 30 de agosto siempre marcaría una caída inventada.
class _TarjetaComparativoMensual extends StatelessWidget {
  const _TarjetaComparativoMensual({required this.comparativo});

  final ComparativoMensual comparativo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final variacion = comparativo.variacionPorcentual;
    final nombreMes = DateFormat('MMMM', 'es').format(DateTime.now());
    final nombreMesAnterior = DateFormat(
      'MMMM',
      'es',
    ).format(DateTime(DateTime.now().year, DateTime.now().month - 1));

    return _MarcoTarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.compare_arrows_rounded,
                size: 20,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Este mes contra el pasado',
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _DatoComparativo(
                  etiqueta: 'Va de $nombreMes',
                  valor: 'S/ ${comparativo.mesActual.total.toStringAsFixed(2)}',
                  detalle: '${comparativo.mesActual.pedidos} pedido(s)',
                  destacado: true,
                ),
              ),
              Expanded(
                child: _DatoComparativo(
                  etiqueta: 'A esta altura de $nombreMesAnterior',
                  valor:
                      'S/ ${comparativo.mesAnteriorMismoTramo.total.toStringAsFixed(2)}',
                  detalle:
                      '${comparativo.mesAnteriorMismoTramo.pedidos} pedido(s)',
                ),
              ),
              Expanded(
                child: _DatoComparativo(
                  etiqueta: '$nombreMesAnterior completo',
                  valor:
                      'S/ ${comparativo.mesAnteriorCompleto.total.toStringAsFixed(2)}',
                  detalle:
                      '${comparativo.mesAnteriorCompleto.pedidos} pedido(s)',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ChipTendencia(
            etiqueta: 'vs. los mismos días del mes pasado',
            variacion: variacion,
          ),
        ],
      ),
    ).animate().fadeIn(delay: 520.ms, duration: 320.ms);
  }
}

/// Clientes que se registraron esta semana. Rotulada explícitamente como
/// "todo el negocio": `Clientes` no tiene tienda asociada, así que este
/// número NO es de la tienda que se está mirando arriba.
class _TarjetaClientesNuevosSemana extends StatelessWidget {
  const _TarjetaClientesNuevosSemana({required this.datos});

  final ClientesNuevosSemana datos;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final desde = DateFormat('d MMM', 'es').format(datos.inicioSemana);

    return _MarcoTarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.person_add_alt_1_rounded,
                size: 20,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Clientes nuevos',
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '${datos.cantidad}',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            datos.cantidad == 1
                ? '1 cliente desde el lunes $desde'
                : 'desde el lunes $desde',
            style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
          ),
          if (datos.esGlobal) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.secondary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.storefront_rounded,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Todo el negocio, no solo esta tienda',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    ).animate().fadeIn(delay: 560.ms, duration: 320.ms);
  }
}

/// La misma caja crema con borde suave que usan los paneles del tablero —
/// acá aparte para no repetirla en cada tarjeta de este archivo.
class _MarcoTarjeta extends StatelessWidget {
  const _MarcoTarjeta({required this.child, this.alto});

  final Widget child;
  final double? alto;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: alto,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.surfaceMuted, width: 1.2),
      ),
      child: child,
    );
  }
}

/// Una cifra del comparativo mensual (valor grande + detalle + etiqueta),
/// mismo lenguaje visual que los datos del panel "Los últimos 7 días".
class _DatoComparativo extends StatelessWidget {
  const _DatoComparativo({
    required this.etiqueta,
    required this.valor,
    this.detalle,
    this.destacado = false,
  });

  final String etiqueta;
  final String valor;
  final String? detalle;

  /// El mes en curso va en color de marca: es la cifra que se está leyendo,
  /// las otras dos son la referencia contra la que se compara.
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          valor,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: destacado ? AppColors.primary : null,
          ),
        ),
        if (detalle != null)
          Text(
            detalle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(fontSize: 11.5),
          ),
        Text(
          etiqueta,
          maxLines: 2,
          style: theme.textTheme.bodyMedium?.copyWith(fontSize: 11.5),
        ),
      ],
    );
  }
}

/// "+18% vs. el mes pasado" en verde / rojo, o un chip apagado cuando no hay
/// contra qué comparar (el mes pasado no vendió nada en ese tramo).
class _ChipTendencia extends StatelessWidget {
  const _ChipTendencia({required this.etiqueta, required this.variacion});

  final String etiqueta;
  final double? variacion;

  @override
  Widget build(BuildContext context) {
    final v = variacion;
    final sinDato = v == null;
    final sube = !sinDato && v >= 0;
    final color = sinDato
        ? AppColors.textSecondary
        : sube
        ? const Color(0xFF2E7D32)
        : const Color(0xFFC62828);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            sinDato
                ? Icons.remove_rounded
                : sube
                ? Icons.trending_up_rounded
                : Icons.trending_down_rounded,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              sinDato
                  ? 'Sin datos $etiqueta'
                  : '${sube ? '+' : ''}${v.toStringAsFixed(0)}% $etiqueta',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
