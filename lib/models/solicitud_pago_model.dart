/// Una deuda propia del cliente (pedido ENTREGADO con EstadoPago=DEUDA),
/// tal como la devuelve `GET /solicitudes-pago/mis-deudas`.
class Deuda {
  const Deuda({
    required this.idPedido,
    required this.idTienda,
    required this.tienda,
    required this.total,
    required this.fechaEntregaReal,
    required this.solicitudPagoActiva,
  });

  factory Deuda.fromJson(Map<String, dynamic> json) => Deuda(
    idPedido: json['idPedido'] as int,
    idTienda: json['idTienda'] as int,
    tienda: json['tienda'] as String?,
    total: (json['total'] as num).toDouble(),
    fechaEntregaReal: json['fechaEntregaReal'] != null
        ? DateTime.parse(json['fechaEntregaReal'] as String).toLocal()
        : null,
    solicitudPagoActiva: json['solicitudPagoActiva'] != null
        ? SolicitudPagoResumen.fromJson(
            json['solicitudPagoActiva'] as Map<String, dynamic>,
          )
        : null,
  );

  final int idPedido;
  final int idTienda;
  final String? tienda;
  final double total;
  final DateTime? fechaEntregaReal;
  // No nulo si ya se generó un QR para este pedido y sigue vigente
  // (GENERADO o REPORTADO) — no se puede volver a seleccionar hasta que
  // se reporte/expire/rechace.
  final SolicitudPagoResumen? solicitudPagoActiva;
}

class SolicitudPagoResumen {
  const SolicitudPagoResumen({
    required this.idSolicitudPago,
    required this.codigoReferencia,
    required this.estado,
    required this.fechaExpiracion,
  });

  factory SolicitudPagoResumen.fromJson(Map<String, dynamic> json) =>
      SolicitudPagoResumen(
        idSolicitudPago: json['idSolicitudPago'] as int,
        codigoReferencia: json['codigoReferencia'] as String,
        estado: json['estado'] as String,
        fechaExpiracion: DateTime.parse(
          json['fechaExpiracion'] as String,
        ).toLocal(),
      );

  final int idSolicitudPago;
  final String codigoReferencia;
  // 'GENERADO' | 'REPORTADO'
  final String estado;
  final DateTime fechaExpiracion;
}

/// Datos del medio de pago tal como vienen embebidos en la respuesta de
/// crear una solicitud de pago — suficientes para armar el QR y las
/// instrucciones sin tener que volver a pedirlos.
class MedioPagoResumen {
  const MedioPagoResumen({
    required this.idMedioPago,
    required this.tipo,
    required this.titular,
    required this.numeroDestino,
    required this.cci,
    required this.nombreBanco,
    required this.notas,
    required this.imagenQrBase64,
  });

  factory MedioPagoResumen.fromJson(Map<String, dynamic> json) =>
      MedioPagoResumen(
        idMedioPago: json['idMedioPago'] as int,
        tipo: json['tipo'] as String,
        titular: json['titular'] as String,
        numeroDestino: json['numeroDestino'] as String,
        cci: json['cci'] as String?,
        nombreBanco: json['nombreBanco'] as String?,
        notas: json['notas'] as String?,
        imagenQrBase64: json['imagenQrBase64'] as String?,
      );

  final int idMedioPago;
  final String tipo;
  final String titular;
  final String numeroDestino;
  final String? cci;
  final String? nombreBanco;
  final String? notas;

  /// QR real (descargado de la app de Yape/Plin) — si está presente, es el
  /// que hay que mostrarle al cliente en vez del QR informativo generado.
  final String? imagenQrBase64;

  String get etiquetaTipo {
    switch (tipo) {
      case 'YAPE':
        return 'Yape';
      case 'PLIN':
        return 'Plin';
      case 'TRANSFERENCIA':
        return 'Transferencia bancaria';
      default:
        return 'Otro';
    }
  }
}

/// Resultado completo de crear una solicitud de pago — con lo necesario
/// para mostrar el QR y las instrucciones de pago.
class SolicitudPagoCreada {
  const SolicitudPagoCreada({
    required this.idSolicitudPago,
    required this.codigoReferencia,
    required this.montoTotal,
    required this.fechaExpiracion,
    required this.medioPago,
  });

  factory SolicitudPagoCreada.fromJson(Map<String, dynamic> json) =>
      SolicitudPagoCreada(
        idSolicitudPago: json['idSolicitudPago'] as int,
        codigoReferencia: json['codigoReferencia'] as String,
        montoTotal: (json['montoTotal'] as num).toDouble(),
        fechaExpiracion: DateTime.parse(
          json['fechaExpiracion'] as String,
        ).toLocal(),
        medioPago: MedioPagoResumen.fromJson(
          json['medioPago'] as Map<String, dynamic>,
        ),
      );

  final int idSolicitudPago;
  final String codigoReferencia;
  final double montoTotal;
  final DateTime fechaExpiracion;
  final MedioPagoResumen medioPago;

  /// Contenido del QR: texto plano legible con los datos para completar el
  /// pago a mano en cualquier billetera/banco — no auto-completa el monto
  /// (ver conversación sobre por qué no existe un QR "inteligente" gratis
  /// e independiente de una pasarela con comisión).
  String get contenidoQr {
    final buffer = StringBuffer()
      ..writeln('Pago a: ${medioPago.titular}')
      ..writeln('${medioPago.etiquetaTipo}: ${medioPago.numeroDestino}');
    if (medioPago.cci != null) buffer.writeln('CCI: ${medioPago.cci}');
    if (medioPago.nombreBanco != null) {
      buffer.writeln('Banco: ${medioPago.nombreBanco}');
    }
    buffer
      ..writeln('Monto: S/ ${montoTotal.toStringAsFixed(2)}')
      ..writeln('Referencia: $codigoReferencia');
    return buffer.toString();
  }
}

/// Una solicitud de pago reportada/pendiente, tal como la ve el personal en
/// `GET /solicitudes-pago/pendientes`.
class SolicitudPagoPendiente {
  const SolicitudPagoPendiente({
    required this.idSolicitudPago,
    required this.codigoReferencia,
    required this.montoTotal,
    required this.estado,
    required this.fechaCreacion,
    required this.fechaReporte,
    required this.clienteNombre,
    required this.clienteDescripcionNegocio,
    required this.medioPago,
  });

  factory SolicitudPagoPendiente.fromJson(Map<String, dynamic> json) {
    final cliente = json['cliente'] as Map<String, dynamic>;
    final medioPago = json['medioPago'] as Map<String, dynamic>;
    final nombre = [
      cliente['nombres'],
      cliente['apellidoPaterno'],
    ].where((s) => s != null && (s as String).trim().isNotEmpty).join(' ');
    return SolicitudPagoPendiente(
      idSolicitudPago: json['idSolicitudPago'] as int,
      codigoReferencia: json['codigoReferencia'] as String,
      montoTotal: (json['montoTotal'] as num).toDouble(),
      estado: json['estado'] as String,
      fechaCreacion: DateTime.parse(json['fechaCreacion'] as String).toLocal(),
      fechaReporte: json['fechaReporte'] != null
          ? DateTime.parse(json['fechaReporte'] as String).toLocal()
          : null,
      clienteNombre: nombre,
      clienteDescripcionNegocio: cliente['descripcionNegocio'] as String?,
      medioPago: '${medioPago['tipo']} · ${medioPago['numeroDestino']}',
    );
  }

  final int idSolicitudPago;
  final String codigoReferencia;
  final double montoTotal;
  final String estado;
  final DateTime fechaCreacion;
  final DateTime? fechaReporte;
  final String clienteNombre;
  final String? clienteDescripcionNegocio;
  final String medioPago;

  String get nombreParaMostrar =>
      (clienteDescripcionNegocio != null &&
          clienteDescripcionNegocio!.trim().isNotEmpty)
      ? clienteDescripcionNegocio!
      : clienteNombre;
}
