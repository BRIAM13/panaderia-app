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

/// Saldo o vuelto que quedó pendiente después de que el personal verificó
/// un pago adelantado por Yape que no coincidió con el total.
///
/// [monto] es SIEMPRE positivo: quién le debe a quién lo dice [tipo], no el
/// signo (`CK_AjustesPago_Monto` exige `Monto > 0`).
class AjustePago {
  const AjustePago({
    required this.idAjuste,
    required this.idPedido,
    required this.tipo,
    required this.monto,
    required this.estado,
    required this.notas,
    required this.fechaCreacion,
    required this.fechaResolucion,
    this.numeroPedidoDia,
    this.totalPedido,
    this.estadoPedido,
    this.codigoOperacionYape,
    this.montoConfirmadoStaff,
    this.cliente,
  });

  factory AjustePago.fromJson(Map<String, dynamic> json) => AjustePago(
    idAjuste: json['idAjuste'] as int,
    idPedido: json['idPedido'] as int,
    tipo: json['tipo'] as String,
    monto: (json['monto'] as num).toDouble(),
    estado: json['estado'] as String? ?? 'PENDIENTE',
    notas: json['notas'] as String?,
    fechaCreacion: json['fechaCreacion'] != null
        ? DateTime.parse(json['fechaCreacion'] as String).toLocal()
        : null,
    fechaResolucion: json['fechaResolucion'] != null
        ? DateTime.parse(json['fechaResolucion'] as String).toLocal()
        : null,
    // Los de abajo solo vienen en `GET /ajustes-pago` (la lista dedicada),
    // no cuando el ajuste llega colgado de un pedido: ahí esos datos ya los
    // tiene el propio pedido.
    numeroPedidoDia: json['numeroPedidoDia'] as int?,
    totalPedido: (json['totalPedido'] as num?)?.toDouble(),
    estadoPedido: json['estadoPedido'] as String?,
    codigoOperacionYape: json['codigoOperacionYape'] as String?,
    montoConfirmadoStaff: (json['montoConfirmadoStaff'] as num?)?.toDouble(),
    cliente: json['cliente'] != null
        ? PedidoClienteResumen.fromJson(json['cliente'] as Map<String, dynamic>)
        : null,
  );

  final int idAjuste;
  final int idPedido;

  /// 'DEUDA' (el cliente nos debe) | 'VUELTO' (se lo debemos nosotros).
  final String tipo;
  final double monto;

  /// 'PENDIENTE' | 'RESUELTO'.
  final String estado;
  final String? notas;
  final DateTime? fechaCreacion;
  final DateTime? fechaResolucion;

  final int? numeroPedidoDia;
  final double? totalPedido;
  final String? estadoPedido;
  final String? codigoOperacionYape;
  final double? montoConfirmadoStaff;
  final PedidoClienteResumen? cliente;

  bool get esVuelto => tipo == 'VUELTO';
  bool get esPendiente => estado == 'PENDIENTE';

  /// "Te debemos S/ 3.00 de vuelto" / "Nos debe S/ 2.00" — la misma frase
  /// que el personal ve en la tarjeta del pedido y en la lista de ajustes,
  /// para que no haya dos redacciones del mismo hecho.
  String get descripcion => esVuelto
      ? 'Vuelto pendiente: devolver S/ ${monto.toStringAsFixed(2)}'
      : 'Saldo pendiente: cobrar S/ ${monto.toStringAsFixed(2)}';
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
    this.estadoPagoAdelanto,
    this.codigoOperacionYape,
    this.montoDeclaradoCliente,
    this.montoConfirmadoStaff,
    this.ajustePago,
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
    // Pago por adelantado con Yape — solo los pedidos web de Panadería lo
    // usan; el resto llega en 'NO_APLICA' (o null con un backend viejo).
    estadoPagoAdelanto: json['estadoPagoAdelanto'] as String?,
    codigoOperacionYape: json['codigoOperacionYape'] as String?,
    montoDeclaradoCliente: (json['montoDeclaradoCliente'] as num?)?.toDouble(),
    montoConfirmadoStaff: (json['montoConfirmadoStaff'] as num?)?.toDouble(),
    ajustePago: json['ajustePago'] != null
        ? AjustePago.fromJson(json['ajustePago'] as Map<String, dynamic>)
        : null,
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
  // 'SOLICITADO' | 'PENDIENTE' | 'CONFIRMADO' | 'RECHAZADO' | 'ENTREGADO' |
  // 'CANCELADO'. 'CONFIRMADO' es el estado al que llega un pedido web de
  // Panadería una vez que el personal verificó su pago adelantado por Yape:
  // está listo para entregarse, igual que un 'PENDIENTE'.
  final String estado;
  // 'PAGADO' | 'DEUDA' | null (null hasta que esté ENTREGADO). OJO: esto es
  // el FIADO posterior a la entrega, nada que ver con [estadoPagoAdelanto].
  final String? estadoPago;
  final DateTime? fechaEntregaReal;
  final String? notas;
  final DateTime fechaCreacion;
  final PedidoClienteResumen cliente;
  final String? vendedor;

  /// Pago por adelantado con Yape: 'NO_APLICA' | 'VERIFICANDO' | 'PAGADO' |
  /// 'DEUDA_PARCIAL' | 'VUELTO_PENDIENTE'. Solo los pedidos hechos desde la
  /// página web para Panadería salen de 'NO_APLICA'. null con un backend
  /// anterior a esta función — se trata igual que 'NO_APLICA'.
  final String? estadoPagoAdelanto;

  /// El código REAL que emitió Yape, tal como lo escribió el cliente: es lo
  /// que el personal busca en su app de Yape para verificar el movimiento.
  /// null mientras el cliente no lo haya mandado (pedido creado, sin pagar).
  final String? codigoOperacionYape;

  /// Lo que el cliente DIJO haber pagado. Es una pista para el personal,
  /// nunca la base de ninguna cuenta: el monto que manda es el que el
  /// personal ve llegar de verdad.
  final double? montoDeclaradoCliente;

  /// Lo que el personal confirmó que llegó realmente. De acá sale
  /// [estadoPagoAdelanto] y el monto de [ajustePago].
  final double? montoConfirmadoStaff;

  /// Saldo o vuelto de ESTE pedido todavía sin resolver. null en la enorme
  /// mayoría de los pedidos (y también cuando ya se resolvió: el backend
  /// solo manda los pendientes).
  final AjustePago? ajustePago;

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

  /// El pedido se pagó (o se está pagando) por adelantado con Yape — o sea,
  /// es un pedido web de Panadería.
  bool get usaPagoAdelanto =>
      estadoPagoAdelanto != null && estadoPagoAdelanto != 'NO_APLICA';

  /// El cliente ya mandó su código de operación y nadie lo revisó todavía:
  /// es la cola de trabajo de "Pagos por verificar".
  bool get esperaVerificacionPago =>
      estadoPagoAdelanto == 'VERIFICANDO' && codigoOperacionYape != null;

  /// El pedido existe pero el cliente todavía no yapeó (o no mandó su
  /// código). No hay nada que el personal pueda verificar todavía.
  bool get esperaPagoDelCliente =>
      estadoPagoAdelanto == 'VERIFICANDO' && codigoOperacionYape == null;

  /// Pago verificado y listo para entregarse — llegó por el camino del pago
  /// adelantado en vez del "aceptar/rechazar" de siempre.
  bool get esConfirmado => estado == 'CONFIRMADO';

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
  /// 'CONFIRMADO' entra igual que 'PENDIENTE': el pago ya está verificado,
  /// pero el pan todavía no salió — lo que haya que devolverle al cliente se
  /// resuelve por su [ajustePago], no dejando el pedido sin cancelar.
  bool get sePuedeCancelar =>
      estado == 'SOLICITADO' || estado == 'PENDIENTE' || estado == 'CONFIRMADO';

  /// Listo para marcarse entregado: confirmado por el personal ('PENDIENTE')
  /// o con su pago adelantado ya verificado ('CONFIRMADO').
  bool get sePuedeEntregar => estado == 'PENDIENTE' || estado == 'CONFIRMADO';
}
