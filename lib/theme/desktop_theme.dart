import 'app_theme.dart';

/// Colores del layout de escritorio (Web/Windows) — reusa la paleta de
/// marca (crema/ámbar/terracota) de siempre, ver [AppColors]. Lo que
/// cambia en escritorio es la ESTRUCTURA (sidebar plano, tarjetas sin
/// degradado ni animación 3D pensada para touch), no la paleta — la marca
/// debe reconocerse igual en cualquier tamaño de pantalla.
class DesktopColors {
  DesktopColors._();

  static const fondo = AppColors.background;
  static const superficie = AppColors.surface;
  static const borde = AppColors.surfaceMuted;
  static const textoPrimario = AppColors.textPrimary;
  static const textoSecundario = AppColors.textSecondary;
  static const hover = AppColors.surfaceMuted;
}
