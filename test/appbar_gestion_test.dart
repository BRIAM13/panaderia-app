import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panaderia_app/widgets/escritorio.dart';
import 'package:panaderia_app/widgets/premium_button.dart';

/// El encabezado de escritorio (`appBarGestion`) mide 72 px fijos y sus
/// acciones son botones con fondo propio. `AppBar` arma sus `actions` con
/// `CrossAxisAlignment.stretch`, así que sin envolverlas les pasa una altura
/// APRETADA de 72 px: el botón se estira de borde a borde de la barra y se
/// ve como un bloque enorme pegado al filo superior (bug reportado en
/// producción sobre "Nuevo pedido"). Estas pruebas fijan las dos mitades del
/// arreglo: la acción conserva su alto natural, y ese alto es el de la
/// variante compacta.
void main() {
  const altoBarra = 72.0;

  Future<void> montarEncabezado(WidgetTester tester, Widget accion) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            appBar: appBarGestion(
              context,
              titulo: 'Pedidos',
              subtitulo: '3 pendientes · 1 por confirmar',
              acciones: [accion],
            ),
            body: const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  testWidgets('la acción del encabezado no se estira al alto de la barra', (
    tester,
  ) async {
    await montarEncabezado(
      tester,
      const PremiumButton(
        label: 'Nuevo pedido',
        icono: Icons.add_shopping_cart_rounded,
        expandido: false,
        compacto: true,
        onPressed: _noOp,
      ),
    );

    final boton = tester.getRect(find.byType(PremiumButton));
    expect(
      boton.height,
      lessThan(altoBarra - 20),
      reason: 'debe quedar aire arriba y abajo, no tocar el borde de la barra',
    );
    expect(
      boton.height,
      inInclusiveRange(32, 48),
      reason: 'alto esperado de la variante compacta',
    );
  });

  testWidgets('la acción queda centrada verticalmente en la barra', (
    tester,
  ) async {
    await montarEncabezado(
      tester,
      const PremiumButton(
        label: 'Agregar método',
        icono: Icons.add_rounded,
        expandido: false,
        compacto: true,
        onPressed: _noOp,
      ),
    );

    final boton = tester.getRect(find.byType(PremiumButton));
    // El aire de arriba y el de abajo tienen que ser prácticamente iguales:
    // si el botón se estira o se desalinea, uno de los dos se va a cero.
    final aireArriba = boton.top;
    final aireAbajo = altoBarra - boton.bottom;
    expect((aireArriba - aireAbajo).abs(), lessThan(1.5));
    expect(aireArriba, greaterThan(10));
  });

  testWidgets('la variante compacta es más baja que la normal', (tester) async {
    await montarEncabezado(
      tester,
      const PremiumButton(
        label: 'Nuevo pedido',
        expandido: false,
        onPressed: _noOp,
      ),
    );
    final alturaNormal = tester.getRect(find.byType(PremiumButton)).height;

    await montarEncabezado(
      tester,
      const PremiumButton(
        label: 'Nuevo pedido',
        expandido: false,
        compacto: true,
        onPressed: _noOp,
      ),
    );
    final alturaCompacta = tester.getRect(find.byType(PremiumButton)).height;

    expect(alturaCompacta, lessThan(alturaNormal));
  });
}

void _noOp() {}
