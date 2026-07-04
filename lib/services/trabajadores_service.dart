import '../models/trabajador_model.dart';
import 'api_client.dart';
import 'secure_storage_service.dart';

/// Datos de un trabajador nuevo (o de una persona existente a la que se le
/// da acceso a una tienda), ya validados por la UI.
class TrabajadorInput {
  const TrabajadorInput({
    required this.dni,
    required this.nombres,
    required this.apellidoPaterno,
    this.apellidoMaterno,
    this.telefono,
    this.email,
    this.direccion,
    required this.rol,
    this.salario,
    this.origenValidacion = 'MANUAL',
    required this.tiendas,
  });

  final String dni;
  final String nombres;
  final String apellidoPaterno;
  final String? apellidoMaterno;
  final String? telefono;
  final String? email;
  final String? direccion;
  // 'TRABAJADOR' | 'ADMIN' | 'SUPERADMIN' — de la lista de RolesService.
  final String rol;
  final double? salario;
  final String origenValidacion;
  final List<int> tiendas;

  Map<String, dynamic> toJson() => {
    'dni': dni,
    'nombres': nombres,
    'apellidoPaterno': apellidoPaterno,
    'apellidoMaterno': apellidoMaterno,
    'telefono': telefono,
    'email': email,
    'direccion': direccion,
    'rol': rol,
    'salario': salario,
    'origenValidacion': origenValidacion,
    'tiendas': tiendas,
  };
}

class TrabajadoresService {
  TrabajadoresService({
    ApiClient? apiClient,
    SecureStorageService? secureStorage,
  }) : _api = apiClient ?? const ApiClient(),
       _storage = secureStorage ?? SecureStorageService();

  final ApiClient _api;
  final SecureStorageService _storage;

  /// Busca un DNI en NUESTRA base (nunca RENIEC — eso se sigue consultando
  /// aparte contra /external/dni/:dni, igual que en Clientes).
  Future<BusquedaDniTrabajador> buscarPorDni(String dni) async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.get(
      '/trabajadores/buscar-por-dni/$dni',
      token: token,
    );
    return BusquedaDniTrabajador.fromJson(data);
  }

  Future<void> crear(TrabajadorInput input) async {
    final token = await _storage.obtenerAccessToken();
    await _api.post('/trabajadores', input.toJson(), token: token);
  }

  /// Pool completo de trabajadores (para el directorio cruzado entre
  /// tiendas) — solo ADMIN/SUPERADMIN.
  Future<List<Trabajador>> listar() async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.get('/trabajadores', token: token);
    final lista = data['trabajadores'] as List<dynamic>? ?? const [];
    return lista
        .map((e) => Trabajador.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> otorgarAcceso({
    required int idTrabajador,
    required int idTienda,
  }) async {
    final token = await _storage.obtenerAccessToken();
    await _api.put(
      '/trabajadores/$idTrabajador/tiendas/$idTienda',
      const {},
      token: token,
    );
  }

  Future<void> revocarAcceso({
    required int idTrabajador,
    required int idTienda,
  }) async {
    final token = await _storage.obtenerAccessToken();
    await _api.delete(
      '/trabajadores/$idTrabajador/tiendas/$idTienda',
      token: token,
    );
  }

  /// Cambia el rol de acceso de un trabajador ya existente (ej. ascenderlo
  /// a Administrador) — el backend valida que quien llama tenga permiso
  /// para asignar ese rol específico.
  Future<void> cambiarRol({
    required int idTrabajador,
    required String rol,
  }) async {
    final token = await _storage.obtenerAccessToken();
    await _api.put('/trabajadores/$idTrabajador/rol', {
      'rol': rol,
    }, token: token);
  }
}
