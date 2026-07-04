class Producto {
  const Producto({
    required this.idProducto,
    required this.nombre,
    required this.descripcion,
    required this.precioUnitario,
    required this.stock,
    required this.unidadMedida,
    required this.categoria,
  });

  factory Producto.fromJson(Map<String, dynamic> json) => Producto(
    idProducto: json['idProducto'] as int,
    nombre: json['nombre'] as String,
    descripcion: json['descripcion'] as String?,
    precioUnitario: (json['precioUnitario'] as num).toDouble(),
    stock: json['stock'] as int,
    unidadMedida: json['unidadMedida'] as String,
    categoria: json['categoria'] as String,
  );

  final int idProducto;
  final String nombre;
  final String? descripcion;
  final double precioUnitario;
  final int stock;
  final String unidadMedida;
  final String categoria;
}
