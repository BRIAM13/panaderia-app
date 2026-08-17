import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../models/tienda_model.dart';
import '../../services/api_client.dart';
import '../../services/pedidos_service.dart' show ProductoAutoservicio;
import '../../services/tiendas_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/text_formatters.dart';
import '../../widgets/estado_error.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/tarjeta_3d.dart';

/// Ajuste de precios del catálogo de una tienda (ADMIN/SUPERADMIN): elegir
/// un producto de la lista y modificar su precio por unidad. El precio
/// nuevo aplica desde ese momento — no cambia pedidos ya registrados (mismo
/// criterio que `AjusteCostosPage`, la versión de Hamburguesas para el
/// precio del paquete de 12).
class AjustePreciosPage extends StatefulWidget {
  const AjustePreciosPage({super.key, required this.tienda});

  final Tienda tienda;

  @override
  State<AjustePreciosPage> createState() => _AjustePreciosPageState();
}

class _AjustePreciosPageState extends State<AjustePreciosPage> {
  final _tiendasService = TiendasService();

  bool _cargando = true;
  String? _error;
  List<ProductoAutoservicio> _productos = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final productos = await _tiendasService.listarProductos(
        widget.tienda.idTienda,
      );
      if (mounted) setState(() => _productos = productos);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo cargar el catálogo.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _editarPrecio(ProductoAutoservicio producto) async {
    final nuevoPrecio = await showDialog<double>(
      context: context,
      builder: (context) => _DialogoEditarPrecio(
        producto: producto,
        tienda: widget.tienda,
        tiendasService: _tiendasService,
      ),
    );
    if (nuevoPrecio == null) return;

    setState(() {
      _productos = _productos
          .map(
            (p) => p.idProducto == producto.idProducto
                ? ProductoAutoservicio(
                    idProducto: p.idProducto,
                    nombre: p.nombre,
                    precioUnitario: nuevoPrecio,
                    esPaquete: p.esPaquete,
                  )
                : p,
          )
          .toList();
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Precio de ${producto.nombre} actualizado.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustar precios')),
      body: SafeArea(
        child: _cargando
            ? const Center(child: AppLoadingIndicator())
            : _error != null
            ? EstadoError(mensaje: _error!, onReintentar: _cargar)
            : _productos.isEmpty
            ? EstadoVacio(
                icono: Icons.bakery_dining_rounded,
                titulo: 'Todavía no hay productos en el catálogo',
                subtitulo: 'Los panes de ${widget.tienda.nombre} van a aparecer acá.',
                onRefrescar: _cargar,
              )
            : RefreshIndicator(
                onRefresh: _cargar,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  children: [
                    Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.secondaryContainer,
                          ),
                          child: const Icon(
                            Icons.price_change_rounded,
                            color: AppColors.primary,
                            size: 30,
                          ),
                        )
                        .animate()
                        .fadeIn(duration: 300.ms)
                        .scale(
                          begin: const Offset(0.85, 0.85),
                          end: const Offset(1, 1),
                        ),
                    const SizedBox(height: 14),
                    Text(
                      'Precios de ${widget.tienda.nombre}',
                      style: theme.textTheme.titleLarge,
                    ).animate().fadeIn(delay: 80.ms, duration: 250.ms),
                    const SizedBox(height: 4),
                    Text(
                      'Toca un pan para cambiar su precio por unidad. No afecta pedidos ya registrados.',
                      style: theme.textTheme.bodyMedium,
                    ).animate().fadeIn(delay: 120.ms, duration: 250.ms),
                    const SizedBox(height: 20),
                    ..._productos.asMap().entries.map(
                      (entry) => _TarjetaProductoPrecio(
                            producto: entry.value,
                            onTap: () => _editarPrecio(entry.value),
                          )
                          .animate(delay: (40 * entry.key).ms)
                          .fadeIn(duration: 250.ms)
                          .moveY(begin: 8, end: 0),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _TarjetaProductoPrecio extends StatelessWidget {
  const _TarjetaProductoPrecio({required this.producto, required this.onTap});

  final ProductoAutoservicio producto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Tarjeta3D(
        onTap: onTap,
        borderRadius: 20,
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            splashColor: AppColors.primary.withValues(alpha: 0.08),
            highlightColor: AppColors.primary.withValues(alpha: 0.04),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.primary.withValues(alpha: 0.20),
                          AppColors.primary.withValues(alpha: 0.08),
                        ],
                      ),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.35),
                        width: 1.4,
                      ),
                    ),
                    child: const Icon(
                      Icons.bakery_dining_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      producto.nombre,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Chip(
                    avatar: const Icon(
                      Icons.sell_outlined,
                      size: 15,
                      color: AppColors.primary,
                    ),
                    label: Text(
                      'S/ ${producto.precioUnitario.toStringAsFixed(2)}',
                    ),
                    labelStyle: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                    backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                    side: BorderSide.none,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppColors.textSecondary.withValues(alpha: 0.6),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DialogoEditarPrecio extends StatefulWidget {
  const _DialogoEditarPrecio({
    required this.producto,
    required this.tienda,
    required this.tiendasService,
  });

  final ProductoAutoservicio producto;
  final Tienda tienda;
  final TiendasService tiendasService;

  @override
  State<_DialogoEditarPrecio> createState() => _DialogoEditarPrecioState();
}

class _DialogoEditarPrecioState extends State<_DialogoEditarPrecio> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _precioController;

  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _precioController = TextEditingController(
      text: widget.producto.precioUnitario.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _precioController.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    final precio = double.parse(_precioController.text.replaceAll(',', '.'));

    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final precioGuardado = await widget.tiendasService
          .actualizarPrecioProducto(
            idTienda: widget.tienda.idTienda,
            idProducto: widget.producto.idProducto,
            precioUnitario: precio,
          );
      if (!mounted) return;
      Navigator.of(context).pop(precioGuardado);
    } on ApiException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(() => _error = 'No se pudo actualizar el precio.');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AlertDialog(
      icon: Container(
        width: 56,
        height: 56,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.secondaryContainer,
        ),
        child: const Icon(
          Icons.sell_outlined,
          color: AppColors.primary,
          size: 26,
        ),
      ),
      title: Text(widget.producto.nombre, textAlign: TextAlign.center),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _precioController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: const [DecimalTextInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Precio por unidad (S/)',
                prefixIcon: Icon(Icons.sell_outlined),
              ),
              validator: (v) {
                final n = double.tryParse((v ?? '').replaceAll(',', '.'));
                if (n == null || n <= 0) {
                  return 'Ingresa un precio válido';
                }
                return null;
              },
              onFieldSubmitted: (_) => _guardar(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(
                  color: scheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.of(context).pop(),
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
}
