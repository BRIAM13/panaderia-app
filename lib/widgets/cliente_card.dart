import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../models/cliente_model.dart';
import '../theme/app_theme.dart';
import 'tarjeta_3d.dart';

/// Tarjeta premium de cliente: contenido dinámico según su tipo de
/// documento (DNI, RUC persona natural con/sin negocio, RUC persona
/// jurídica) y "Auditoría Visual" del Estándar Briam en el badge lateral
/// (azul = RENIEC/SUNAT, ámbar = manual, rojo = sin documento).
class ClienteCard extends StatelessWidget {
  const ClienteCard({super.key, required this.cliente, required this.onTap});

  final Cliente cliente;
  final VoidCallback onTap;

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

  String get _etiquetaCalidad {
    switch (cliente.calidadDato) {
      case CalidadDato.reniec:
        return 'RENIEC';
      case CalidadDato.manual:
        return 'Manual';
      case CalidadDato.sinDni:
        return 'Sin DNI';
    }
  }

  IconData get _iconoCalidad {
    switch (cliente.calidadDato) {
      case CalidadDato.reniec:
        return PhosphorIconsFill.sealCheck;
      case CalidadDato.manual:
        return PhosphorIconsRegular.notePencil;
      case CalidadDato.sinDni:
        return PhosphorIconsRegular.question;
    }
  }

  IconData get _iconoTipo {
    switch (cliente.tipoDocumento) {
      case TipoClienteDocumento.dni:
        return PhosphorIconsRegular.user;
      case TipoClienteDocumento.rucPersonaNatural:
        return PhosphorIconsRegular.storefront;
      case TipoClienteDocumento.rucPersonaJuridica:
        return PhosphorIconsRegular.buildings;
      case TipoClienteDocumento.sinDocumento:
        return PhosphorIconsRegular.user;
    }
  }

  String get _etiquetaDocumento {
    switch (cliente.tipoDocumento) {
      case TipoClienteDocumento.dni:
        return cliente.dni != null
            ? 'DNI ${cliente.dni}'
            : 'Sin DNI registrado';
      case TipoClienteDocumento.rucPersonaNatural:
      case TipoClienteDocumento.rucPersonaJuridica:
        return 'RUC ${cliente.dni}';
      case TipoClienteDocumento.sinDocumento:
        return 'Sin documento registrado';
    }
  }

  /// El nombre/descripción del negocio se destaca en negrita para
  /// cualquier cliente marcado como negocio (RUC con nombre comercial de
  /// SUNAT, o un DNI/sin documento al que el vendedor le anotó un rubro).
  String? get _nombreComercialDestacado =>
      cliente.esNegocio ? cliente.nombreComercial : null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _color;
    final direccion = cliente.direccion;
    final nombreComercial = _nombreComercialDestacado;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Tarjeta3D(
        onTap: onTap,
        borderRadius: 22,
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            splashColor: color.withValues(alpha: 0.08),
            highlightColor: color.withValues(alpha: 0.04),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
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
                    child: PhosphorIcon(_iconoTipo, color: color, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cliente.nombreParaMostrar,
                          style: theme.textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 3),
                        Text(
                          direccion != null && direccion.trim().isNotEmpty
                              ? '$_etiquetaDocumento · $direccion'
                              : _etiquetaDocumento,
                          style: theme.textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Chip(
                    avatar: PhosphorIcon(_iconoCalidad, size: 15, color: color),
                    label: Text(_etiquetaCalidad),
                    labelStyle: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                    backgroundColor: color.withValues(alpha: 0.1),
                    side: BorderSide.none,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
