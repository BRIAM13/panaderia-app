import 'cliente_model.dart';

/// Segmento del cliente, calculado por el backend a partir de su historial
/// de pedidos ENTREGADOS — ver `calcularSegmento` en clientesController.js.
enum SegmentoCliente { nuevo, enRiesgo, vip, frecuente, regular }

SegmentoCliente segmentoClienteFromString(String valor) {
  switch (valor) {
    case 'NUEVO':
      return SegmentoCliente.nuevo;
    case 'EN_RIESGO':
      return SegmentoCliente.enRiesgo;
    case 'VIP':
      return SegmentoCliente.vip;
    case 'FRECUENTE':
      return SegmentoCliente.frecuente;
    default:
      return SegmentoCliente.regular;
  }
}

/// Una tienda donde el cliente ya tuvo al menos un pedido entregado.
class TiendaResumen {
  const TiendaResumen({required this.idTienda, required this.nombre});

  factory TiendaResumen.fromJson(Map<String, dynamic> json) =>
      TiendaResumen(
        idTienda: json['idTienda'] as int,
        nombre: json['nombre'] as String,
      );

  final int idTienda;
  final String nombre;
}

/// Historial agregado de pedidos de un cliente — solo cuenta lo
/// efectivamente ENTREGADO, nunca lo pendiente/rechazado/cancelado.
class HistorialCliente {
  const HistorialCliente({
    required this.totalPedidos,
    required this.pedidosEntregados,
    required this.totalGastado,
    required this.deudaPendiente,
    required this.ultimaCompra,
    required this.diasDesdeUltimaCompra,
    required this.tiendas,
  });

  factory HistorialCliente.fromJson(Map<String, dynamic> json) {
    final ultimaCompraStr = json['ultimaCompra'] as String?;
    return HistorialCliente(
      totalPedidos: json['totalPedidos'] as int? ?? 0,
      pedidosEntregados: json['pedidosEntregados'] as int? ?? 0,
      totalGastado: (json['totalGastado'] as num?)?.toDouble() ?? 0,
      deudaPendiente: (json['deudaPendiente'] as num?)?.toDouble() ?? 0,
      ultimaCompra: ultimaCompraStr != null
          ? DateTime.tryParse(ultimaCompraStr)
          : null,
      diasDesdeUltimaCompra: json['diasDesdeUltimaCompra'] as int?,
      tiendas: (json['tiendas'] as List<dynamic>? ?? const [])
          .map((e) => TiendaResumen.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  final int totalPedidos;
  final int pedidosEntregados;
  final double totalGastado;
  final double deudaPendiente;
  final DateTime? ultimaCompra;
  final int? diasDesdeUltimaCompra;
  final List<TiendaResumen> tiendas;
}

/// Perfil completo de un cliente: sus datos base + el historial agregado +
/// el segmento — todo lo que arma `GET /clientes/:id/perfil`.
class PerfilCliente {
  const PerfilCliente({
    required this.cliente,
    required this.historial,
    required this.segmento,
  });

  factory PerfilCliente.fromJson(Map<String, dynamic> json) => PerfilCliente(
    cliente: Cliente.fromJson(json['cliente'] as Map<String, dynamic>),
    historial: HistorialCliente.fromJson(
      json['historial'] as Map<String, dynamic>,
    ),
    segmento: segmentoClienteFromString(json['segmento'] as String? ?? ''),
  );

  final Cliente cliente;
  final HistorialCliente historial;
  final SegmentoCliente segmento;
}

/// Una nota interna que el personal dejó sobre un cliente — nunca visible
/// para el cliente mismo.
class NotaCliente {
  const NotaCliente({
    required this.idNota,
    required this.idCliente,
    required this.texto,
    required this.fechaCreacion,
    required this.autor,
  });

  factory NotaCliente.fromJson(Map<String, dynamic> json) => NotaCliente(
    idNota: json['idNota'] as int,
    idCliente: json['idCliente'] as int,
    texto: json['texto'] as String,
    fechaCreacion:
        DateTime.tryParse(json['fechaCreacion'] as String? ?? '') ??
        DateTime.now(),
    autor: json['autor'] as String? ?? '',
  );

  final int idNota;
  final int idCliente;
  final String texto;
  final DateTime fechaCreacion;
  final String autor;
}
