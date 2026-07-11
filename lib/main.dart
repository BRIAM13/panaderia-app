import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'pages/auth/login_page.dart';
import 'pages/splash/splash_page.dart';
import 'services/api_client.dart';
import 'services/secure_storage_service.dart';
import 'theme/app_theme.dart';
import 'widgets/page_transitions.dart';

/// Referencia global al Navigator raíz — necesaria para poder forzar una
/// navegación (cerrar sesión y volver al login) desde `ApiClient`, que
/// puede reaccionar a una respuesta del backend desde cualquier pantalla,
/// no solo desde la que originó la petición.
final navigatorKey = GlobalKey<NavigatorState>();

bool _manejandoRolCambiado = false;

/// Se dispara cuando el backend detecta que el rol del usuario cambió
/// mientras tenía la sesión abierta (ver `ApiClient.onRolCambiado` y
/// `authMiddleware.js` → tipo 'ROL_CAMBIADO'). Cierra la sesión guardada y
/// manda al usuario de vuelta al login con un aviso, sin importar en qué
/// pantalla estuviera — así la app se recarga limpia con las pantallas que
/// le corresponden a su rol nuevo.
Future<void> _manejarRolCambiado(String mensaje) async {
  if (_manejandoRolCambiado) return;
  _manejandoRolCambiado = true;
  // Solo borra los tokens (que ya no sirven) — conserva el usuario
  // recordado y la preferencia de biometría, no fue un cierre de sesión
  // decidido por el usuario.
  await SecureStorageService().limpiarSesion();
  navigatorKey.currentState?.pushAndRemoveUntil(
    SlideUpFadeRoute(builder: (_) => LoginPage(mensajeInicial: mensaje)),
    (route) => false,
  );
  _manejandoRolCambiado = false;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Necesario para que DateFormat con nombres de mes/día ('EEEE', 'MMMM')
  // funcione en español (ej. resumen de pedido: "viernes 4 de julio").
  await initializeDateFormatting('es');
  await _inicializarFirebaseSiAplica();
  await _inicializarAdMobSiAplica();
  ApiClient.onRolCambiado = _manejarRolCambiado;
  runApp(const PanaderiaApp());
}

/// Firebase (usado para notificaciones push) solo tiene configuración nativa
/// para Android en este proyecto por ahora — en web/escritorio no se
/// inicializa.
Future<void> _inicializarFirebaseSiAplica() async {
  if (kIsWeb) return;
  if (!Platform.isAndroid) return;

  try {
    await Firebase.initializeApp();
  } catch (_) {
    // No bloquea el arranque de la app si Firebase no pudo inicializarse.
  }
}

/// Dispositivos marcados como "de prueba" ante AdMob: aunque el código use
/// el ID de bloque de anuncios REAL, estos dispositivos siempre reciben un
/// anuncio de prueba (claramente marcado como tal) en vez de uno real —
/// así se puede seguir probando la app sin arriesgar la cuenta por "tráfico
/// inválido" (Google suspende cuentas que detectan clics/vistas repetidas
/// del propio dueño sobre sus anuncios reales). El ID de cada dispositivo
/// aparece en el logcat la primera vez que intenta cargar un anuncio real
/// (buscar "Use RequestConfiguration.Builder().setTestDeviceIds(...)").
const _dispositivosDePrueba = <String>[
  '75ECA870F184FC2776473AF1AFB4B0CF', // Samsung Galaxy S24 Ultra (Briam, dispositivo de pruebas)
];

/// google_mobile_ads solo tiene implementación para Android e iOS; en web
/// o escritorio simplemente no se inicializa (el banner ya lo maneja).
Future<void> _inicializarAdMobSiAplica() async {
  if (kIsWeb) return;
  if (!(Platform.isAndroid || Platform.isIOS)) return;

  try {
    await MobileAds.instance.initialize();
    await MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(testDeviceIds: _dispositivosDePrueba),
    );
  } catch (_) {
    // No bloquea el arranque de la app si AdMob no pudo inicializarse.
  }
}

class PanaderiaApp extends StatelessWidget {
  const PanaderiaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Corporación Ronceros',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: buildAppTheme(),
      // Respeta la fuente grande del sistema (accesibilidad) pero la limita
      // a 1.25x para que nunca desborde botones ni formularios. Ojo:
      // encadenar `.clamp()` sobre el TextScaler del sistema (en vez de
      // sobre un número) revienta con "maxScale > minScale: is not true" en
      // Android 14+ (escalado de fuente no lineal) cuando el usuario tiene
      // configurado un tamaño de letra grande — el TextScaler del sistema ya
      // viene con sus propios límites internos, y el segundo `.clamp()`
      // puede terminar con un mínimo mayor que el máximo. Por eso acá se
      // deriva un factor numérico simple (con un tamaño de referencia) y se
      // aplica un clamp normal sobre ese número, nunca sobre el TextScaler.
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        const tamanoReferencia = 100.0;
        final factorActual =
            mediaQuery.textScaler.scale(tamanoReferencia) / tamanoReferencia;
        final factorSeguro = factorActual.clamp(1.0, 1.25);
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: TextScaler.linear(factorSeguro),
          ),
          child: child!,
        );
      },
      home: const SplashPage(),
    );
  }
}
