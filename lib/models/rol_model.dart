/// Un rol que el usuario autenticado puede asignar a otra persona —
/// siempre leído de la tabla Roles, nunca hardcodeado en la app: un ADMIN
/// solo ve TRABAJADOR, un SUPERADMIN ve TRABAJADOR/ADMIN/SUPERADMIN.
class RolAsignable {
  const RolAsignable({required this.idRol, required this.nombreRol});

  factory RolAsignable.fromJson(Map<String, dynamic> json) => RolAsignable(
    idRol: json['idRol'] as int,
    nombreRol: json['nombreRol'] as String,
  );

  final int idRol;
  final String nombreRol;

  String get etiqueta {
    switch (nombreRol) {
      case 'TRABAJADOR':
        return 'Trabajador';
      case 'ADMIN':
        return 'Administrador';
      case 'SUPERADMIN':
        return 'Super administrador';
      default:
        return nombreRol;
    }
  }
}
