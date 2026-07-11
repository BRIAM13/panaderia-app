import 'package:flutter/material.dart';

/// Paleta neutra usada SOLO en el layout de escritorio (Web/Windows) — la
/// paleta cálida crema/ámbar del resto de la app se diseñó pensando en
/// celular, y en pantallas grandes se sentía "de app móvil agrandada" en
/// vez de una herramienta de trabajo. Acá se usa un tono neutro, tipo
/// panel de trabajo (Linear/Stripe), con el color de marca solo como
/// acento puntual — la vista móvil no se toca, sigue con su paleta cálida.
class DesktopColors {
  DesktopColors._();

  static const fondo = Color(0xFFF6F6F8);
  static const superficie = Color(0xFFFFFFFF);
  static const borde = Color(0xFFE6E6EB);
  static const textoPrimario = Color(0xFF17171C);
  static const textoSecundario = Color(0xFF6E6E79);
  static const hover = Color(0xFFF0F0F3);
}
