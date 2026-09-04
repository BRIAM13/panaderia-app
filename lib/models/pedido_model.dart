import 'cliente_model.dart';

/// Datos mínimos del cliente que trae la respuesta de creación de un
/// pedido — suficientes para armar el resumen post-registro sin tener que
/// volver a pedir la lista completa de clientes.
class PedidoClienteResumen {
  const PedidoClienteResumen({
    required this.dni,
    required this.nombres,
    required this.apellidoPaterno,
    required this.apellidoMaterno,
    required this.descripcionNegocio,
  });

  factory PedidoClienteResumen.fromJson(Map<String, dynamic> json) =>
      PedidoClienteResumen(
        dni: json['dni'] as String?,
        nombres: json['nombres'] as String? ?? '',
        apellidoPaterno: json['apellidoPaterno'] as String? ?? '',
        apellidoMaterno: json['apellidoMaterno'] as String?,
        descripcionNegocio: json['descripcionNegocio'] as String?,
      );

  final String? dni;
  final String nombres;
  final String apellidoPaterno;
  final String? apellidoMaterno;
  final String? descripcionNegocio;

  /// RUC (persona natural o jurídica) muestra solo la razón social; DNI o
  /// sin documento muestran nombre completo con apellidos — misma regla
  /// que [Cliente.nombreParaMostrar].
  String get nombreParaMostrar {
    final esRuc =
        tipoDocumentoDesde(dni) == TipoClienteDocumento.rucPersonaNatural ||
        tipoDocumentoDesde(dni) == TipoClienteDocumento.rucPersonaJuridica;
    if (esRuc) return nombres;
    return [
      nombres,
      apellidoPaterno,
      apellidoMaterno,
    ].where((s) => s != null && s.trim().isNotEmpty).join(' ');
  }

  String? get nombreComercial =>
      (descripcionNegocio != null && descripcionNegocio!.trim().isNotEmpty)
      ? descripcionNegocio
      : null;
}

/// Una línea del carrito de un pedido — un producto con su cantidad y su
/// precio. Un pedido tiene una o varias.
///
/// Los últimos cinco campos solo vienen en pedidos de Horneados, donde lo
/// que distingue a cada línea no es el producto (siempre es el mismo) sino
/// su carne, presentación y aderezo. En cualquier otra tienda llegan null
/// — ver [esHorneado].
class ItemPedido {
  const ItemPedido({
    required this.idPedidoItem,
    required this.idProducto,
    required this.producto,
    required this.tipoPedido,
    required this.cantidad,
    required this.precioUnitario,
    required this.subtotal,
    this.carne,
    this.presentacion,
    this.aplicaAderezo,
    this.tipoAderezo,
    this.precioAderezo,
  });

  factory ItemPedido.fromJson(Map<String, dynamic> json) => ItemPedido(
    // Al crear un pedido el backend responde las líneas ya calculadas pero
    // todavía sin su id (no hace falta para mostrar el resumen), así que
    // acá es opcional; al listarlos siempre viene.
    idPedidoItem: json['idPedidoItem'] as int?,
    idProducto: json['idProducto'] as int,
    producto: json['producto'] as String? ?? '',
    tipoPedido: json['tipoPedido'] as String? ?? 'UNIDADES',
    cantidad: json['cantidad'] as int,
    precioUnitario: (json['precioUnitario'] as num).toDouble(),
    subtotal: (json['subtotal'] as num).toDouble(),
    carne: json['carne'] as String?,
    presentacion: json['presentacion'] as String?,
    aplicaAderezo: json['aplicaAderezo'] as bool?,
    tipoAderezo: json['tipoAderezo'] as String?,
    precioAderezo: (json['precioAderezo'] as num?)?.toDouble(),
  );

  final int? idPedidoItem;
  final int idProducto;
  final String producto;

  /// 'UNIDADES' | 'PAQUETES' — es del producto de ESTA línea, no del pedido
  /// entero.
  final String tipoPedido;
  final int cantidad;
  final double precioUnitario;
  final double subtotal;

  /// Solo Horneados (ver [esHorneado]).
  final String? carne;
  final String? presentacion;
  final bool? aplicaAderezo;
  final String? tipoAderezo;
  final double? precioAderezo;

  bool get esHorneado => carne != null;
  bool get esPaquete => tipoPedido == 'PAQUETES';

  /// "Pan francés" o, en Horneados, "Pollo · Entero" — el nombre del
  /// producto placeholder no distingue nada entre líneas de ese rubro.
  String get descripcion {
    if (!esHorneado) return producto;
    return [carne, presentacion].where((s) => s != null && s.isNotEmpty).join(' · ');
  }
}

/// Lo que devuelven [PedidosService.crear], [crearComoCliente] y
/// [HorneadosService.crearPedido] al registrar un pedido.
class PedidoResultado {
  const PedidoResultado({
    required this.idPedido,
    required this.numeroPedidoDia,
    this.tienda,
    required this.items,
    required this.productoResumen,
    required this.total,
    required this.fechaEntrega,
    required this.fechaCreacion,
    required this.cliente,
  });

  factory PedidoResultado.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>? ?? const [])
        .map((e) => ItemPedido.fromJson(e as Map<String, dynamic>))
        .toList();
    return PedidoResultado(
      idPedido: json['idPedido'] as int,
      numeroPedidoDia: json['numeroPedidoDia'] as int? ?? 0,
      tienda: json['tienda'] as String?,
      items: items,
      productoResumen: json['productoResumen'] as String? ?? '',
      total: (json['total'] as num).toDouble(),
      fechaEntrega: json['fechaEntrega'] != null
          ? DateTime.parse(json['fechaEntrega'] as String).toLocal()
          : null,
      fechaCreacion: DateTime.parse(json['fechaCreacion'] as String).toLocal(),
      cliente: PedidoClienteResumen.fromJson(
        json['cliente'] as Map<String, dynamic>,
      ),
    );
  }

  final int idPedido;

  /// Correlativo #1, #2... que empieza de nuevo cada día calendario (hora
  /// de Perú), independiente por tienda — es lo que se le muestra al
  /// personal/cliente ("Pedido #N"), nunca [idPedido] (la PK real, que
  /// sigue siendo lo único válido para llamar a /pedidos/:id/...).
  final int numeroPedidoDia;

  /// Solo viene en la respuesta de [PedidosService.crearComoCliente] (ver
  /// crearMiPedido en pedidosController.js).
  final String? tienda;

  final List<ItemPedido> items;

  /// "Pan francés x2, Pan de agua x1" — para subtítulos compactos. Nunca
  /// sustituye recorrer [items] donde importa el detalle por producto.
  final String productoResumen;

  final double total;
  final DateTime? fechaEntrega;
  final DateTime fechaCreacion;
  final PedidoClienteResumen cliente;
}

/// Un pedido ya registrado, tal como lo devuelven `GET /pedidos`,
/// `/pedidos/mis-pedidos`, `/pedidos/deudas` y sus equivalentes de
/// Horneados — un mismo shape para todas las tiendas.
class Pedido {
  const Pedido({
    required this.idPedido,
    required this.numeroPedidoDia,
    required this.idCliente,
    required this.idTienda,
    required this.tienda,
    required this.items,
    required this.productoResumen,
    required this.total,
    required this.fechaEntrega,
    required this.estado,
    required this.estadoPago,
    required this.fechaEntregaReal,
    required this.notas,
    required this.fechaCreacion,
    required this.cliente,
    required this.vendedor,
    this.registradoPorRol,
    this.aprobadoPor,
    this.canceladoPor,
    this.entregadoPor,
  });

  factory Pedido.fromJson(Map<String, dynamic> json) => Pedido(
    idPedido: json['idPedido'] as int,
    numeroPedidoDia: json['numeroPedidoDia'] as int? ?? 0,
    idCliente: json['idCliente'] as int,
    idTienda: json['idTienda'] as int?,
    tienda: json['tienda'] as String?,
    items: (json['items'] as List<dynamic>? ?? const [])
        .map((e) => ItemPedido.fromJson(e as Map<String, dynamic>))
        .toList(),
    productoResumen: json['productoResumen'] as String? ?? '',
    total: (json['total'] as num).toDouble(),
    fechaEntrega: json['fechaEntrega'] != null
        ? DateTime.parse(json['fechaEntrega'] as String).toLocal()
        : null,
    estado: json['estado'] as String,
    estadoPago: json['estadoPago'] as String?,
    fechaEntregaReal: json['fechaEntregaReal'] != null
        ? DateTime.parse(json['fechaEntregaReal'] as String).toLocal()
        : null,
    notas: json['notas'] as String?,
    fechaCreacion: DateTime.parse(json['fechaCreacion'] as String).toLocal(),
    cliente: PedidoClienteResumen.fromJson(
      json['cliente'] as Map<String, dynamic>,
    ),
    // null si lo registró el propio cliente (autoservicio), no el personal.
    vendedor: json['vendedor'] as String?,
    // Estos 4 solo vienen del backend si quien pide la lista es
    // ADMIN/SUPERADMIN (ver pedidosController.js) — para TRABAJADOR o el
    // propio cliente siempre llegan null.
    registradoPorRol: json['registradoPorRol'] as String?,
    aprobadoPor: json['aprobadoPor'] as String?,
    canceladoPor: json['canceladoPor'] as String?,
    entregadoPor: json['entregadoPor'] as String?,
  );

  final int idPedido;

  /// Correlativo #1, #2... que empieza de nuevo cada día calendario (hora
  /// de Perú), independiente por tienda — es lo que se muestra al personal/
  /// cliente ("Pedido #N"), nunca [idPedido] (la PK real que identifica el
  /// pedido en /pedidos/:id/...).
  final int numeroPedidoDia;
  final int idCliente;
  final int? idTienda;
  final String? tienda;

  /// Las líneas del carrito. Siempre al menos una.
  final List<ItemPedido> items;

  /// "Pan francés x2, Pan de agua x1" — conveniencia para subtítulos y
  /// listas compactas. Donde importa la cantidad o el precio por producto
  /// (ej. preparar el pedido), hay que recorrer [items].
  final String productoResumen;

  final double total;
  final DateTime? fechaEntrega;
  // 'SOLICITADO' | 'PENDIENTE' | 'RECHAZADO' | 'ENTREGADO' | 'CANCELADO'
  final String estado;
  // 'PAGADO' | 'DEUDA' | null (null hasta que esté ENTREGADO)
  final String? estadoPago;
  final DateTime? fechaEntregaReal;
  final String? notas;
  final DateTime fechaCreacion;
  final PedidoClienteResumen cliente;
  final String? vendedor;

  /// Visibles solo para ADMIN/SUPERADMIN (el backend ya filtra esto, no
  /// hace falta repetir el chequeo de rol acá — si no corresponde, llegan
  /// null y la UI simplemente no muestra nada).
  final String? registradoPorRol;
  final String? aprobadoPor;
  final String? canceladoPor;
  final String? entregadoPor;

  bool get esSolicitado => estado == 'SOLICITADO';
  bool get esEntregado => estado == 'ENTREGADO';
  bool get esDeuda => estadoPago == 'DEUDA';

  /// Cuántos productos distintos tiene el pedido.
  int get cantidadItems => items.length;

  /// La suma de las cantidades de todas las líneas — "cuántas cosas hay que
  /// preparar" en total, a diferencia de [cantidadItems].
  int get cantidadTotalUnidades =>
      items.fold<int>(0, (acc, i) => acc + i.cantidad);

  /// true si el pedido tiene más de un producto — sirve para decidir si la
  /// tarjeta muestra el detalle desplegado o solo el resumen.
  bool get tieneVariosProductos => items.length > 1;

  /// true si es un pedido de Horneados (sus líneas traen carne).
  bool get esHorneado => items.isNotEmpty && items.first.esHorneado;

  /// Ya se resolvió (entregado, rechazado o cancelado) — no necesita más
  /// acción ni debe agruparse por fecha programada (ver Historial en
  /// ListaPedidosPorSeccion). Solo SOLICITADO/PENDIENTE siguen "activos".
  bool get esFinalizado =>
      estado == 'ENTREGADO' || estado == 'RECHAZADO' || estado == 'CANCELADO';

  /// El cliente puede cancelarlo mientras no se haya entregado todavía.
  bool get sePuedeCancelar => estado == 'SOLICITADO' || estado == 'PENDIENTE';
}
