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

  /// Escritorio "cómodo". [escritorio] alcanza para partir la pantalla en
  /// dos, pero NO para densidades altas dentro del Hub: ahí el panel lateral
  /// fijo se come 300 px, así que a 900 px de ventana el contenido real es
  /// de ~580 px — meter 4 KPIs o una tabla de 5 columnas ahí queda apretado.
  /// A partir de este ancho quedan ~800 px útiles y esas densidades sí
  /// entran bien.
  static const double escritorioComodo = 1100;

  /// Monitor grande / laptop moderna a pantalla completa: hay espacio para
  /// tres columnas de contenido a la vez (ej. gráfico + dos listas), o para
  /// una tabla con todas sus columnas visibles sin recortar nada.
  static const double escritorioAncho = 1400;
}
