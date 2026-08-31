import 'perfil_cliente_model.dart';

/// Un cliente visto desde el panel de Analítica: lo mínimo para listarlo y
/// entender por qué está en esa lista. No es un [Cliente] completo a
/// propósito — acá se cargan TODOS los clientes de una sola vez, y arrastrar
/// DNI, dirección, verificaciones y demás por cada uno solo para pintar una
/// fila sería peso muerto. Al tocar la fila se abre su perfil, que sí trae
/// la ficha completa.
class ClienteResumenLigero {
  const ClienteResumenLigero({
    required this.idCliente,
    required this.nombre,
    required this.telefono,
    required this.pedidosEntregados,
    required this.totalGastado,
    required this.diasDesdeUltimaCompra,
    required this.segmento,
  });

  factory ClienteResumenLigero.fromJson(Map<String, dynamic> json) =>
      ClienteResumenLigero(
        idCliente: json['idCliente'] as int,
        nombre: json['nombre'] as String? ?? '',
        telefono: json['telefono'] as String?,
        pedidosEntregados: json['pedidosEntregados'] as int? ?? 0,
        totalGastado: (json['totalGastado'] as num?)?.toDouble() ?? 0,
        diasDesdeUltimaCompra: json['diasDesdeUltimaCompra'] as int?,
        segmento: segmentoClienteFromString(json['segmento'] as String? ?? ''),
      );

  final int idCliente;
  final String nombre;
  final String? telefono;
  final int pedidosEntregados;
  final double totalGastado;

  /// null si el cliente nunca tuvo un pedido entregado (segmento NUEVO).
  final int? diasDesdeUltimaCompra;
  final SegmentoCliente segmento;
}

/// La foto completa de la cartera de clientes activos que arma
/// `GET /clientes/analitica/resumen-segmentos` en una sola consulta.
class ResumenSegmentos {
  const ResumenSegmentos({
    required this.conteoPorSegmento,
    required this.totalClientes,
    required this.enRiesgo,
    required this.topPorGasto,
  });

  factory ResumenSegmentos.fromJson(Map<String, dynamic> json) {
    final resumen = json['resumen'] as Map<String, dynamic>? ?? const {};
    return ResumenSegmentos(
      conteoPorSegmento: resumen.map(
        (clave, valor) =>
            MapEntry(segmentoClienteFromString(clave), (valor as num).toInt()),
      ),
      totalClientes: json['totalClientes'] as int? ?? 0,
      enRiesgo: _listaDeClientes(json['enRiesgo']),
      topPorGasto: _listaDeClientes(json['topPorGasto']),
    );
  }

  static List<ClienteResumenLigero> _listaDeClientes(dynamic valor) =>
      (valor as List<dynamic>? ?? const [])
          .map((e) => ClienteResumenLigero.fromJson(e as Map<String, dynamic>))
          .toList();

  final Map<SegmentoCliente, int> conteoPorSegmento;
  final int totalClientes;

  /// Todos los que cayeron en EN_RIESGO, del más abandonado al menos — es el
  /// orden en que conviene llamarlos.
  final List<ClienteResumenLigero> enRiesgo;

  /// Los 10 que más gastaron (histórico entregado), de mayor a menor.
  final List<ClienteResumenLigero> topPorGasto;

  int conteoDe(SegmentoCliente segmento) => conteoPorSegmento[segmento] ?? 0;

  bool get sinDatos => totalClientes == 0;
}
