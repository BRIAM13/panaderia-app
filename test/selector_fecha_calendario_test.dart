import 'package:flutter_test/flutter_test.dart';
import 'package:panaderia_app/widgets/selector_fecha_calendario.dart';

/// Regla de negocio del calendario de ventas, aislada de la UI: qué días se
/// pueden tocar. El caso delicado es el de HOY, que se pidió explícitamente
/// que siempre sea elegible aunque todavía no haya ninguna venta — pero solo
/// mientras sea hoy, sin quedarse habilitado el día siguiente.
void main() {
  group('diaHabilitadoEnCalendario', () {
    final hoy = DateTime(2026, 9, 2, 14, 30);

    test('un día que está en la lista de fechas con ventas se puede elegir', () {
      expect(
        diaHabilitadoEnCalendario(
          dia: DateTime(2026, 8, 30),
          fechasHabilitadas: [DateTime(2026, 8, 30), DateTime(2026, 8, 28)],
          hoy: hoy,
        ),
        isTrue,
      );
    });

    test('un día pasado SIN ventas no se puede elegir', () {
      expect(
        diaHabilitadoEnCalendario(
          dia: DateTime(2026, 8, 29),
          fechasHabilitadas: [DateTime(2026, 8, 30), DateTime(2026, 8, 28)],
          hoy: hoy,
        ),
        isFalse,
      );
    });

    test('HOY siempre se puede elegir, aunque no tenga ninguna venta', () {
      expect(
        diaHabilitadoEnCalendario(
          dia: DateTime(2026, 9, 2),
          fechasHabilitadas: const [],
          hoy: hoy,
        ),
        isTrue,
      );
    });

    test('la hora del día no influye: se compara solo el día calendario', () {
      expect(
        diaHabilitadoEnCalendario(
          dia: DateTime(2026, 9, 2, 23, 59),
          fechasHabilitadas: const [],
          hoy: DateTime(2026, 9, 2, 0, 1),
        ),
        isTrue,
      );
    });

    test(
      'un día que fue "hoy" y no tuvo ventas se apaga apenas pasa a ser ayer',
      () {
        // Ayer (1 de setiembre) estuvo habilitado por ser el día en curso;
        // hoy ya es 2 de setiembre y ayer no registró ninguna venta, así que
        // deja de ser elegible. El nuevo hoy sí lo es.
        final ayerSinVentas = DateTime(2026, 9, 1);
        expect(
          diaHabilitadoEnCalendario(
            dia: ayerSinVentas,
            fechasHabilitadas: const [],
            hoy: ayerSinVentas,
          ),
          isTrue,
          reason: 'mientras era el día en curso sí se podía elegir',
        );
        expect(
          diaHabilitadoEnCalendario(
            dia: ayerSinVentas,
            fechasHabilitadas: const [],
            hoy: hoy,
          ),
          isFalse,
          reason: 'al día siguiente ya no, porque nunca tuvo ventas',
        );
        expect(
          diaHabilitadoEnCalendario(
            dia: DateTime(2026, 9, 2),
            fechasHabilitadas: const [],
            hoy: hoy,
          ),
          isTrue,
          reason: 'siempre debe haber forma de volver al día de hoy',
        );
      },
    );

    test('cruzar de mes o de año no confunde días con el mismo número', () {
      expect(
        diaHabilitadoEnCalendario(
          dia: DateTime(2025, 9, 2),
          fechasHabilitadas: const [],
          hoy: hoy,
        ),
        isFalse,
      );
      expect(
        diaHabilitadoEnCalendario(
          dia: DateTime(2026, 8, 2),
          fechasHabilitadas: const [],
          hoy: hoy,
        ),
        isFalse,
      );
    });
  });
}
