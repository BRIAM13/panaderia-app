import '../models/cliente_model.dart';
import '../models/perfil_cliente_model.dart';
import 'api_client.dart';
import 'secure_storage_service.dart';

/// Datos de un cliente para crear o actualizar, ya validados por la UI.
class ClienteInput {
  const ClienteInput({
    this.dni,
    required this.nombres,
    required this.apellidoPaterno,
    this.apellidoMaterno,
    this.telefono,
    this.email,
    this.direccion,
    this.descripcionNegocio,
    this.nombreComercialOficial = false,
    this.origenValidacion = 'MANUAL',
    this.dniVerificadoApiReal = false,
  });

  final String? dni;
  final String nombres;
  final String apellidoPaterno;
  final String? apellidoMaterno;
  final String? telefono;
  final String? email;
  final String? direccion;
  final String? descripcionNegocio;

  /// true si [descripcionNegocio] es el nombre comercial oficial devuelto
  /// por una búsqueda RUC exitosa contra SUNAT — el backend lo bloquea para
  /// siempre en cuanto llegue así una vez.
  final bool nombreComercialOficial;
  final String origenValidacion;

  /// true solo si el DNI fue validado contra apiperu.dev real (no el
  /// simulador de respaldo): dispara la clonación automática de Usuario.
  final bool dniVerificadoApiReal;

  Map<String, dynamic> toJson() => {
    'dni': dni,
    'nombres': nombres,
    'apellidoPaterno': apellidoPaterno,
    'apellidoMaterno': apellidoMaterno,
    'telefono': telefono,
    'email': email,
    'direccion': direccion,
    'descripcionNegocio': descripcionNegocio,
    'nombreComercialOficial': nombreComercialOficial,
    'origenValidacion': origenValidacion,
    'dniVerificadoApiReal': dniVerificadoApiReal,
  };
}

/// Resultado de verificar localmente (contra nuestra BD, sin apiperu.dev)
/// si un documento ya pertenece a alguien registrado.
class DocumentoExistenteResult {
  const DocumentoExistenteResult({
    required this.existe,
    this.nombreCompleto,
    this.esCliente = false,
    this.tieneUsuario = false,
  });

  factory DocumentoExistenteResult.fromJson(Map<String, dynamic> json) =>
      DocumentoExistenteResult(
        existe: json['existe'] as bool? ?? false,
        nombreCompleto: json['nombreCompleto'] as String?,
        esCliente: json['esCliente'] as bool? ?? false,
        tieneUsuario: json['tieneUsuario'] as bool? ?? false,
      );

  final bool existe;
  final String? nombreCompleto;
  final bool esCliente;
  final bool tieneUsuario;
}

class ClientesService {
  ClientesService({ApiClient? apiClient, SecureStorageService? secureStorage})
    : _api = apiClient ?? const ApiClient(),
      _storage = secureStorage ?? SecureStorageService();

  final ApiClient _api;
  final SecureStorageService _storage;

  /// [estado]: 'activos' (por defecto), 'inactivos' o 'todos'.
  Future<List<Cliente>> listar({String estado = 'activos'}) async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.get('/clientes?estado=$estado', token: token);
    final lista = data['clientes'] as List<dynamic>? ?? const [];
    return lista
        .map((e) => Cliente.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Devuelve `true` si el backend clonó automáticamente una cuenta de
  /// acceso para el cliente (verificación con DNI real de apiperu.dev).
  Future<bool> crear(ClienteInput input) async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.post('/clientes', input.toJson(), token: token);
    return data['cuentaClonada'] == true;
  }

  Future<bool> actualizar(int idCliente, ClienteInput input) async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.put(
      '/clientes/$idCliente',
      input.toJson(),
      token: token,
    );
    return data['cuentaClonada'] == true;
  }

  Future<void> desactivar(int idCliente) async {
    final token = await _storage.obtenerAccessToken();
    await _api.delete('/clientes/$idCliente', token: token);
  }

  Future<void> reactivar(int idCliente) async {
    final token = await _storage.obtenerAccessToken();
    await _api.put('/clientes/$idCliente/reactivar', const {}, token: token);
  }

  /// Chequeo local (rápido, sin costo) contra nuestra propia BD: evita
  /// gastar una consulta paga a apiperu.dev cuando el documento ya
  /// pertenece a alguien registrado. [excluirIdPersona] se usa al editar,
  /// para no marcar como "duplicado" al propio cliente que se está editando.
  Future<DocumentoExistenteResult> verificarDocumento(
    String documento, {
    int? excluirIdPersona,
  }) async {
    final token = await _storage.obtenerAccessToken();
    final query = excluirIdPersona != null
        ? '?excluirIdPersona=$excluirIdPersona'
        : '';
    final data = await _api.get(
      '/clientes/verificar-documento/$documento$query',
      token: token,
    );
    return DocumentoExistenteResult.fromJson(data);
  }

  /// Autoservicio: el propio usuario CLIENTE consulta su cliente asociado.
  Future<Cliente> obtenerMiPerfil() async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.get('/clientes/mi-perfil', token: token);
    return Cliente.fromJson(data['cliente'] as Map<String, dynamic>);
  }

  /// Autoservicio: solo dirección de entrega. Teléfono/email tienen su
  /// propio flujo con código de verificación — ver métodos de abajo.
  Future<void> actualizarMiPerfil({String? direccion}) async {
    final token = await _storage.obtenerAccessToken();
    await _api.put('/clientes/mi-perfil', {
      'direccion': direccion,
    }, token: token);
  }

  /// Pide un código SMS para el número [telefonoNuevo]. Si el cliente ya
  /// tiene algún canal verificado, primero hay que autorizar el cambio
  /// (ver [solicitarAutorizacion]) y pasar ese código aquí.
  Future<void> solicitarCodigoCelular({
    required String telefonoNuevo,
    String? canalAutorizacion,
    String? codigoAutorizacion,
  }) async {
    final token = await _storage.obtenerAccessToken();
    await _api.post('/clientes/mi-perfil/celular/solicitar-codigo', {
      'telefonoNuevo': telefonoNuevo,
      if (canalAutorizacion != null) 'canalAutorizacion': canalAutorizacion,
      if (codigoAutorizacion != null) 'codigoAutorizacion': codigoAutorizacion,
    }, token: token);
  }

  Future<void> confirmarCodigoCelular({
    required String telefonoNuevo,
    required String codigo,
  }) async {
    final token = await _storage.obtenerAccessToken();
    await _api.post('/clientes/mi-perfil/celular/confirmar-codigo', {
      'telefonoNuevo': telefonoNuevo,
      'codigo': codigo,
    }, token: token);
  }

  Future<void> solicitarCodigoCorreo({
    required String emailNuevo,
    String? canalAutorizacion,
    String? codigoAutorizacion,
  }) async {
    final token = await _storage.obtenerAccessToken();
    await _api.post('/clientes/mi-perfil/correo/solicitar-codigo', {
      'emailNuevo': emailNuevo,
      if (canalAutorizacion != null) 'canalAutorizacion': canalAutorizacion,
      if (codigoAutorizacion != null) 'codigoAutorizacion': codigoAutorizacion,
    }, token: token);
  }

  Future<void> confirmarCodigoCorreo({
    required String emailNuevo,
    required String codigo,
  }) async {
    final token = await _storage.obtenerAccessToken();
    await _api.post('/clientes/mi-perfil/correo/confirmar-codigo', {
      'emailNuevo': emailNuevo,
      'codigo': codigo,
    }, token: token);
  }

  /// Envía el código que autoriza un cambio sensible (celular/correo/
  /// contraseña) al canal YA verificado que el cliente elija.
  Future<void> solicitarAutorizacion({required String canal}) async {
    final token = await _storage.obtenerAccessToken();
    await _api.post('/clientes/mi-perfil/autorizacion/solicitar', {
      'canal': canal,
    }, token: token);
  }

  /// Valida el código de autorización EN EL MOMENTO, sin gastarlo (el
  /// backend lo vuelve a validar y ahí sí lo consume cuando se usa para el
  /// cambio real). Así el paso de "autoriza este cambio" puede mostrar el
  /// error de inmediato si el código es incorrecto, en vez de dejar avanzar
  /// cualquier código y recién fallar en el paso siguiente.
  Future<void> validarAutorizacion({
    required String canal,
    required String codigo,
  }) async {
    final token = await _storage.obtenerAccessToken();
    await _api.post('/clientes/mi-perfil/autorizacion/validar', {
      'canal': canal,
      'codigo': codigo,
    }, token: token);
  }

  /// Cambio de contraseña autoservicio: no pide la contraseña actual, la
  /// protege el código de autorización — así, aunque alguien más use la
  /// sesión ya iniciada del dueño, no puede cambiarla sin acceso real a su
  /// celular/correo verificado.
  Future<void> cambiarPasswordSeguro({
    required String passwordNueva,
    required String canalAutorizacion,
    required String codigoAutorizacion,
  }) async {
    final token = await _storage.obtenerAccessToken();
    await _api.post('/clientes/mi-perfil/password/cambiar-seguro', {
      'passwordNueva': passwordNueva,
      'canalAutorizacion': canalAutorizacion,
      'codigoAutorizacion': codigoAutorizacion,
    }, token: token);
  }

  /// CRM (personal): perfil completo con historial agregado y segmento.
  Future<PerfilCliente> obtenerPerfil(int idCliente) async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.get('/clientes/$idCliente/perfil', token: token);
    return PerfilCliente.fromJson(data);
  }

  Future<List<NotaCliente>> listarNotas(int idCliente) async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.get('/clientes/$idCliente/notas', token: token);
    final lista = data['notas'] as List<dynamic>? ?? const [];
    return lista
        .map((e) => NotaCliente.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> crearNota(int idCliente, String texto) async {
    final token = await _storage.obtenerAccessToken();
    await _api.post('/clientes/$idCliente/notas', {
      'texto': texto,
    }, token: token);
  }

  /// Devuelve el nuevo saldo de puntos tras el canje.
  Future<int> canjearPuntos(
    int idCliente,
    int puntos, {
    String? descripcion,
  }) async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.post('/clientes/$idCliente/canjear-puntos', {
      'puntos': puntos,
      if (descripcion != null) 'descripcion': descripcion,
    }, token: token);
    return data['puntosFidelidad'] as int;
  }

  /// Campaña de reactivación: push a todos los clientes "en riesgo".
  /// Exclusivo ADMIN/SUPERADMIN — el backend también lo exige.
  Future<({int clientesNotificados, int dispositivosAlcanzados})>
  enviarCampaniaReactivacion(String mensaje) async {
    final token = await _storage.obtenerAccessToken();
    final data = await _api.post('/clientes/campanias/reactivacion', {
      'mensaje': mensaje,
    }, token: token);
    return (
      clientesNotificados: data['clientesNotificados'] as int? ?? 0,
      dispositivosAlcanzados: data['dispositivosAlcanzados'] as int? ?? 0,
    );
  }
}
