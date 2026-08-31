/// Representa al usuario autenticado, incluyendo la información de roles
/// necesaria para decidir si se ofrece la vista dual Cliente/Trabajador.
class UsuarioSesion {
  const UsuarioSesion({
    required this.idUsuario,
    required this.idPersona,
    required this.nombreUsuario,
    required String rol,
    required this.requiereCambioPassword,
    required this.roles,
    required this.esCliente,
    required this.esTrabajador,
    required this.esHibrido,
    this.cargoTrabajador,
    this.nombres,
    this.apellidoPaterno,
    this.apellidoMaterno,
  }) : _rolCrudo = rol;

  factory UsuarioSesion.fromJson(Map<String, dynamic> json) {
    return UsuarioSesion(
      idUsuario: json['idUsuario'] as int,
      idPersona: json['idPersona'] as int,
      nombreUsuario: json['nombreUsuario'] as String,
      rol: json['rol'] as String,
      requiereCambioPassword: json['requiereCambioPassword'] as bool? ?? false,
      roles: (json['roles'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      esCliente: json['esCliente'] as bool? ?? false,
      esTrabajador: json['esTrabajador'] as bool? ?? false,
      esHibrido: json['esHibrido'] as bool? ?? false,
      cargoTrabajador: json['cargoTrabajador'] as String?,
      nombres: json['nombres'] as String?,
      apellidoPaterno: json['apellidoPaterno'] as String?,
      apellidoMaterno: json['apellidoMaterno'] as String?,
    );
  }

  final int idUsuario;
  final int idPersona;
  final String nombreUsuario;
  final String _rolCrudo;
  final bool requiereCambioPassword;
  final List<String> roles;
  final bool esCliente;
  final bool esTrabajador;
  final bool esHibrido;
  final String? cargoTrabajador;
  final String? nombres;
  final String? apellidoPaterno;
  final String? apellidoMaterno;

  /// Rol efectivo para decidir qué puede VER en la app. VISITOR (cuenta de
  /// solo lectura para revisores externos — Google Play, Culqi, etc.) se
  /// comporta como ADMIN en toda la interfaz; es el backend quien de
  /// verdad le bloquea cualquier escritura sin importar qué se muestre
  /// aquí (ver authMiddleware.js → verificarToken). Así ningún chequeo
  /// `rol == 'ADMIN'` disperso por la app necesita enterarse de que este
  /// rol existe.
  String get rol => _rolCrudo == 'VISITOR' ? 'ADMIN' : _rolCrudo;

  /// true solo para la cuenta de solo lectura — a diferencia de [rol]
  /// (que la "disfraza" de ADMIN para que vea todo lo que un ADMIN vería),
  /// esto expone el rol REAL sin disfrazar. Se usa únicamente para mostrar
  /// la etiqueta correcta en el drawer ("Visitante" en vez de
  /// "Administrador").
  bool get esVisitante => _rolCrudo == 'VISITOR';

  /// Roles con privilegios de gestión (todo lo que no sea un cliente puro).
  bool get esPersonalDeGestion =>
      rol == 'TRABAJADOR' || rol == 'ADMIN' || rol == 'SUPERADMIN';

  /// Nombre completo verificado por DNI/RENIEC — se usa en los saludos
  /// ("Bienvenido, ...") en vez del nombre de usuario técnico. Si por algún
  /// motivo no llegó (cuenta sin Persona asociada), cae de vuelta al
  /// nombre de usuario.
  String get nombreCompleto {
    final partes = [
      nombres,
      apellidoPaterno,
      apellidoMaterno,
    ].where((s) => s != null && s.trim().isNotEmpty).join(' ');
    return partes.isEmpty ? nombreUsuario : partes;
  }

  UsuarioSesion copyWith({bool? requiereCambioPassword}) {
    return UsuarioSesion(
      idUsuario: idUsuario,
      idPersona: idPersona,
      nombreUsuario: nombreUsuario,
      rol: _rolCrudo,
      requiereCambioPassword:
          requiereCambioPassword ?? this.requiereCambioPassword,
      roles: roles,
      esCliente: esCliente,
      esTrabajador: esTrabajador,
      esHibrido: esHibrido,
      cargoTrabajador: cargoTrabajador,
      nombres: nombres,
      apellidoPaterno: apellidoPaterno,
      apellidoMaterno: apellidoMaterno,
    );
  }
}
