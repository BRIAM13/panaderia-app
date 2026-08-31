import 'package:flutter/material.dart';

import '../models/perfil_cliente_model.dart';

/// Cómo se ve un segmento del CRM en pantalla: su nombre en español, su
/// color y su ícono. Vive acá (y no dentro de una pantalla) porque el mismo
/// segmento tiene que verse idéntico en el perfil de un cliente y en el
/// panel de Analítica — si cada pantalla eligiera sus propios colores, el
/// mismo cliente sería "dorado" en una y "naranja" en otra.
class EtiquetaSegmento {
  const EtiquetaSegmento(this.texto, this.color, this.icono);

  final String texto;
  final Color color;
  final IconData icono;
}

EtiquetaSegmento etiquetaSegmento(SegmentoCliente segmento) {
  switch (segmento) {
    case SegmentoCliente.nuevo:
      return const EtiquetaSegmento(
        'Nuevo',
        Color(0xFF2563EB),
        Icons.fiber_new_rounded,
      );
    case SegmentoCliente.enRiesgo:
      return const EtiquetaSegmento(
        'En riesgo',
        Color(0xFFDC2626),
        Icons.warning_amber_rounded,
      );
    case SegmentoCliente.vip:
      return const EtiquetaSegmento(
        'VIP',
        Color(0xFFC08A3E),
        Icons.workspace_premium_rounded,
      );
    case SegmentoCliente.frecuente:
      return const EtiquetaSegmento(
        'Frecuente',
        Color(0xFF2E7D32),
        Icons.repeat_rounded,
      );
    case SegmentoCliente.regular:
      return const EtiquetaSegmento(
        'Regular',
        Color(0xFF6B5B4C),
        Icons.person_rounded,
      );
  }
}

/// Orden fijo en que se muestran los segmentos en el panel de Analítica —
/// el mismo que usa el backend para armar el resumen, de "recién llegado" a
/// "cliente de siempre", con el que hay que rescatar (en riesgo) resaltado
/// al principio.
const List<SegmentoCliente> ordenSegmentos = [
  SegmentoCliente.nuevo,
  SegmentoCliente.enRiesgo,
  SegmentoCliente.vip,
  SegmentoCliente.frecuente,
  SegmentoCliente.regular,
];

/// Clave con la que viaja cada segmento en el JSON del backend (ver
/// `SEGMENTOS` en clientesController.js).
String claveSegmento(SegmentoCliente segmento) {
  switch (segmento) {
    case SegmentoCliente.nuevo:
      return 'NUEVO';
    case SegmentoCliente.enRiesgo:
      return 'EN_RIESGO';
    case SegmentoCliente.vip:
      return 'VIP';
    case SegmentoCliente.frecuente:
      return 'FRECUENTE';
    case SegmentoCliente.regular:
      return 'REGULAR';
  }
}
