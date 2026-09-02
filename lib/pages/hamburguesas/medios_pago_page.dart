import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../models/medio_pago_model.dart';
import '../../models/tienda_model.dart';
import '../../services/api_client.dart';
import '../../services/medios_pago_service.dart';
import '../../services/tiendas_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/text_formatters.dart';
import '../../widgets/escritorio.dart';
import '../../widgets/estado_error.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/premium_button.dart';
import '../../widgets/selector_desplegable.dart';
import '../../widgets/tarjeta_3d.dart';

const _tiposMedioPago = ['YAPE', 'PLIN', 'TRANSFERENCIA', 'OTRO'];

/// Gestión de métodos de pago (ADMIN/SUPERADMIN de la tienda): Yape, Plin,
/// transferencia bancaria u otro — estos son los que el cliente ve al
/// pagar una deuda. Se puede tener más de una tienda asignada, por eso
/// esta pantalla primero elige la tienda (si hay más de una) y luego lista
/// sus medios de pago (activos e inactivos, se pueden reactivar).
class MediosPagoPage extends StatefulWidget {
  const MediosPagoPage({super.key});

  @override
  State<MediosPagoPage> createState() => _MediosPagoPageState();
}

class _MediosPagoPageState extends State<MediosPagoPage> {
  final _tiendasService = TiendasService();
  final _mediosPagoService = MediosPagoService();

  bool _cargando = true;
  String? _error;
  List<Tienda> _tiendas = [];
  Tienda? _tiendaSeleccionada;
  List<MedioPago> _medios = [];

  @override
  void initState() {
    super.initState();
    _cargarTiendas();
  }

  Future<void> _cargarTiendas() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final tiendas = await _tiendasService.misTiendas();
      setState(() {
        _tiendas = tiendas;
        _tiendaSeleccionada = tiendas.isNotEmpty ? tiendas.first : null;
      });
      if (_tiendaSeleccionada != null) await _cargarMedios();
    } on ApiException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(() => _error = 'No se pudieron cargar tus tiendas.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _cargarMedios() async {
    if (_tiendaSeleccionada == null) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final medios = await _mediosPagoService.listarPorTienda(
        _tiendaSeleccionada!.idTienda,
      );
      setState(() => _medios = medios);
    } on ApiException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(() => _error = 'No se pudieron cargar los métodos de pago.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _cambiarEstado(MedioPago medio, bool activo) async {
    try {
      await _mediosPagoService.cambiarEstado(medio.idMedioPago, activo: activo);
      _cargarMedios();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.mensaje)));
    }
  }

  Future<void> _abrirFormulario({MedioPago? medioExistente}) async {
    if (_tiendaSeleccionada == null) return;
    final guardado = await showDialog<bool>(
      context: context,
      builder: (context) => _FormularioMedioPago(
        service: _mediosPagoService,
        idTienda: _tiendaSeleccionada!.idTienda,
        medioExistente: medioExistente,
      ),
    );
    if (guardado == true) _cargarMedios();
  }

  @override
  Widget build(BuildContext context) {
    final escritorio = esEscritorio(context);
    final activos = _medios.where((m) => m.estado).length;

    return Scaffold(
      // En escritorio "Agregar método" sube al encabezado: un FAB en la
      // esquina de un monitor ancho queda a media pantalla de distancia de
      // la lista que está mirando el usuario.
      appBar: appBarGestion(
        context,
        titulo: 'Métodos de pago',
        subtitulo: _medios.isEmpty
            ? 'Yape, Plin o transferencia para cobrar deudas'
            : '${_medios.length} configurado(s) · $activos activo(s)',
        acciones: [
          // Variante `compacto` y sin Padding propio — mismo criterio que
          // en Pedidos: appBarGestion ya centra cada acción dentro de su
          // toolbarHeight fijo (72), y el PremiumButton normal (~54 px de
          // alto) ahí adentro pesa más que el título de la pantalla. Ver
          // el comentario largo en `pedidos_page.dart`.
          if (escritorio && _tiendaSeleccionada != null)
            PremiumButton(
              label: 'Agregar método',
              icono: PhosphorIconsBold.plus,
              expandido: false,
              compacto: true,
              onPressed: () => _abrirFormulario(),
            ),
        ],
      ),
      floatingActionButton: escritorio || _tiendaSeleccionada == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _abrirFormulario(),
              icon: const PhosphorIcon(PhosphorIconsBold.plus),
              label: const Text('Agregar método'),
            ),
      body: SafeArea(child: _construirCuerpo()),
    );
  }

  Widget _construirCuerpo() {
    if (_cargando && _tiendas.isEmpty) {
      return const Center(child: AppLoadingIndicator());
    }
    if (_error != null && _tiendas.isEmpty) {
      return EstadoError(mensaje: _error!, onReintentar: _cargarTiendas);
    }
    if (_tiendas.isEmpty) {
      return EstadoVacio(
        icono: PhosphorIconsDuotone.storefront,
        titulo: 'No tienes tiendas asignadas',
      );
    }

    final escritorio = esEscritorio(context);

    final tarjetas = _medios.asMap().entries.map(
      (entry) =>
          _TarjetaMedioPago(
                medio: entry.value,
                onEditar: () => _abrirFormulario(medioExistente: entry.value),
                onCambiarEstado: (activo) =>
                    _cambiarEstado(entry.value, activo),
              )
              .animate(delay: (60 * entry.key).ms)
              .fadeIn(duration: 300.ms)
              .moveY(begin: 10, end: 0)
              .flipH(begin: 0.12, end: 0, duration: 320.ms),
    );

    return RefreshIndicator(
      onRefresh: _cargarMedios,
      child: ContenidoCentrado(
        anchoMaximo: 1400,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            escritorio ? 28 : 20,
            escritorio ? 20 : 12,
            escritorio ? 28 : 20,
            escritorio ? 40 : 100,
          ),
          children: [
            if (_tiendas.length > 1) ...[
              // El selector de tienda es un combo de una palabra: estirado
              // a todo el ancho de un monitor se ve absurdo.
              SizedBox(
                width: escritorio ? 340 : double.infinity,
                child: SelectorDesplegable<Tienda>(
                  valor: _tiendaSeleccionada,
                  opciones: _tiendas,
                  etiqueta: (t) => t.nombre,
                  label: 'Tienda',
                  icono: PhosphorIconsRegular.storefront,
                  onChanged: (t) {
                    setState(() => _tiendaSeleccionada = t);
                    _cargarMedios();
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (_cargando)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: AppLoadingIndicator()),
              )
            else if (_medios.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: EstadoVacio(
                  icono: PhosphorIconsDuotone.wallet,
                  titulo: 'Aún no configuraste ningún método de pago',
                  subtitulo:
                      'Agrega Yape, Plin, transferencia u otro para que tus '
                      'clientes puedan pagar sus deudas.',
                ),
              )
            else if (!escritorio)
              ...tarjetas
            else
              // Escritorio: los métodos de pago son pocos y de alto
              // parejo — en grilla se ven todos de un vistazo, en vez de
              // una sola columna de tarjetas anchísimas.
              LayoutBuilder(
                builder: (context, constraints) {
                  const separacion = 16.0;
                  const anchoObjetivo = 420.0;
                  final columnas =
                      ((constraints.maxWidth + separacion) /
                              (anchoObjetivo + separacion))
                          .floor()
                          .clamp(1, 3);
                  final ancho =
                      (constraints.maxWidth - separacion * (columnas - 1)) /
                      columnas;
                  return Wrap(
                    spacing: separacion,
                    runSpacing: 0,
                    children: tarjetas
                        .map((t) => SizedBox(width: ancho, child: t))
                        .toList(),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _TarjetaMedioPago extends StatelessWidget {
  const _TarjetaMedioPago({
    required this.medio,
    required this.onEditar,
    required this.onCambiarEstado,
  });

  final MedioPago medio;
  final VoidCallback onEditar;
  final ValueChanged<bool> onCambiarEstado;

  IconData get _icono {
    switch (medio.tipo) {
      case 'YAPE':
      case 'PLIN':
        return PhosphorIconsRegular.deviceMobile;
      case 'TRANSFERENCIA':
        return PhosphorIconsRegular.bank;
      default:
        return PhosphorIconsRegular.money;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Tarjeta3D(
        borderRadius: 18,
        child: Container(
          color: AppColors.surface,
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PhosphorIcon(_icono, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      medio.etiquetaTipo,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${medio.titular} · ${medio.numeroDestino}',
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (medio.nombreBanco != null)
                      Text(
                        medio.nombreBanco!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 12,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PhosphorIcon(
                          medio.imagenQrBase64 != null
                              ? PhosphorIconsRegular.qrCode
                              : PhosphorIconsRegular.qrCode,
                          size: 14,
                          color: medio.imagenQrBase64 != null
                              ? const Color(0xFF2E7D32)
                              : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          medio.imagenQrBase64 != null
                              ? 'QR real subido'
                              : 'Sin QR real — solo informativo',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: medio.imagenQrBase64 != null
                                ? const Color(0xFF2E7D32)
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onEditar,
                icon: const PhosphorIcon(
                  PhosphorIconsRegular.pencilSimple,
                  size: 20,
                ),
              ),
              Switch(value: medio.estado, onChanged: onCambiarEstado),
            ],
          ),
        ),
      ),
    );
  }
}

class _FormularioMedioPago extends StatefulWidget {
  const _FormularioMedioPago({
    required this.service,
    required this.idTienda,
    this.medioExistente,
  });

  final MediosPagoService service;
  final int idTienda;
  final MedioPago? medioExistente;

  @override
  State<_FormularioMedioPago> createState() => _FormularioMedioPagoState();
}

class _FormularioMedioPagoState extends State<_FormularioMedioPago> {
  final _formKey = GlobalKey<FormState>();
  late String _tipo;
  final _titularController = TextEditingController();
  final _numeroController = TextEditingController();
  final _cciController = TextEditingController();
  final _bancoController = TextEditingController();
  final _notasController = TextEditingController();
  final _imagePicker = ImagePicker();

  bool _guardando = false;
  String? _error;

  /// QR real (descargado de la propia app de Yape/Plin) que se va a
  /// guardar — precargado con el que ya tenía el medio de pago, si se está
  /// editando uno que ya tiene uno subido.
  String? _imagenQrBase64;

  bool get _esEdicion => widget.medioExistente != null;

  @override
  void initState() {
    super.initState();
    final medio = widget.medioExistente;
    _tipo = medio?.tipo ?? 'YAPE';
    _titularController.text = medio?.titular ?? '';
    _numeroController.text = medio?.numeroDestino ?? '';
    _cciController.text = medio?.cci ?? '';
    _bancoController.text = medio?.nombreBanco ?? '';
    _notasController.text = medio?.notas ?? '';
    _imagenQrBase64 = medio?.imagenQrBase64;
  }

  Future<void> _elegirImagenQr(ImageSource origen) async {
    try {
      final archivo = await _imagePicker.pickImage(
        source: origen,
        // Un QR no necesita alta resolución — esto mantiene el archivo
        // liviano para no acercarse al límite del body del backend.
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (archivo == null) return;
      final bytes = await archivo.readAsBytes();
      if (!mounted) return;
      setState(() => _imagenQrBase64 = base64Encode(bytes));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo cargar la imagen.')),
      );
    }
  }

  Future<void> _elegirOrigenImagen() async {
    final origen = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const PhosphorIcon(PhosphorIconsRegular.images),
              title: const Text('Elegir de la galería'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const PhosphorIcon(PhosphorIconsRegular.camera),
              title: const Text('Tomar una foto'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (origen != null) await _elegirImagenQr(origen);
  }

  @override
  void dispose() {
    _titularController.dispose();
    _numeroController.dispose();
    _cciController.dispose();
    _bancoController.dispose();
    _notasController.dispose();
    super.dispose();
  }

  String get _labelNumero {
    switch (_tipo) {
      case 'YAPE':
        return 'Número de Yape';
      case 'PLIN':
        return 'Número de Plin';
      case 'TRANSFERENCIA':
        return 'Número de cuenta';
      default:
        return 'Número o referencia';
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _guardando = true;
      _error = null;
    });

    final input = MedioPagoInput(
      tipo: _tipo,
      titular: _titularController.text.trim(),
      numeroDestino: _numeroController.text.trim(),
      cci: _tipo == 'TRANSFERENCIA' ? _cciController.text.trim() : null,
      nombreBanco:
          _tipo == 'TRANSFERENCIA' && _bancoController.text.trim().isNotEmpty
          ? _bancoController.text.trim()
          : null,
      notas: _notasController.text.trim().isEmpty
          ? null
          : _notasController.text.trim(),
      imagenQrBase64: _imagenQrBase64,
    );

    try {
      if (_esEdicion) {
        await widget.service.actualizar(
          widget.medioExistente!.idMedioPago,
          input,
        );
      } else {
        await widget.service.crear(widget.idTienda, input);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(
        () => _error = 'Ocurrió un error inesperado. Intenta nuevamente.',
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // El AlertDialog de Material topa el contenido en 280px de ancho: en
    // escritorio este formulario (tipo, titular, número, CCI, banco, QR)
    // quedaba en una columna angostísima en medio de la pantalla.
    final anchoDialogo = esEscritorio(context) ? 520.0 : null;

    return AlertDialog(
      title: Text(
        _esEdicion ? 'Editar método de pago' : 'Nuevo método de pago',
      ),
      content: SizedBox(
        width: anchoDialogo,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!_esEdicion) ...[
                  SelectorDesplegable<String>(
                    valor: _tipo,
                    opciones: _tiposMedioPago,
                    etiqueta: _etiquetaTipo,
                    label: 'Tipo',
                    onChanged: (v) => setState(() => _tipo = v!),
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _titularController,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: const [UpperCaseTextFormatter()],
                  decoration: const InputDecoration(labelText: 'Titular'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _numeroController,
                  decoration: InputDecoration(labelText: _labelNumero),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                ),
                if (_tipo == 'TRANSFERENCIA') ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _cciController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'CCI (20 dígitos)',
                    ),
                    validator: (v) =>
                        (v == null || !RegExp(r'^\d{20}$').hasMatch(v.trim()))
                        ? 'Debe tener 20 dígitos'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _bancoController,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: const [UpperCaseTextFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'Banco (opcional)',
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notasController,
                  decoration: const InputDecoration(
                    labelText: 'Notas para el cliente (opcional)',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                Text(
                  'QR real de Yape/Plin (opcional, pero recomendado)',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Descárgalo desde la propia app (Mi QR → Descargar) y '
                  'súbelo aquí — es el único que Yape/Plin reconocen al '
                  'escanear. Sin esto, el cliente solo ve un QR informativo.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                InkWell(
                  onTap: _elegirOrigenImagen,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    height: _imagenQrBase64 != null ? 160 : 90,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.secondary.withValues(alpha: 0.35),
                      ),
                      color: AppColors.surfaceMuted,
                    ),
                    alignment: Alignment.center,
                    child: _imagenQrBase64 != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(13),
                            child: Image.memory(
                              base64Decode(_imagenQrBase64!),
                              height: 160,
                              fit: BoxFit.contain,
                            ),
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              PhosphorIcon(
                                PhosphorIconsRegular.cameraPlus,
                                color: AppColors.primary,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Subir imagen del QR',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                  ),
                ),
                if (_imagenQrBase64 != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _imagenQrBase64 = null),
                      icon: const PhosphorIcon(PhosphorIconsBold.x, size: 16),
                      label: const Text('Quitar imagen'),
                    ),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: _guardando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }

  String _etiquetaTipo(String tipo) {
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
