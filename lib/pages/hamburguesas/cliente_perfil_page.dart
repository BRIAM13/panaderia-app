import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../models/cliente_model.dart';
import '../../models/perfil_cliente_model.dart';
import '../../services/api_client.dart';
import '../../services/clientes_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/segmento_utils.dart';
import '../../widgets/escritorio.dart';
import '../../widgets/estado_error.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/premium_button.dart';
import 'cliente_form_page.dart';

/// Perfil de cliente del CRM: historial agregado, segmento automático,
/// puntos de fidelidad (con canje) y notas internas del personal — todo lo
/// que el módulo de Clientes ya guardaba pero nunca mostraba junto.
///
/// Es una cáscara delgada (Scaffold + AppBar) sobre [ClientePerfilVista],
/// que es donde vive todo el contenido y la carga de datos. Esa separación
/// existe porque en escritorio el mismo perfil se muestra EMBEBIDO en el
/// panel derecho de la lista de Clientes, sin navegar a otra ruta.
class ClientePerfilPage extends StatefulWidget {
  const ClientePerfilPage({super.key, required Cliente this.cliente})
    : _idCliente = null;

  /// Entrada desde pantallas que solo conocen el id (ver `AnaliticaPage`,
  /// que carga un resumen liviano de toda la cartera y no la ficha completa
  /// de cada cliente). La ficha llega igual en la primera carga: el propio
  /// endpoint de perfil ya la devuelve.
  const ClientePerfilPage.porId({super.key, required int idCliente})
    : cliente = null,
      _idCliente = idCliente;

  final Cliente? cliente;
  final int? _idCliente;

  int get idCliente => cliente?.idCliente ?? _idCliente!;

  @override
  State<ClientePerfilPage> createState() => _ClientePerfilPageState();
}

class _ClientePerfilPageState extends State<ClientePerfilPage> {
  /// El botón "Editar" vive en el AppBar (fuera de la vista), así que
  /// necesita una llave para pedirle a la vista que abra el formulario.
  final _vistaKey = GlobalKey<ClientePerfilVistaState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBarGestion(
        context,
        titulo: 'Perfil del cliente',
        subtitulo: 'Historial, segmento, puntos y notas internas',
        acciones: [
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            tooltip: 'Editar cliente',
            onPressed: () => _vistaKey.currentState?.editar(),
          ),
        ],
      ),
      body: SafeArea(
        child: ClientePerfilVista(
          key: _vistaKey,
          idCliente: widget.idCliente,
          clienteInicial: widget.cliente,
        ),
      ),
    );
  }
}

/// El contenido del perfil, sin barra ni Scaffold — reutilizable tal cual
/// como panel de detalle en el maestro-detalle de escritorio.
class ClientePerfilVista extends StatefulWidget {
  const ClientePerfilVista({
    super.key,
    required this.idCliente,
    this.clienteInicial,
    this.embebido = false,
    this.onCambio,
  });

  final int idCliente;
  final Cliente? clienteInicial;

  /// true cuando la vista vive dentro del panel derecho de Clientes: como
  /// ahí no hay AppBar, se dibuja su propia barra de acciones arriba.
  final bool embebido;

  /// Aviso al maestro de que algo cambió (se editó el cliente, se canjearon
  /// puntos) para que refresque su lista.
  final VoidCallback? onCambio;

  @override
  State<ClientePerfilVista> createState() => ClientePerfilVistaState();
}

class ClientePerfilVistaState extends State<ClientePerfilVista> {
  final _clientesService = ClientesService();
  final _notaController = TextEditingController();

  PerfilCliente? _perfil;
  List<NotaCliente> _notas = [];
  bool _cargando = true;
  bool _guardandoNota = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _notaController.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final resultados = await Future.wait([
        _clientesService.obtenerPerfil(widget.idCliente),
        _clientesService.listarNotas(widget.idCliente),
      ]);
      setState(() {
        _perfil = resultados[0] as PerfilCliente;
        _notas = resultados[1] as List<NotaCliente>;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(() => _error = 'No se pudo cargar el perfil del cliente.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  /// La ficha a editar sale del perfil ya cargado (no de
  /// `widget.clienteInicial`), que es la versión recién traída del servidor y
  /// existe también cuando se entró solo con el id.
  ///
  /// Público: lo dispara el botón del AppBar de [ClientePerfilPage], que vive
  /// fuera de este widget.
  Future<void> editar() async {
    final cliente = _perfil?.cliente ?? widget.clienteInicial;
    if (cliente == null) return;

    final guardado = await pushSlideUpFade<bool>(
      context,
      (_) => ClienteFormPage(clienteExistente: cliente),
    );
    if (guardado == true) {
      await _cargar();
      widget.onCambio?.call();
    }
  }

  Future<void> _agregarNota() async {
    final texto = _notaController.text.trim();
    if (texto.isEmpty) return;

    setState(() => _guardandoNota = true);
    try {
      await _clientesService.crearNota(widget.idCliente, texto);
      _notaController.clear();
      final notas = await _clientesService.listarNotas(
        widget.idCliente,
      );
      if (!mounted) return;
      setState(() => _notas = notas);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.mensaje)));
    } finally {
      if (mounted) setState(() => _guardandoNota = false);
    }
  }

  Future<void> _abrirCanjePuntos() async {
    final perfil = _perfil;
    if (perfil == null) return;

    final resultado = await showDialog<int>(
      context: context,
      builder: (context) =>
          _DialogoCanjePuntos(saldoActual: perfil.cliente.puntosFidelidad),
    );
    if (resultado == null || !mounted) return;

    try {
      await _clientesService.canjearPuntos(widget.idCliente, resultado);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Se canjearon $resultado puntos.')),
      );
      await _cargar();
      widget.onCambio?.call();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.mensaje)));
    }
  }

  @override
  Widget build(BuildContext context) => _construirCuerpo();

  Widget _construirCuerpo() {
    if (_cargando) {
      return const Center(child: AppLoadingIndicator());
    }
    if (_error != null) {
      return EstadoError(mensaje: _error!, onReintentar: _cargar);
    }

    final perfil = _perfil!;
    // Embebido en el panel de detalle hay más ancho: el historial pasa a una
    // sola fila de 4 métricas (en vez de 2x2) y el bloque respira más.
    final embebido = widget.embebido;

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: embebido
            ? const EdgeInsets.fromLTRB(24, 20, 24, 40)
            : const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          if (embebido) ...[
            _BarraAccionesPerfil(
              onEditar: editar,
              onRecargar: _cargar,
            ).animate().fadeIn(duration: 200.ms),
            const SizedBox(height: 16),
          ],
          _EncabezadoCliente(perfil: perfil)
              .animate()
              .fadeIn(duration: 250.ms)
              .moveY(begin: 8, end: 0),
          const SizedBox(height: 16),
          _TarjetaHistorial(historial: perfil.historial, enFila: embebido)
              .animate(delay: 60.ms)
              .fadeIn(duration: 250.ms)
              .moveY(begin: 8, end: 0),
          const SizedBox(height: 16),
          _TarjetaPuntos(
                puntos: perfil.cliente.puntosFidelidad,
                onCanjear: _abrirCanjePuntos,
              )
              .animate(delay: 100.ms)
              .fadeIn(duration: 250.ms)
              .moveY(begin: 8, end: 0),
          const SizedBox(height: 16),
          _SeccionNotas(
                notas: _notas,
                controller: _notaController,
                guardando: _guardandoNota,
                onAgregar: _agregarNota,
              )
              .animate(delay: 140.ms)
              .fadeIn(duration: 250.ms)
              .moveY(begin: 8, end: 0),
        ],
      ),
    );
  }
}

/// Barra de acciones del perfil cuando se muestra embebido (sin AppBar que
/// las aloje).
class _BarraAccionesPerfil extends StatelessWidget {
  const _BarraAccionesPerfil({required this.onEditar, required this.onRecargar});

  final VoidCallback onEditar;
  final VoidCallback onRecargar;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton.icon(
          onPressed: onRecargar,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Actualizar'),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: onEditar,
          icon: const Icon(Icons.edit_rounded, size: 18),
          label: const Text('Editar cliente'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ],
    );
  }
}

class _EncabezadoCliente extends StatelessWidget {
  const _EncabezadoCliente({required this.perfil});

  final PerfilCliente perfil;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cliente = perfil.cliente;
    final etiqueta = etiquetaSegmento(perfil.segmento);
    final direccion = cliente.direccion;
    final telefono = cliente.telefono;
    final email = cliente.email;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      etiqueta.color.withValues(alpha: 0.20),
                      etiqueta.color.withValues(alpha: 0.08),
                    ],
                  ),
                  border: Border.all(
                    color: etiqueta.color.withValues(alpha: 0.35),
                    width: 1.4,
                  ),
                ),
                child: Icon(etiqueta.icono, color: etiqueta.color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(cliente.nombreParaMostrar, style: theme.textTheme.titleLarge),
                    if (cliente.esNegocio) ...[
                      const SizedBox(height: 2),
                      Text(
                        cliente.nombreComercial!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.secondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Chip(
                      avatar: Icon(etiqueta.icono, size: 15, color: etiqueta.color),
                      label: Text(etiqueta.texto),
                      labelStyle: TextStyle(
                        color: etiqueta.color,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                      backgroundColor: etiqueta.color.withValues(alpha: 0.1),
                      side: BorderSide.none,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (cliente.dni != null) _FilaDato(icono: Icons.badge_outlined, texto: cliente.dni!),
          if (telefono != null && telefono.isNotEmpty)
            _FilaDato(icono: Icons.call_outlined, texto: telefono),
          if (email != null && email.isNotEmpty)
            _FilaDato(icono: Icons.email_outlined, texto: email),
          if (direccion != null && direccion.isNotEmpty)
            _FilaDato(icono: Icons.place_outlined, texto: direccion),
        ],
      ),
    );
  }
}

class _FilaDato extends StatelessWidget {
  const _FilaDato({required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(icono, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(texto, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _TarjetaHistorial extends StatelessWidget {
  const _TarjetaHistorial({required this.historial, this.enFila = false});

  final HistorialCliente historial;

  /// true en el panel de detalle de escritorio: las 4 métricas van en una
  /// sola fila en vez de la grilla 2x2 pensada para un celular angosto.
  final bool enFila;

  String get _ultimaCompraTexto {
    final dias = historial.diasDesdeUltimaCompra;
    if (dias == null) return 'Sin compras aún';
    if (dias == 0) return 'Hoy';
    if (dias == 1) return 'Ayer';
    return 'Hace $dias días';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final metricas = <Widget>[
      _EstadisticaChica(
        etiqueta: 'Gastado',
        valor: 'S/ ${historial.totalGastado.toStringAsFixed(2)}',
        icono: Icons.payments_outlined,
      ),
      _EstadisticaChica(
        etiqueta: 'Entregados',
        valor: '${historial.pedidosEntregados}',
        icono: Icons.local_shipping_outlined,
      ),
      _EstadisticaChica(
        etiqueta: 'Deuda pendiente',
        valor: 'S/ ${historial.deudaPendiente.toStringAsFixed(2)}',
        icono: Icons.warning_amber_outlined,
        destacar: historial.deudaPendiente > 0,
      ),
      _EstadisticaChica(
        etiqueta: 'Última compra',
        valor: _ultimaCompraTexto,
        icono: Icons.event_outlined,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Historial de compras', style: theme.textTheme.titleMedium),
          const SizedBox(height: 14),
          if (enFila)
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < metricas.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: metricas[i]),
                ],
              ],
            )
          else ...[
            Row(
              children: [
                Expanded(child: metricas[0]),
                const SizedBox(width: 12),
                Expanded(child: metricas[1]),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: metricas[2]),
                const SizedBox(width: 12),
                Expanded(child: metricas[3]),
              ],
            ),
          ],
          if (historial.tiendas.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: historial.tiendas
                  .map(
                    (t) => Chip(
                      label: Text(t.nombre),
                      backgroundColor: AppColors.surfaceMuted,
                      side: BorderSide.none,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _EstadisticaChica extends StatelessWidget {
  const _EstadisticaChica({
    required this.etiqueta,
    required this.valor,
    required this.icono,
    this.destacar = false,
  });

  final String etiqueta;
  final String valor;
  final IconData icono;
  final bool destacar;

  @override
  Widget build(BuildContext context) {
    final color = destacar ? AppColors.error : AppColors.primary;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 18, color: color),
          const SizedBox(height: 6),
          Text(
            valor,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            etiqueta,
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _TarjetaPuntos extends StatelessWidget {
  const _TarjetaPuntos({required this.puntos, required this.onCanjear});

  final int puntos;
  final VoidCallback onCanjear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.secondary],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.stars_rounded, color: Colors.white, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$puntos puntos de fidelidad',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Se ganan al entregar pedidos',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: puntos > 0 ? onCanjear : null,
            style: TextButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.18),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Canjear'),
          ),
        ],
      ),
    );
  }
}

class _DialogoCanjePuntos extends StatefulWidget {
  const _DialogoCanjePuntos({required this.saldoActual});

  final int saldoActual;

  @override
  State<_DialogoCanjePuntos> createState() => _DialogoCanjePuntosState();
}

class _DialogoCanjePuntosState extends State<_DialogoCanjePuntos> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirmar() {
    final puntos = int.tryParse(_controller.text.trim());
    if (puntos == null || puntos <= 0) {
      setState(() => _error = 'Ingresa un número de puntos válido.');
      return;
    }
    if (puntos > widget.saldoActual) {
      setState(() => _error = 'El cliente solo tiene ${widget.saldoActual} puntos.');
      return;
    }
    Navigator.of(context).pop(puntos);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Canjear puntos'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Saldo actual: ${widget.saldoActual} puntos'),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Puntos a canjear',
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _confirmar, child: const Text('Canjear')),
      ],
    );
  }
}

class _SeccionNotas extends StatelessWidget {
  const _SeccionNotas({
    required this.notas,
    required this.controller,
    required this.guardando,
    required this.onAgregar,
  });

  final List<NotaCliente> notas;
  final TextEditingController controller;
  final bool guardando;
  final VoidCallback onAgregar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Notas internas', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Solo las ve el personal, nunca el cliente.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          if (notas.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Todavía no hay notas para este cliente.',
                style: theme.textTheme.bodyMedium,
              ),
            )
          else
            ...notas.map(
              (nota) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nota.texto, style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 6),
                      Text(
                        '${nota.autor} · ${_formatearFecha(nota.fechaCreacion)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Escribe una nota sobre este cliente...',
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: PremiumButton(
              label: 'Agregar nota',
              icono: Icons.note_add_outlined,
              relleno: false,
              cargando: guardando,
              onPressed: onAgregar,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatearFecha(DateTime fecha) {
  const meses = [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];
  return '${fecha.day} ${meses[fecha.month - 1]} ${fecha.year}';
}
