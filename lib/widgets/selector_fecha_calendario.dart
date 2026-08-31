import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../theme/app_theme.dart';

const _diasSemana = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

/// Calendario propio (no el `showDatePicker` de Material, que no permite
/// decorar días individuales) — solo dentro deja elegir días con ventas
/// registradas, y marca con un aro rojo los que tienen alguna deuda
/// TODAVÍA pendiente, para que el personal identifique de un vistazo qué
/// días revisar.
Future<DateTime?> mostrarSelectorFechaVentas({
  required BuildContext context,
  required DateTime fechaSeleccionada,
  required List<DateTime> fechasHabilitadas,
  required List<DateTime> fechasConDeuda,
}) {
  return showDialog<DateTime>(
    context: context,
    builder: (context) => _DialogoCalendarioVentas(
      fechaSeleccionada: fechaSeleccionada,
      fechasHabilitadas: fechasHabilitadas,
      fechasConDeuda: fechasConDeuda,
    ),
  );
}

bool _mismoDia(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class _DialogoCalendarioVentas extends StatefulWidget {
  const _DialogoCalendarioVentas({
    required this.fechaSeleccionada,
    required this.fechasHabilitadas,
    required this.fechasConDeuda,
  });

  final DateTime fechaSeleccionada;
  final List<DateTime> fechasHabilitadas;
  final List<DateTime> fechasConDeuda;

  @override
  State<_DialogoCalendarioVentas> createState() =>
      _DialogoCalendarioVentasState();
}

class _DialogoCalendarioVentasState extends State<_DialogoCalendarioVentas> {
  late DateTime _mesMostrado = DateTime(
    widget.fechaSeleccionada.year,
    widget.fechaSeleccionada.month,
  );

  bool get _puedeIrAtras {
    if (widget.fechasHabilitadas.isEmpty) return false;
    final primero = widget.fechasHabilitadas.reduce(
      (a, b) => a.isBefore(b) ? a : b,
    );
    return DateTime(
      _mesMostrado.year,
      _mesMostrado.month - 1,
    ).isAfter(DateTime(primero.year, primero.month - 1));
  }

  bool get _puedeIrAdelante {
    final ahora = DateTime.now();
    return DateTime(
      _mesMostrado.year,
      _mesMostrado.month,
    ).isBefore(DateTime(ahora.year, ahora.month));
  }

  void _cambiarMes(int delta) {
    setState(
      () => _mesMostrado = DateTime(
        _mesMostrado.year,
        _mesMostrado.month + delta,
      ),
    );
  }

  bool _habilitado(DateTime dia) =>
      widget.fechasHabilitadas.any((f) => _mismoDia(f, dia));

  bool _conDeuda(DateTime dia) =>
      widget.fechasConDeuda.any((f) => _mismoDia(f, dia));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primerDiaMes = DateTime(_mesMostrado.year, _mesMostrado.month, 1);
    final diasEnMes = DateTime(
      _mesMostrado.year,
      _mesMostrado.month + 1,
      0,
    ).day;
    // weekday: 1=lunes..7=domingo — cuántas celdas vacías van antes del día 1.
    final espaciosVacios = primerDiaMes.weekday - 1;

    return Dialog(
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: _puedeIrAtras ? () => _cambiarMes(-1) : null,
                  icon: const PhosphorIcon(PhosphorIconsBold.caretLeft),
                ),
                Expanded(
                  child: Text(
                    DateFormat(
                      'MMMM yyyy',
                      'es',
                    ).format(_mesMostrado).toUpperCase(),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  onPressed: _puedeIrAdelante ? () => _cambiarMes(1) : null,
                  icon: const PhosphorIcon(PhosphorIconsBold.caretRight),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: _diasSemana
                  .map(
                    (d) => Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 4),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
              ),
              itemCount: espaciosVacios + diasEnMes,
              itemBuilder: (context, index) {
                if (index < espaciosVacios) return const SizedBox.shrink();
                final dia = DateTime(
                  _mesMostrado.year,
                  _mesMostrado.month,
                  index - espaciosVacios + 1,
                );
                final habilitado = _habilitado(dia);
                final conDeuda = _conDeuda(dia);
                final seleccionado = _mismoDia(dia, widget.fechaSeleccionada);

                return Padding(
                  padding: const EdgeInsets.all(2),
                  child: Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: habilitado
                          ? () => Navigator.of(context).pop(dia)
                          : null,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: seleccionado ? AppColors.primary : null,
                          border: conDeuda
                              ? Border.all(
                                  color: seleccionado
                                      ? Colors.white
                                      : const Color(0xFFC62828),
                                  width: 2,
                                )
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${dia.day}',
                          style: TextStyle(
                            fontWeight: seleccionado
                                ? FontWeight.w800
                                : FontWeight.w500,
                            color: seleccionado
                                ? Colors.white
                                : habilitado
                                ? null
                                : AppColors.textSecondary.withValues(
                                    alpha: 0.35,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFC62828),
                      width: 2,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Con deuda pendiente',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      ),
    );
  }
}
