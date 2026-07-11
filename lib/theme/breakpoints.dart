/// Puntos de quiebre compartidos para adaptar pantallas diseñadas
/// mobile-first a ventanas anchas (Web/Windows/tablet) — un solo lugar
/// para no repetir el mismo número mágico en cada pantalla.
class Breakpoints {
  Breakpoints._();

  /// A partir de acá hay espacio de sobra para layouts de 2+ columnas,
  /// paneles laterales fijos, etc.
  static const double escritorio = 900;

  /// Ancho de tablet en horizontal / ventana mediana — suficiente para
  /// grillas de 2 columnas sin sentirse apretado, aunque todavía no para
  /// paneles laterales fijos.
  static const double tablet = 600;
}
