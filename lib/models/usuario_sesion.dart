/// Representa al usuario autenticado, incluyendo la información de roles
/// necesaria para decidir si se ofrece la vista dual Cliente/Trabajador.
class UsuarioSesion {
  const UsuarioSesion({
    required this.idUsuario,
    required this.idPersona,
    required this.nombreUsuario,
    required this.rol,
    required this.requiereCambioPassword,
    required this.roles,
    required this.esCliente,
    required this.esTrabajador,
    required this.esHibrido,
    this.cargoTrabajador,
    this.nombres,
    this.apellidoPaterno,
    this.apellidoMaterno,
  });

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
  final String rol;
  final bool requiereCambioPassword;
  final List<String> roles;
  final bool esCliente;
  final bool esTrabajador;
  final bool esHibrido;
  final String? cargoTrabajador;
  final String? nombres;
  final String? apellidoPaterno;
  final String? apellidoMaterno;

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
      rol: rol,
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
