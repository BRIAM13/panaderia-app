/// Calidad del dato de un cliente, según el "Estándar Briam":
/// azul = validado por RENIEC, naranja = ingresado manualmente,
/// rojo = sin DNI registrado.
enum CalidadDato { reniec, manual, sinDni }

/// Tipo de documento/contribuyente de un cliente, derivado únicamente del
/// formato y prefijo de su `dni` — nunca de un campo aparte, para que la
/// tarjeta y el detalle siempre coincidan con lo que se ve en el formulario.
enum TipoClienteDocumento {
  dni,
  rucPersonaNatural,
  rucPersonaJuridica,
  sinDocumento,
}

/// Deriva el tipo de documento/contribuyente únicamente del formato y
/// prefijo del propio número — reutilizable por cualquier modelo que
/// necesite mostrar "DNI xxx" vs "RUC xxx (persona natural/jurídica)"
/// (ver también [Pedido] en `pedido_model.dart`).
TipoClienteDocumento tipoDocumentoDesde(String? dni) {
  if (dni == null || dni.isEmpty) return TipoClienteDocumento.sinDocumento;
  if (dni.length == 11) {
    return dni.startsWith('20')
        ? TipoClienteDocumento.rucPersonaJuridica
        : TipoClienteDocumento.rucPersonaNatural;
  }
  return TipoClienteDocumento.dni;
}

CalidadDato calidadDatoFromString(String valor) {
  switch (valor) {
    case 'RENIEC':
      return CalidadDato.reniec;
    case 'SIN_DNI':
      return CalidadDato.sinDni;
    default:
      return CalidadDato.manual;
  }
}

class Cliente {
  const Cliente({
    required this.idCliente,
    required this.idPersona,
    required this.dni,
    required this.nombres,
    required this.apellidoPaterno,
    required this.apellidoMaterno,
    required this.telefono,
    required this.email,
    required this.direccion,
    required this.descripcionNegocio,
    required this.nombreComercialOficial,
    required this.origenValidacion,
    required this.calidadDato,
    required this.puntosFidelidad,
    this.activo = true,
    this.telefonoVerificado = false,
    this.emailVerificado = false,
  });

  factory Cliente.fromJson(Map<String, dynamic> json) {
    return Cliente(
      idCliente: json['idCliente'] as int,
      idPersona: json['idPersona'] as int,
      dni: json['dni'] as String?,
      nombres: json['nombres'] as String,
      apellidoPaterno: json['apellidoPaterno'] as String,
      apellidoMaterno: json['apellidoMaterno'] as String?,
      telefono: json['telefono'] as String?,
      email: json['email'] as String?,
      direccion: json['direccion'] as String?,
      descripcionNegocio: json['descripcionNegocio'] as String?,
      nombreComercialOficial: json['nombreComercialOficial'] as bool? ?? false,
      origenValidacion: json['origenValidacion'] as String? ?? 'MANUAL',
      calidadDato: calidadDatoFromString(
        json['calidadDato'] as String? ?? 'MANUAL',
      ),
      puntosFidelidad: json['puntosFidelidad'] as int? ?? 0,
      activo: json['activo'] as bool? ?? true,
      telefonoVerificado: json['telefonoVerificado'] as bool? ?? false,
      emailVerificado: json['emailVerificado'] as bool? ?? false,
    );
  }

  final int idCliente;
  final int idPersona;
  final String? dni;
  final String nombres;
  final String apellidoPaterno;
  final String? apellidoMaterno;
  final String? telefono;
  final String? email;
  final String? direccion;
  final String? descripcionNegocio;

  /// true si el "nombre comercial" vino de una búsqueda RUC exitosa contra
  /// SUNAT (no un texto tecleado por el vendedor) — se bloquea para siempre,
  /// igual que los nombres verificados por RENIEC.
  final bool nombreComercialOficial;
  final String origenValidacion;
  final CalidadDato calidadDato;
  final int puntosFidelidad;

  /// false si el cliente fue desactivado — sigue existiendo en la BD (con
  /// todo su historial) pero oculto de la vista normal hasta reactivarlo.
  final bool activo;

  /// true solo si el dueño de la cuenta confirmó un código enviado a ese
  /// número/correo. Mientras no esté verificado, no sirve para autorizar
  /// cambios sensibles (ver `AutorizacionCambioSheet`).
  final bool telefonoVerificado;
  final bool emailVerificado;

  String get nombreCompleto => [
    nombres,
    apellidoPaterno,
    apellidoMaterno,
  ].where((s) => s != null && s.trim().isNotEmpty).join(' ');

  bool get esNegocio =>
      descripcionNegocio != null && descripcionNegocio!.trim().isNotEmpty;

  bool get datosCongelados => calidadDato == CalidadDato.reniec;

  /// El "nombre comercial" de un cliente RUC se guarda en la misma columna
  /// que la descripción de negocio de un cliente DNI — mismo dato, distinto
  /// significado según el contexto (ver [tipoDocumento]).
  String? get nombreComercial => descripcionNegocio;

  TipoClienteDocumento get tipoDocumento => tipoDocumentoDesde(dni);

  /// Nombre a mostrar en tarjetas/detalle: para RUC es la razón social
  /// (contenida en [nombres]); para DNI es el nombre completo con apellidos.
  String get nombreParaMostrar =>
      tipoDocumento == TipoClienteDocumento.dni ? nombreCompleto : nombres;
}
