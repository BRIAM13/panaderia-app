import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../services/api_client.dart';
import '../../services/configuraciones_service.dart';
import '../../utils/text_formatters.dart';
import 'escritorio_hamburguesas.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/premium_button.dart';

const _claveConfigPrecioPaquete = 'PRECIO_PAQUETE';

/// Ajuste del precio global por defecto del paquete de 12 panes de
/// hamburguesa. Solo visible para ADMIN/SUPERADMIN — afecta el valor
/// sugerido en "Nuevo pedido" a partir de este momento (no cambia pedidos
/// ya registrados).
class AjusteCostosPage extends StatefulWidget {
  const AjusteCostosPage({super.key});

  @override
  State<AjusteCostosPage> createState() => _AjusteCostosPageState();
}

class _AjusteCostosPageState extends State<AjusteCostosPage> {
  final _formKey = GlobalKey<FormState>();
  final _precioController = TextEditingController();
  final _configuracionesService = ConfiguracionesService();

  bool _cargando = true;
  bool _guardando = false;
  String? _error;
  String? _mensajeExito;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _precioController.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final valor = await _configuracionesService.obtener(
        _claveConfigPrecioPaquete,
      );
      setState(() => _precioController.text = valor);
    } on ApiException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(() => _error = 'No se pudo cargar el precio actual.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _guardando = true;
      _error = null;
      _mensajeExito = null;
    });

    try {
      final nuevoValor = double.parse(
        _precioController.text.replaceAll(',', '.'),
      ).toStringAsFixed(2);
      await _configuracionesService.actualizar(
        _claveConfigPrecioPaquete,
        nuevoValor,
      );
      setState(() {
        _precioController.text = nuevoValor;
        _mensajeExito = 'Precio actualizado. Se aplicará a los nuevos pedidos.';
      });
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final escritorio = esEscritorio(context);

    return Scaffold(
      appBar: appBarGestion(
        context,
        titulo: 'Ajuste de costos',
        subtitulo: 'Precio sugerido del paquete al registrar pedidos nuevos',
      ),
      body: SafeArea(
        child: _cargando
            ? const Center(child: AppLoadingIndicator())
            : SingleChildScrollView(
                padding: EdgeInsets.all(escritorio ? 32 : 20),
                // Un formulario de un solo campo estirado a 1600px de ancho
                // es ilegible: en escritorio se topa a ancho de panel y se
                // centra, con la tarjeta haciendo de "modal" sobre el fondo.
                child: FormularioEscritorio(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: scheme.secondaryContainer,
                              ),
                              child: PhosphorIcon(
                                PhosphorIconsRegular.currencyCircleDollar,
                                color: scheme.primary,
                                size: 32,
                              ),
                            )
                            .animate()
                            .fadeIn(duration: 300.ms)
                            .scale(
                              begin: const Offset(0.85, 0.85),
                              end: const Offset(1, 1),
                            ),
                        const SizedBox(height: 16),
                        Text(
                          'Precio del paquete de 12 panes',
                          style: theme.textTheme.titleLarge,
                        ).animate().fadeIn(delay: 80.ms, duration: 250.ms),
                        const SizedBox(height: 6),
                        Text(
                          'Este es el precio sugerido que verá el vendedor al registrar un nuevo pedido de paquetes. '
                          'No afecta los pedidos ya registrados.',
                          style: theme.textTheme.bodyMedium,
                        ).animate().fadeIn(delay: 120.ms, duration: 250.ms),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _precioController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: const [DecimalTextInputFormatter()],
                          decoration: const InputDecoration(
                            labelText: 'Precio del paquete (S/)',
                            prefixIcon: PhosphorIcon(PhosphorIconsRegular.tag),
                          ),
                          validator: (v) {
                            final n = double.tryParse(
                              (v ?? '').replaceAll(',', '.'),
                            );
                            if (n == null || n <= 0) {
                              return 'Ingresa un precio válido';
                            }
                            return null;
                          },
                        ).animate().fadeIn(delay: 160.ms, duration: 250.ms),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            style: TextStyle(
                              color: scheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        if (_mensajeExito != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _mensajeExito!,
                            style: const TextStyle(
                              color: Color(0xFF16A34A),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        PremiumButton(
                          label: 'Guardar cambios',
                          icono: PhosphorIconsBold.check,
                          cargando: _guardando,
                          onPressed: _guardar,
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
