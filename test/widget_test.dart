import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:panaderia_app/models/usuario_sesion.dart';
import 'package:panaderia_app/pages/hub/home_page.dart';
import 'package:panaderia_app/theme/app_theme.dart';

// Nota: LoginPage y SplashPage dependen de flutter_secure_storage y
// local_auth, cuyos canales de plataforma no existen en el harness de
// `flutter test` (no es un dispositivo real ni un navegador). Por eso
// HomePage se prueba aquí de forma aislada (no depende de esos plugins),
// y el flujo de login/biometría se verifica con un build real en navegador
// (ver flujo documentado para la Fase 2/3).
//
// Tampoco se usa pumpAndSettle(): el AdBanner de la vista Cliente tiene una
// animación de pulso infinita (a propósito), y pumpAndSettle nunca
// terminaría de asentar. Se usan pumps con duración fija, un viewport de
// prueba lo bastante alto para el contenido de cada pantalla, y un
// addTearDown que desmonta el árbol al final para liberar los
// temporizadores del ciclo de animación infinito antes del cierre del test.

const _clienteDemo = UsuarioSesion(
  idUsuario: 1,
  idPersona: 1,
  nombreUsuario: 'cliente.demo',
  rol: 'CLIENTE',
  requiereCambioPassword: false,
  roles: ['CLIENTE'],
  esCliente: true,
  esTrabajador: false,
  esHibrido: false,
);

const _trabajadorDemo = UsuarioSesion(
  idUsuario: 2,
  idPersona: 2,
  nombreUsuario: 'trabajador.demo',
  rol: 'TRABAJADOR',
  requiereCambioPassword: false,
  roles: ['TRABAJADOR'],
  esCliente: false,
  esTrabajador: true,
  esHibrido: false,
  cargoTrabajador: 'Vendedor',
);

const _hibridoDemo = UsuarioSesion(
  idUsuario: 5,
  idPersona: 5,
  nombreUsuario: 'hibrido.demo',
  rol: 'TRABAJADOR',
  requiereCambioPassword: false,
  roles: ['CLIENTE', 'TRABAJADOR'],
  esCliente: true,
  esTrabajador: true,
  esHibrido: true,
  cargoTrabajador: 'Vendedor',
);

Widget _envolver(Widget home) {
  return MaterialApp(theme: buildAppTheme(), home: home);
}

// Dos pumps en vez de uno: los `.animate(delay: ...)` escalonados (ej. el
// drawer) arman su Timer de retraso recién cuando el reloj falso avanza —
// un solo pump no le da chance de completar el ticker que ese Timer
// arranca a mitad de camino, y el binding revienta con "Timer is still
// pending" al desmontar. Un segundo pump vacía ese trabajo pendiente.
Future<void> _asentar(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pump(const Duration(milliseconds: 700));
}

/// Monta [home], fija un viewport alto y garantiza que el árbol se desmonte
/// al final del test, para no dejar pendiente el temporizador del pulso
/// infinito del AdBanner.
Future<void> _montar(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(420, 1100);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));

  await tester.pumpWidget(_envolver(home));
  await _asentar(tester);
}

void main() {
  testWidgets(
    'El personal (Trabajador) ya no ve el grid fijo de tiendas — su '
    'pantalla principal ahora es el Dashboard de su tienda',
    (WidgetTester tester) async {
      // DashboardPage pide datos reales por HTTP en initState, que no hay
      // en el harness de `flutter test` — solo se verifica que el grid fijo
      // "Elige tu tienda" (reemplazado por el Dashboard para todo el
      // personal, no solo Admin/Superadmin) ya no aparece, sin asumir si la
      // llamada de red resultó en carga, error o datos.
      await _montar(tester, const HomePage(usuario: _trabajadorDemo));

      expect(find.text('Elige tu tienda'), findsNothing);
      expect(find.text('Pastelería'), findsNothing);
    },
  );

  testWidgets(
    'La vista Cliente ya no muestra el hub de tiendas como pantalla principal',
    (WidgetTester tester) async {
      // MisPedidosPendientesView pide datos reales por HTTP en initState,
      // que no hay en el harness de `flutter test` — solo se verifica que
      // el hub de tiendas de la vista Trabajador ya no aparece aquí, sin
      // asumir si la llamada de red resultó en carga, error o datos.
      await _montar(tester, const HomePage(usuario: _clienteDemo));

      expect(find.text('Elige tu tienda'), findsNothing);
      expect(find.text('Pastelería'), findsNothing);
    },
  );

  testWidgets('Un cliente puro no ve la sección de MENÚ en el drawer', (
    WidgetTester tester,
  ) async {
    await _montar(tester, const HomePage(usuario: _clienteDemo));

    await tester.tap(find.byIcon(Icons.menu));
    await _asentar(tester);

    expect(find.text('MENÚ'), findsNothing);
    expect(find.text('Mis pedidos'), findsOneWidget);
  });

  testWidgets(
    'Un usuario híbrido sigue viendo su Dashboard de gestión como pantalla '
    'principal, y ve AMBAS secciones (MENÚ y MI CUENTA) en el drawer',
    (WidgetTester tester) async {
      await _montar(tester, const HomePage(usuario: _hibridoDemo));

      await tester.tap(find.byIcon(Icons.menu));
      await _asentar(tester);

      expect(find.text('Cambiar de vista'), findsNothing);
      expect(find.text('MENÚ'), findsOneWidget);
      expect(find.text('MI CUENTA'), findsOneWidget);
      // "Hacer pedido" ya no vive en el drawer — es el FAB de la propia
      // pantalla "Mis pedidos" (ver MisPedidosPendientesPage).
      expect(find.text('Mis pedidos'), findsOneWidget);
      expect(find.text('Mis deudas'), findsOneWidget);
    },
  );
}
