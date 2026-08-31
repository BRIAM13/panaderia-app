import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:panaderia_app/theme/app_theme.dart';
import 'package:panaderia_app/widgets/selector_desplegable.dart';

/// Pruebas del selector desplegable con menú propio (overlay).
///
/// Lo que importa verificar acá no es el look (eso se mira en pantalla), sino
/// que el overlay hecho a mano REALMENTE funcione: que se abra, que muestre
/// las opciones, que elegir una dispare `onChanged`, que se cierre solo, que
/// no deje entradas colgadas al destruirse, y que el `validator` siga
/// integrado con el `Form` como cualquier `TextFormField`.

const _tiendas = ['Panadería Centro', 'Horneados Norte', 'Hamburguesas Sur'];

Widget _app(Widget hijo) => MaterialApp(
  theme: buildAppTheme(),
  home: Scaffold(
    body: Center(child: SizedBox(width: 320, child: hijo)),
  ),
);

void main() {
  testWidgets('abre el menú y muestra todas las opciones', (tester) async {
    await tester.pumpWidget(
      _app(
        SelectorDesplegable<String>(
          valor: _tiendas.first,
          opciones: _tiendas,
          etiqueta: (t) => t,
          label: 'Tienda',
          icono: Icons.storefront,
          onChanged: (_) {},
        ),
      ),
    );

    // Cerrado: solo se ve el valor actual.
    expect(find.text('Horneados Norte'), findsNothing);

    await tester.tap(find.text('Panadería Centro'));
    await tester.pumpAndSettle();

    // Abierto: las tres opciones están en el overlay (la seleccionada
    // aparece dos veces: en el campo y en el menú).
    expect(find.text('Panadería Centro'), findsNWidgets(2));
    expect(find.text('Horneados Norte'), findsOneWidget);
    expect(find.text('Hamburguesas Sur'), findsOneWidget);
  });

  testWidgets('elegir una opción dispara onChanged y cierra el menú', (
    tester,
  ) async {
    String? elegida;

    await tester.pumpWidget(
      _app(
        SelectorDesplegable<String>(
          valor: _tiendas.first,
          opciones: _tiendas,
          etiqueta: (t) => t,
          label: 'Tienda',
          onChanged: (v) => elegida = v,
        ),
      ),
    );

    await tester.tap(find.text('Panadería Centro'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Hamburguesas Sur'));
    await tester.pumpAndSettle();

    expect(elegida, 'Hamburguesas Sur');
    // El menú se fue: 'Horneados Norte' solo vivía dentro del overlay.
    expect(find.text('Horneados Norte'), findsNothing);
  });

  testWidgets('tocar afuera cierra el menú sin cambiar el valor', (
    tester,
  ) async {
    var llamadas = 0;

    await tester.pumpWidget(
      _app(
        SelectorDesplegable<String>(
          valor: _tiendas.first,
          opciones: _tiendas,
          etiqueta: (t) => t,
          label: 'Tienda',
          onChanged: (_) => llamadas++,
        ),
      ),
    );

    await tester.tap(find.text('Panadería Centro'));
    await tester.pumpAndSettle();
    expect(find.text('Horneados Norte'), findsOneWidget);

    // Esquina superior izquierda: fuera de la tarjeta del menú.
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(find.text('Horneados Norte'), findsNothing);
    expect(llamadas, 0);
  });

  testWidgets('Escape cierra el menú', (tester) async {
    await tester.pumpWidget(
      _app(
        SelectorDesplegable<String>(
          valor: _tiendas.first,
          opciones: _tiendas,
          etiqueta: (t) => t,
          label: 'Tienda',
          onChanged: (_) {},
        ),
      ),
    );

    await tester.tap(find.text('Panadería Centro'));
    await tester.pumpAndSettle();
    expect(find.text('Horneados Norte'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Horneados Norte'), findsNothing);
  });

  testWidgets('el validator se integra con el Form y el error se limpia al '
      'elegir', (tester) async {
    final clave = GlobalKey<FormState>();
    String? valor;

    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) => Form(
            key: clave,
            child: SelectorDesplegable<String>(
              valor: valor,
              opciones: _tiendas,
              etiqueta: (t) => t,
              label: 'Tienda',
              validator: (v) => v == null ? 'Selecciona una tienda' : null,
              onChanged: (v) => setState(() => valor = v),
            ),
          ),
        ),
      ),
    );

    expect(clave.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Selecciona una tienda'), findsOneWidget);

    // Sin valor todavía: se abre tocando la caja del campo.
    await tester.tap(find.byType(InputDecorator));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Horneados Norte'));
    await tester.pumpAndSettle();

    expect(valor, 'Horneados Norte');
    expect(clave.currentState!.validate(), isTrue);
    await tester.pump();
    expect(find.text('Selecciona una tienda'), findsNothing);
  });

  testWidgets('no deja el overlay huérfano si el widget muere abierto', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        SelectorDesplegable<String>(
          valor: _tiendas.first,
          opciones: _tiendas,
          etiqueta: (t) => t,
          label: 'Tienda',
          onChanged: (_) {},
        ),
      ),
    );

    await tester.tap(find.text('Panadería Centro'));
    await tester.pumpAndSettle();
    expect(find.text('Horneados Norte'), findsOneWidget);

    // Se reemplaza todo el árbol con el menú todavía abierto.
    await tester.pumpWidget(_app(const Text('otra pantalla')));
    await tester.pumpAndSettle();

    expect(find.text('Horneados Norte'), findsNothing);
    expect(find.text('otra pantalla'), findsOneWidget);
  });

  testWidgets('abre hacia arriba cuando el campo está pegado al borde '
      'inferior', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: 320,
              child: SelectorDesplegable<String>(
                valor: _tiendas.first,
                opciones: _tiendas,
                etiqueta: (t) => t,
                label: 'Tienda',
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    final campo = tester.getRect(find.byType(InputDecorator));
    await tester.tap(find.text('Panadería Centro'));
    await tester.pumpAndSettle();

    // La tarjeta del menú tiene que quedar ARRIBA del campo, no debajo del
    // borde inferior de la ventana.
    final menu = tester.getRect(find.text('Horneados Norte'));
    expect(menu.bottom, lessThanOrEqualTo(campo.top));
  });
}
