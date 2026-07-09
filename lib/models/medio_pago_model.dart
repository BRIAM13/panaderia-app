/// Un método de pago digital configurado por el ADMIN/SUPERADMIN de una
/// tienda, para que sus clientes salden deudas.
class MedioPago {
  const MedioPago({
    required this.idMedioPago,
    required this.idTienda,
    required this.tipo,
    required this.titular,
    required this.numeroDestino,
    required this.cci,
    required this.nombreBanco,
    required this.notas,
    required this.imagenQrBase64,
    required this.estado,
  });

  factory MedioPago.fromJson(Map<String, dynamic> json) => MedioPago(
    idMedioPago: json['idMedioPago'] as int,
    idTienda: json['idTienda'] as int,
    tipo: json['tipo'] as String,
    titular: json['titular'] as String,
    numeroDestino: json['numeroDestino'] as String,
    cci: json['cci'] as String?,
    nombreBanco: json['nombreBanco'] as String?,
    notas: json['notas'] as String?,
    imagenQrBase64: json['imagenQrBase64'] as String?,
    estado: json['estado'] as bool,
  );

  final int idMedioPago;
  final int idTienda;
  // 'YAPE' | 'PLIN' | 'TRANSFERENCIA' | 'OTRO'
  final String tipo;
  final String titular;
  final String numeroDestino;
  final String? cci;
  final String? nombreBanco;
  final String? notas;

  /// QR real (descargado de la propia app de Yape/Plin), en base64 — si
  /// está presente, es el que hay que mostrarle al cliente para escanear
  /// (el único que esas apps reconocen de verdad). Si es null, el cliente
  /// solo ve el QR informativo generado por la app.
  final String? imagenQrBase64;
  final bool estado;

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
