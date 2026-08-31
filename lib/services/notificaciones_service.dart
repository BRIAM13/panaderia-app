import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:ui' show Color;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../main.dart' show navigatorKey;
import '../models/tienda_model.dart';
import '../pages/hamburguesas/deudas_page.dart';
import '../pages/hamburguesas/pedidos_page.dart';
import '../pages/hub/mis_deudas_page.dart';
import '../pages/hub/mis_pedidos_pendientes_view.dart';
import '../widgets/page_transitions.dart';
import 'api_client.dart';
import 'secure_storage_service.dart';
import 'tiendas_service.dart';

const _canalId = 'notificaciones_generales';
const _canalNombre = 'Notificaciones';

/// Tipos de notificación (ver `datos.tipo` en pushService.js del backend)
/// que corresponden a un cambio real en algún pedido — cuando llega una de
/// estas, las vistas de pedidos abiertas deben recargarse solas, sin
/// esperar a que el usuario deslice para refrescar a mano.
const _tiposEventoPedido = {
  'NUEVO_PEDIDO',
  'PEDIDO_SOLICITADO',
  'PEDIDO_APROBADO',
  'PEDIDO_RECHAZADO',
  'PEDIDO_ENTREGADO',
  'PEDIDO_CANCELADO',
  'DEUDA_PAGADA',
  'PAGO_REPORTADO',
  'PAGO_RECHAZADO',
};

/// Pide permiso de notificaciones, obtiene el token FCM del dispositivo y lo
/// registra en el backend — se llama una vez por sesión, apenas el usuario
/// ya está autenticado (ver HomePage.initState). Todo dentro de try/catch:
/// si Firebase no está disponible (web/escritorio, o falla algo puntual),
/// nunca debe bloquear el uso normal de la app.
///
/// También muestra la notificación cuando llega con la app ABIERTA: FCM
/// solo despliega la notificación del sistema automáticamente si la app
/// está en segundo plano o cerrada — en primer plano hay que mostrarla a
/// mano con flutter_local_notifications.
class NotificacionesService {
  NotificacionesService({
    ApiClient? apiClient,
    SecureStorageService? secureStorage,
  }) : _api = apiClient ?? const ApiClient(),
       _storage = secureStorage ?? SecureStorageService();

  final ApiClient _api;
  final SecureStorageService _storage;
  static final _notificacionesLocales = FlutterLocalNotificationsPlugin();
  static bool _canalCreado = false;

  /// Emite cada vez que cambia algo relacionado a pedidos/pagos — ya sea
  /// porque llegó una notificación push (nuevo/solicitado/aprobado/
  /// rechazado/entregado/cancelado/deuda pagada) o porque el propio
  /// usuario acaba de hacer una acción exitosa en esta misma sesión (ej.
  /// el personal registró un pedido nuevo, o confirmó una entrega) — ese
  /// tipo de cambio nunca dispara push hacia uno mismo, así que sin este
  /// aviso local el Dashboard u otras pantallas abiertas se quedaban
  /// mostrando cifras viejas hasta deslizar a mano. Las vistas de pedidos
  /// (dashboard de personal, Pedidos, Deudas, Mis pedidos del cliente) se
  /// suscriben para recargarse solas.
  static final _controladorEventosPedido = StreamController<void>.broadcast();
  static Stream<void> get eventosPedido => _controladorEventosPedido.stream;

  /// Llamar después de cualquier acción propia que cambie un pedido/pago
  /// (crear, aprobar, rechazar, entregar, cancelar, confirmar/rechazar
  /// pago, marcar deuda pagada) para que el resto de la app se entere sin
  /// esperar una notificación push (que nunca llega hacia uno mismo).
  static void avisarCambioPedido() => _controladorEventosPedido.add(null);

  static void _emitirSiEsEventoDePedido(RemoteMessage mensaje) {
    if (_tiposEventoPedido.contains(mensaje.data['tipo'])) {
      _controladorEventosPedido.add(null);
    }
  }

  /// Cuando el backend cambia el rol de este usuario (ver
  /// trabajadoresController.js → notificarCambioRol), manda este push para
  /// que la app reaccione AL INSTANTE, sin esperar a que el usuario toque
  /// algo que dispare una petición al servidor (que es el respaldo
  /// garantizado, pero solo reactivo — ver ApiClient.onRolCambiado). Un
  /// push puede fallar o demorarse (sin conexión, token FCM vencido, Doze
  /// de Android en segundo plano), por eso este es un "empujón" extra, no
  /// el único mecanismo.
  static void _reaccionarSiEsCambioDeRol(RemoteMessage mensaje) {
    if (mensaje.data['tipo'] != 'ROL_CAMBIADO') return;
    ApiClient.onRolCambiado?.call(
      mensaje.notification?.body ??
          'Tu cuenta fue actualizada con nuevos permisos. Vuelve a iniciar sesión para continuar.',
    );
  }

  /// Lleva al usuario al apartado correspondiente cuando TOCA una
  /// notificación (a diferencia de `_emitirSiEsEventoDePedido`, que solo
  /// refresca listas ya abiertas). Se dispara desde tres caminos distintos
  /// según en qué estado estaba la app al tocarla: en primer plano (la
  /// notificación la mostramos nosotros con flutter_local_notifications,
  /// ver `onDidReceiveNotificationResponse`), en segundo plano
  /// (`onMessageOpenedApp`, la mostró el sistema) o cerrada del todo
  /// (`getInitialMessage`, también la mostró el sistema).
  ///
  /// `idTienda` presente en los datos = notificación para el PERSONAL (ver
  /// pedidosController.js/solicitudesPagoController.js: solo los pushes que
  /// avisan al equipo de una tienda incluyen ese campo) → se resuelve el
  /// objeto `Tienda` correspondiente y se abre Pedidos o Deudas. Sin
  /// `idTienda` = notificación para el CLIENTE dueño del pedido → Mis
  /// pedidos o Mis deudas.
  static Future<void> _navegarSegunNotificacion(
    Map<String, dynamic> datos,
  ) async {
    final tipo = datos['tipo'] as String?;
    if (tipo == null || tipo == 'ROL_CAMBIADO') return;

    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    try {
      final idTiendaTexto = datos['idTienda'] as String?;
      if (idTiendaTexto != null) {
        final idTienda = int.tryParse(idTiendaTexto);
        if (idTienda == null) return;

        final tiendas = await TiendasService().misTiendas();
        Tienda? tienda;
        for (final t in tiendas) {
          if (t.idTienda == idTienda) {
            tienda = t;
            break;
          }
        }
        if (tienda == null) return;

        navigator.popUntil((ruta) => ruta.isFirst);
        navigator.push(
          SlideUpFadeRoute(
            builder: (_) => tipo == 'PAGO_REPORTADO'
                ? DeudasPage(tienda: tienda!)
                : PedidosPage(tienda: tienda!),
          ),
        );
      } else {
        navigator.popUntil((ruta) => ruta.isFirst);
        navigator.push(
          SlideUpFadeRoute(
            builder: (_) => tipo == 'DEUDA_PAGADA' || tipo == 'PAGO_RECHAZADO'
                ? const MisDeudasPage()
                : const MisPedidosPendientesPage(),
          ),
        );
      }
    } catch (_) {
      // Silencioso: si no se pudo resolver la tienda (sin acceso, sin
      // conexión), el usuario igual puede navegar a mano desde el drawer —
      // el evento de refresco (`_emitirSiEsEventoDePedido`) ya se disparó
      // aparte y no depende de esto.
    }
  }

  Future<void> inicializarYRegistrar() async {
    if (kIsWeb || !Platform.isAndroid) return;

    try {
      await _inicializarNotificacionesLocales();

      final mensajeria = FirebaseMessaging.instance;
      await mensajeria.requestPermission();

      FirebaseMessaging.onMessage.listen((mensaje) {
        _mostrarNotificacionLocal(mensaje);
        _emitirSiEsEventoDePedido(mensaje);
        _reaccionarSiEsCambioDeRol(mensaje);
      });
      FirebaseMessaging.onMessageOpenedApp.listen((mensaje) {
        _emitirSiEsEventoDePedido(mensaje);
        _reaccionarSiEsCambioDeRol(mensaje);
        _navegarSegunNotificacion(mensaje.data);
      });

      // App abierta desde cero (estaba cerrada) tocando la notificación.
      final mensajeInicial = await mensajeria.getInitialMessage();
      if (mensajeInicial != null) {
        _emitirSiEsEventoDePedido(mensajeInicial);
        _reaccionarSiEsCambioDeRol(mensajeInicial);
        _navegarSegunNotificacion(mensajeInicial.data);
      }

      final token = await mensajeria.getToken();
      if (token == null) return;

      final accessToken = await _storage.obtenerAccessToken();
      if (accessToken == null) return;

      await _api.post('/notificaciones/registrar-token', {
        'fcmToken': token,
        'plataforma': 'ANDROID',
      }, token: accessToken);
    } catch (_) {
      // Silencioso a propósito: las notificaciones son un extra, no deben
      // impedir que el resto de la app funcione.
    }
  }

  Future<void> _inicializarNotificacionesLocales() async {
    if (_canalCreado) return;

    // '@drawable/ic_notification': silueta blanca simple, como pide Android
    // para la barra de estado — el ícono a color completo (@mipmap/ic_launcher)
    // se ve mal ahí (Android lo recorta a un cuadrado sólido).
    await _notificacionesLocales.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_notification'),
      ),
      // Con la app en primer plano, la notificación la mostramos nosotros
      // (ver `_mostrarNotificacionLocal`) — este es el único camino para
      // enterarnos de que la TOCARON en ese caso, por eso viaja el `data`
      // original codificado como JSON en el payload.
      onDidReceiveNotificationResponse: (respuesta) {
        final payload = respuesta.payload;
        if (payload == null) return;
        try {
          final datos = jsonDecode(payload) as Map<String, dynamic>;
          _navegarSegunNotificacion(datos);
        } catch (_) {
          // Payload corrupto/inesperado: no hay a dónde navegar.
        }
      },
    );

    const canal = AndroidNotificationChannel(
      _canalId,
      _canalNombre,
      importance: Importance.high,
    );
    await _notificacionesLocales
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(canal);

    _canalCreado = true;
  }

  Future<void> _mostrarNotificacionLocal(RemoteMessage mensaje) async {
    final notificacion = mensaje.notification;
    if (notificacion == null) return;

    await _notificacionesLocales.show(
      mensaje.hashCode,
      notificacion.title,
      notificacion.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _canalId,
          _canalNombre,
          importance: Importance.high,
          priority: Priority.high,
          // Terracota de marca — con lo que Android tiñe la silueta blanca
          // de ic_notification en la barra de estado.
          color: Color(0xFFB5451B),
        ),
      ),
      payload: jsonEncode(mensaje.data),
    );
  }
}
