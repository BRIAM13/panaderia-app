class Tienda {
  const Tienda({
    required this.idTienda,
    required this.nombre,
    required this.slug,
    required this.disponible,
  });

  factory Tienda.fromJson(Map<String, dynamic> json) => Tienda(
    idTienda: json['idTienda'] as int,
    nombre: json['nombre'] as String,
    slug: json['slug'] as String,
    disponible: json['disponible'] as bool? ?? false,
  );

  final int idTienda;
  final String nombre;
  final String slug;

  /// false = "Próximamente" — la tienda existe en el catálogo pero aún no
  /// tiene operación real (sin producto/gestión configurada).
  final bool disponible;
}
