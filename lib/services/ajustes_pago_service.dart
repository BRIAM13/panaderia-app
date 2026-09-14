import '../models/pedido_model.dart';
import 'api_client.dart';
import 'secure_storage_service.dart';

// `AjustePago` vive en models/pedido_model.dart, junto a `Pedido`: un ajuste
// siempre es de un pedido, y así la lista dedicada y el ajuste que llega
// colgado de un pedido son exactamente el mismo tipo. Se reexporta para que
// una pantalla que solo use este servicio no necesite un import extra.
export '../models/pedido_model.dart' show AjustePago;

/// Saldos y vueltos que quedaron pendientes tras verificar un pago
/// adelantado por Yape que no coincidió con el total del pedido.
///
/// Vive aparte de `PedidosService` por lo mismo que la pantalla vive aparte
/// de Pedidos: un ajuste puede sobrevivir a su pedido. La lista de pedidos
/// oculta lo ya finalizado, así que un vuelto que no se alcanzó a devolver
/// el día de la entrega desaparecería justo cuando más falta hace
/// recordarlo.
class AjustesPagoService {
  AjustesPagoService({ApiClient? apiClient, SecureStorageService? secureStorage})
    : _api = apiClient ?? const ApiClient(),
      _storage = secureStorage ?? SecureStorageService();

  final ApiClient _api;
  final SecureStorageService _storage;

  /// Los ajustes TODAVÍA sin resolver de una tienda, del más viejo al más
  /// nuevo (lo que lleva más tiempo esperando va primero). Sin acceso a esa
  /// tienda el backend devuelve una lista vacía, no un error.
  Future<List<AjustePago>> listarPendientes({required int idTienda}) async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.get('/ajustes-pago?idTienda=$idTienda', token: token);
    final lista = data['ajustes'] as List<dynamic>? ?? const [];
    return lista
        .map((e) => AjustePago.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Marca un saldo cobrado o un vuelto devuelto.
  ///
  /// A propósito es una acción INDEPENDIENTE de "marcar entregado": lo
  /// normal es resolverlo al recoger, pero el dueño puede devolver un vuelto
  /// por Yape el mismo día o cobrar un saldo la semana siguiente. Atarlas
  /// obligaría a mentir en una para poder hacer la otra.
  Future<void> resolver(int idAjuste, {String? notas}) async {
    final token = await _storage.obtenerAccessToken();
    await _api.post('/ajustes-pago/$idAjuste/resolver', {
      if (notas != null && notas.trim().isNotEmpty) 'notas': notas.trim(),
    }, token: token);
  }
}
