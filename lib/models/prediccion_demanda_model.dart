/// La demanda que el modelo espera para un día concreto de una tienda +
/// producto. Contrato definido por `ml_service/esquemas.py`
/// (`PrediccionDia`), servido tal cual por el backend Node.
class PrediccionDia {
  const PrediccionDia({
    required this.fecha,
    required this.diaSemana,
    required this.esFeriado,
    required this.nombreFeriado,
    required this.demandaPredicha,
  });

  factory PrediccionDia.fromJson(Map<String, dynamic> json) => PrediccionDia(
    fecha: DateTime.parse(json['fecha'] as String),
    diaSemana: json['diaSemana'] as String? ?? '',
    esFeriado: json['esFeriado'] as bool? ?? false,
    nombreFeriado: json['nombreFeriado'] as String?,
    demandaPredicha: (json['demandaPredicha'] as num?)?.toInt() ?? 0,
  );

  final DateTime fecha;
  final String diaSemana;
  final bool esFeriado;
  final String? nombreFeriado;
  final int demandaPredicha;
}

/// Respuesta completa del microservicio de predicción para una consulta.
/// [advertencia] y [versionModelo] no son decorativos: el modelo se entrenó
/// con datos SINTÉTICOS, y la pantalla tiene que decirlo — un número que
/// parece dato duro sin serlo es peor que no mostrar nada.
class PrediccionDemanda {
  const PrediccionDemanda({
    required this.nombreTienda,
    required this.nombreProducto,
    required this.unidad,
    required this.versionModelo,
    required this.advertencia,
    required this.predicciones,
  });

  factory PrediccionDemanda.fromJson(Map<String, dynamic> json) =>
      PrediccionDemanda(
        nombreTienda: json['nombreTienda'] as String? ?? '',
        nombreProducto: json['nombreProducto'] as String? ?? '',
        unidad: json['unidad'] as String? ?? 'unidades',
        versionModelo: json['versionModelo'] as String? ?? '',
        advertencia: json['advertencia'] as String? ?? '',
        predicciones: (json['predicciones'] as List<dynamic>? ?? const [])
            .map((e) => PrediccionDia.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final String nombreTienda;
  final String nombreProducto;
  final String unidad;
  final String versionModelo;
  final String advertencia;
  final List<PrediccionDia> predicciones;

  int get demandaTotal =>
      predicciones.fold(0, (acc, p) => acc + p.demandaPredicha);
}
