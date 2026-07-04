import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart' show Share;
import 'package:url_launcher/url_launcher.dart';

import '../models/cliente_model.dart';
import '../theme/app_theme.dart';

/// Acciones que puede devolver el sheet, para que la pantalla que lo abrió
/// decida qué hacer (editar / desactivar / reactivar) sin acoplarse a la
/// navegación.
enum ClienteAccion { editar, desactivar, reactivar }

Future<ClienteAccion?> showClienteAccionesSheet(
  BuildContext context,
  Cliente cliente,
) {
  return showModalBottomSheet<ClienteAccion>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _ClienteAccionesSheetContent(cliente: cliente),
  );
}

String _numeroWhatsApp(String telefono) {
  final soloDigitos = telefono.replaceAll(RegExp(r'[^0-9]'), '');
  if (soloDigitos.startsWith('51')) return soloDigitos;
  if (soloDigitos.length == 9) {
    return '51$soloDigitos'; // celular peruano sin código de país
  }
  return soloDigitos;
}

class _ClienteAccionesSheetContent extends StatelessWidget {
  const _ClienteAccionesSheetContent({required this.cliente});

  final Cliente cliente;

  static const _colorReniec = Color(0xFF2563EB);
  static const _colorManual = Color(0xFFEA8C1B);
  static const _colorSinDni = Color(0xFFDC2626);

  Color get _color {
    switch (cliente.calidadDato) {
      case CalidadDato.reniec:
        return _colorReniec;
      case CalidadDato.manual:
        return _colorManual;
      case CalidadDato.sinDni:
        return _colorSinDni;
    }
  }

  IconData get _iconoTipo {
    switch (cliente.tipoDocumento) {
      case TipoClienteDocumento.dni:
        return Icons.person_rounded;
      case TipoClienteDocumento.rucPersonaNatural:
        return Icons.storefront_rounded;
      case TipoClienteDocumento.rucPersonaJuridica:
        return Icons.apartment_rounded;
      case TipoClienteDocumento.sinDocumento:
        return Icons.person_outline_rounded;
    }
  }

  String get _etiquetaDocumento {
    switch (cliente.tipoDocumento) {
      case TipoClienteDocumento.dni:
        return cliente.dni != null
            ? 'DNI ${cliente.dni}'
            : 'Sin DNI registrado';
      case TipoClienteDocumento.rucPersonaNatural:
        return 'RUC ${cliente.dni} · Persona Natural con Negocio';
      case TipoClienteDocumento.rucPersonaJuridica:
        return 'RUC ${cliente.dni} · Persona Jurídica';
      case TipoClienteDocumento.sinDocumento:
        return 'Sin documento registrado';
    }
  }

  String? get _nombreComercialDestacado =>
      cliente.esNegocio ? cliente.nombreComercial : null;

  Future<void> _llamar(BuildContext context) async {
    final telefono = cliente.telefono;
    if (telefono == null || telefono.isEmpty) return;
    await launchUrl(Uri(scheme: 'tel', path: telefono));
  }

  Future<void> _whatsapp(BuildContext context) async {
    final telefono = cliente.telefono;
    if (telefono == null || telefono.isEmpty) return;
    final numero = _numeroWhatsApp(telefono);
    final mensaje = Uri.encodeComponent(
      'Hola ${cliente.nombreParaMostrar}, te contactamos de Corporación Ronceros.',
    );
    await launchUrl(
      Uri.parse('https://wa.me/$numero?text=$mensaje'),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _abrirMapa(BuildContext context) async {
    final direccion = cliente.direccion;
    if (direccion == null || direccion.isEmpty) return;
    final query = Uri.encodeComponent(direccion);
    await launchUrl(
      Uri.parse('https://www.google.com/maps/search/?api=1&query=$query'),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _compartir(BuildContext context) async {
    final buffer = StringBuffer(cliente.nombreParaMostrar);
    if (cliente.dni != null) buffer.write('\n$_etiquetaDocumento');
    if (cliente.telefono != null) buffer.write('\nTel: ${cliente.telefono}');
    if (cliente.email != null) buffer.write('\nEmail: ${cliente.email}');
    if (cliente.direccion != null) {
      buffer.write('\nDirección de entrega: ${cliente.direccion}');
    }
    await Share.share(buffer.toString());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = _color;
    final tieneTelefono =
        cliente.telefono != null && cliente.telefono!.isNotEmpty;
    final tieneDireccion =
        cliente.direccion != null && cliente.direccion!.isNotEmpty;
    final nombreComercial = _nombreComercialDestacado;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: scheme.onSurface.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        color.withValues(alpha: 0.20),
                        color.withValues(alpha: 0.08),
                      ],
                    ),
                    border: Border.all(
                      color: color.withValues(alpha: 0.35),
                      width: 1.4,
                    ),
                  ),
                  child: Icon(_iconoTipo, color: color, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cliente.nombreParaMostrar,
                        style: theme.textTheme.titleLarge,
                      ),
                      if (nombreComercial != null &&
                          nombreComercial.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          nombreComercial,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.secondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 2),
                      Text(
                        _etiquetaDocumento,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (!cliente.activo) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: scheme.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.person_off_rounded,
                      size: 18,
                      color: scheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Este cliente está desactivado. Reactívalo para poder editarlo o registrarle pedidos.',
                        style: TextStyle(
                          color: scheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (tieneDireccion) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.place_outlined,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        cliente.direccion!,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _BotonAccion(
                  icono: Icons.call_rounded,
                  etiqueta: 'Llamar',
                  habilitado: tieneTelefono,
                  onTap: () => _llamar(context),
                ),
                _BotonAccion(
                  icono: Icons.chat_rounded,
                  etiqueta: 'WhatsApp',
                  habilitado: tieneTelefono,
                  onTap: () => _whatsapp(context),
                ),
                _BotonAccion(
                  icono: Icons.map_rounded,
                  etiqueta: 'Mapa',
                  habilitado: tieneDireccion,
                  onTap: () => _abrirMapa(context),
                ),
                _BotonAccion(
                  icono: Icons.share_rounded,
                  etiqueta: 'Compartir',
                  habilitado: true,
                  onTap: () => _compartir(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            if (cliente.activo) ...[
              ListTile(
                leading: const Icon(Icons.edit_rounded),
                title: const Text('Editar cliente'),
                onTap: () => Navigator.of(context).pop(ClienteAccion.editar),
              ),
              ListTile(
                leading: Icon(Icons.person_off_rounded, color: scheme.error),
                title: Text(
                  'Desactivar cliente',
                  style: TextStyle(color: scheme.error),
                ),
                onTap: () =>
                    Navigator.of(context).pop(ClienteAccion.desactivar),
              ),
            ] else
              ListTile(
                leading: Icon(
                  Icons.person_add_alt_1_rounded,
                  color: const Color(0xFF2E7D32),
                ),
                title: const Text(
                  'Reactivar cliente',
                  style: TextStyle(
                    color: Color(0xFF2E7D32),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () => Navigator.of(context).pop(ClienteAccion.reactivar),
              ),
          ],
        ),
      ),
    );
  }
}

class _BotonAccion extends StatelessWidget {
  const _BotonAccion({
    required this.icono,
    required this.etiqueta,
    required this.habilitado,
    required this.onTap,
  });

  final IconData icono;
  final String etiqueta;
  final bool habilitado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = habilitado
        ? scheme.primary
        : scheme.onSurface.withValues(alpha: 0.25);

    return Column(
      children: [
        Material(
          color: color.withValues(alpha: 0.12),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: habilitado ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Icon(icono, color: color, size: 24),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          etiqueta,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
