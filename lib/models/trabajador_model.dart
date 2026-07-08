/// Estado de acceso de un trabajador a una tienda puntual — [activo] en
/// false significa que tuvo acceso alguna vez pero se lo revocaron, no que
/// nunca lo tuvo (ver TrabajadorTiendas.Estado en el backend).
class TrabajadorTiendaAsignada {
  const TrabajadorTiendaAsignada({
    required this.idTienda,
    required this.nombre,
    required this.activo,
  });

  factory TrabajadorTiendaAsignada.fromJson(Map<String, dynamic> json) =>
      TrabajadorTiendaAsignada(
        idTienda: json['idTienda'] as int,
        nombre: json['nombre'] as String,
        activo: json['activo'] as bool? ?? false,
      );

  final int idTienda;
  final String nombre;
  final bool activo;
}

/// Resultado de buscar un DNI en nuestra propia base antes de registrar un
/// trabajador — igual idea que la verificación de documento de Clientes,
/// pero con los datos completos necesarios para precargar el formulario.
class BusquedaDniTrabajador {
  const BusquedaDniTrabajador({
    required this.existeEnBd,
    this.bloqueado = false,
    this.mensajeBloqueo,
    this.idPersona,
    this.nombres,
    this.apellidoPaterno,
    this.apellidoMaterno,
    this.telefono,
    this.email,
    this.direccion,
    this.origenValidacion,
    this.esCliente = false,
    this.yaEsTrabajador = false,
    this.idTrabajador,
    this.cargo,
    this.tiendasAsignadas = const [],
  });

  factory BusquedaDniTrabajador.fromJson(Map<String, dynamic> json) {
    final tiendas = json['tiendasAsignadas'] as List<dynamic>? ?? const [];
    return BusquedaDniTrabajador(
      existeEnBd: json['existeEnBd'] as bool? ?? false,
      bloqueado: json['bloqueado'] as bool? ?? false,
      mensajeBloqueo: json['mensaje'] as String?,
      idPersona: json['idPersona'] as int?,
      nombres: json['nombres'] as String?,
      apellidoPaterno: json['apellidoPaterno'] as String?,
      apellidoMaterno: json['apellidoMaterno'] as String?,
      telefono: json['telefono'] as String?,
      email: json['email'] as String?,
      direccion: json['direccion'] as String?,
      origenValidacion: json['origenValidacion'] as String?,
      esCliente: json['esCliente'] as bool? ?? false,
      yaEsTrabajador: json['yaEsTrabajador'] as bool? ?? false,
      idTrabajador: json['idTrabajador'] as int?,
      cargo: json['cargo'] as String?,
      tiendasAsignadas: tiendas
          .map(
            (e) => TrabajadorTiendaAsignada.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  final bool existeEnBd;

  /// true si el DNI pertenece a un SUPERADMIN que quien busca no puede
  /// tocar (ver trabajadoresController.js → buscarPorDni) — en ese caso el
  /// backend a propósito NO manda ningún dato personal, solo
  /// [mensajeBloqueo].
  final bool bloqueado;
  final String? mensajeBloqueo;

  final int? idPersona;
  final String? nombres;
  final String? apellidoPaterno;
  final String? apellidoMaterno;
  final String? telefono;
  final String? email;
  final String? direccion;
  final String? origenValidacion;
  final bool esCliente;
  final bool yaEsTrabajador;
  final int? idTrabajador;
  final String? cargo;
  final List<TrabajadorTiendaAsignada> tiendasAsignadas;
}

/// Un trabajador del pool completo (para el directorio cruzado entre
/// tiendas), tal como lo devuelve `GET /trabajadores`.
class Trabajador {
  const Trabajador({
    required this.idTrabajador,
    required this.idPersona,
    required this.dni,
    required this.nombres,
    required this.apellidoPaterno,
    required this.apellidoMaterno,
    required this.telefono,
    required this.email,
    required this.cargo,
    required this.rol,
    required this.activo,
    required this.tiendas,
  });

  factory Trabajador.fromJson(Map<String, dynamic> json) {
    final tiendas = json['tiendas'] as List<dynamic>? ?? const [];
    return Trabajador(
      idTrabajador: json['idTrabajador'] as int,
      idPersona: json['idPersona'] as int,
      dni: json['dni'] as String?,
      nombres: json['nombres'] as String,
      apellidoPaterno: json['apellidoPaterno'] as String,
      apellidoMaterno: json['apellidoMaterno'] as String?,
      telefono: json['telefono'] as String?,
      email: json['email'] as String?,
      cargo: json['cargo'] as String,
      rol: json['rol'] as String?,
      activo: json['activo'] as bool? ?? true,
      tiendas: tiendas
          .map(
            (e) => TrabajadorTiendaAsignada.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  final int idTrabajador;
  final int idPersona;
  final String? dni;
  final String nombres;
  final String apellidoPaterno;
  final String? apellidoMaterno;
  final String? telefono;
  final String? email;
  final String cargo;
  // Rol de acceso actual (TRABAJADOR/ADMIN/SUPERADMIN) — null si la persona
  // todavía no tiene una cuenta de acceso creada.
  final String? rol;
  final bool activo;
  final List<TrabajadorTiendaAsignada> tiendas;

  String get nombreCompleto => [
    nombres,
    apellidoPaterno,
    apellidoMaterno,
  ].where((s) => s != null && s.trim().isNotEmpty).join(' ');

  bool tieneAccesoA(int idTienda) =>
      tiendas.any((t) => t.idTienda == idTienda && t.activo);
}
