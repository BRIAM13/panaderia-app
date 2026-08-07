import 'package:package_info_plus/package_info_plus.dart';

import 'api_client.dart';

/// Resultado de comparar la versión instalada contra la mínima exigida por
/// el backend (`GET /app-info`, sin autenticación — ver server.js).
class EstadoActualizacion {
  const EstadoActualizacion({
    required this.actualizacionRequerida,
    required this.urlDescarga,
  });

  final bool actualizacionRequerida;
  final String urlDescarga;
}

/// Compara versiones "semver" simples (`1.2.3`, sin sufijos tipo `-beta`) —
/// suficiente para este proyecto, que solo usa `major.minor.patch`.
/// Devuelve true si [actual] es estrictamente menor que [minima].
bool versionEsMenorQue(String actual, String minima) {
  List<int> partes(String v) =>
      v.split('.').map((p) => int.tryParse(p) ?? 0).toList();

  final a = partes(actual);
  final m = partes(minima);
  final largo = a.length > m.length ? a.length : m.length;

  for (var i = 0; i < largo; i++) {
    final ai = i < a.length ? a[i] : 0;
    final mi = i < m.length ? m[i] : 0;
    if (ai != mi) return ai < mi;
  }
  return false;
}

class VersionService {
  VersionService({ApiClient? apiClient}) : _api = apiClient ?? const ApiClient();

  final ApiClient _api;

  /// Nunca lanza: si el backend no responde o algo falla, se asume que NO
  /// hace falta actualizar — un fallo de red jamás debe dejar a nadie
  /// bloqueado fuera de la app.
  Future<EstadoActualizacion> verificar() async {
    const urlPorDefecto = 'https://play.google.com/store/apps/details?id=com.corporacionronceros.panaderia_app';
    try {
      final data = await _api.get('/app-info');
      final versionMinima = data['versionMinimaAndroid'] as String? ?? '0.0.0';
      final urlDescarga = data['urlDescargaApk'] as String? ?? urlPorDefecto;

      final info = await PackageInfo.fromPlatform();
      final requerida = versionEsMenorQue(info.version, versionMinima);

      return EstadoActualizacion(
        actualizacionRequerida: requerida,
        urlDescarga: urlDescarga,
      );
    } catch (_) {
      return const EstadoActualizacion(
        actualizacionRequerida: false,
        urlDescarga: urlPorDefecto,
      );
    }
  }
}
