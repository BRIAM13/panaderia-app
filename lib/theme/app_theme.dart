import 'package:flutter/material.dart';

/// Paleta gourmet de la Super App: ámbar/terracota como color de marca,
/// crema/vainilla cálido de fondo y carbón/chocolate para texto y superficies.
class AppColors {
  AppColors._();

  // La familia cálida es la misma de siempre (terracota / ámbar / bronce),
  // pero con bastante más saturación: los tonos anteriores rondaban 50-74 %
  // de saturación y sobre un fondo crema casi blanco la pantalla entera se
  // leía apagada. Acá se conserva el MATIZ (16° el terracota, 35° el bronce)
  // y se sube la saturación, que es lo que da la sensación de "más vivo"
  // sin cambiar de paleta.
  static const Color primary = Color(
    0xFFCC4318,
  ); // Terracota vivo (hsl 16/79/45)
  /// Variante oscura del primario, para TEXTO pequeño sobre fondos claros:
  /// el primario saturado contra crema queda en ~3.8:1 y no llega a AA.
  static const Color primaryDeep = Color(0xFF98300E);
  static const Color primaryContainer = Color(0xFFFAC9A9);
  /// Bronce / miel. Sube de 51 % a 81 % de saturación respecto del original
  /// (0xFFC08A3E) manteniendo el matiz en 35°, pero baja de luminancia en
  /// vez de subirla: un bronce claro y saturado se lee "mostaza", y además
  /// es el extremo del degradado de la tarjeta "Cobrado hoy", donde va texto
  /// BLANCO encima — a 0xFFC17C1A ese texto quedaba en 3.4:1 y no pasaba AA.
  static const Color secondary = Color(0xFFB06E12);
  /// Bronce oscurecido para texto sobre contenedores claros de bronce.
  static const Color secondaryDeep = Color(0xFF6E4A0F);
  /// Miel de los banners informativos. Se usa en una docena larga de
  /// pantallas, así que sube poco: apenas un punto más viva que la original
  /// (0xFFF1DDB6). La versión que llegó a 0xFFFADB9E duplicaba la caída del
  /// azul (−61 contra −39) y con eso volvía mostaza media app.
  static const Color secondaryContainer = Color(0xFFF5DDB4);

  // ---------------------------------------------------------------------
  // NEUTROS. Regla de la casa: la saturación se sube en los ACENTOS, nunca
  // acá. El fondo crema tiene una caída pareja entre canales consecutivos
  // (253,246,236 → −7 de R a G, −10 de G a B); si un neutro nuevo hace caer
  // el azul mucho más de lo que cae el verde, el ojo lo lee como AMARILLO,
  // y como estos tokens pintan el fondo de la app entera el tinte aparece
  // en todas las pantallas a la vez. Todo neutro nuevo se compara contra
  // [background] antes de fijarse.
  // ---------------------------------------------------------------------

  /// Miel PÁLIDA. [secondaryContainer] a todo lo ancho de la pastilla de
  /// fecha le competía al botón principal; esta versión conserva el color
  /// sin robarle la jerarquía al CTA.
  static const Color secondarySoft = Color(0xFFF9EBD3);
  static const Color background = Color(0xFFFDF6EC); // Crema / vainilla cálido
  static const Color surface = Color(0xFFFFFBF3);
  static const Color surfaceMuted = Color(0xFFF3E9D8);

  /// Superficie de la navegación (barra inferior en celular, riel en tablet).
  /// Es un escalón más "arena" que [surface] para que la barra se lea como
  /// una pieza aparte del contenido, pero mantiene exactamente la misma
  /// caída de canales que [surfaceMuted] (−10 y −17): quien pone el color
  /// en esta barra es la pastilla terracota, no el fondo.
  static const Color navSurface = Color(0xFFF5EBDA);

  /// Borde cálido visible. [surfaceMuted] servía de borde, pero contra el
  /// fondo crema desaparecía; este tono es el que dibuja los contornos.
  static const Color borderSoft = Color(0xFFE6DAC6);

  static const Color textPrimary = Color(
    0xFF2B2118,
  ); // Carbón / chocolate profundo
  /// Texto secundario (etiquetas, subtítulos) — más oscuro y saturado que
  /// el original (0xFF6B5B4C, casi gris) para que se note más sin salirse
  /// de la familia chocolate/bronce de [textPrimary].
  static const Color textSecondary = Color(0xFF5A4632);

  /// Marrón bronce para los ítems INACTIVOS de la navegación. Con
  /// [textSecondary] (casi gris) la barra volvía a verse descolorida en
  /// tres de sus cuatro casillas; este tono la mantiene dentro de la paleta
  /// y aun así queda en 5.8:1 sobre [navSurface].
  static const Color navInactive = Color(0xFF7A5236);

  static const Color error = Color(0xFFB3261E);
}

/// Construye el ThemeData Material 3 de la aplicación.
ThemeData buildAppTheme() {
  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
      ).copyWith(
        primary: AppColors.primary,
        onPrimary: Colors.white,
        primaryContainer: AppColors.primaryContainer,
        onPrimaryContainer: AppColors.textPrimary,
        secondary: AppColors.secondary,
        onSecondary: Colors.white,
        secondaryContainer: AppColors.secondaryContainer,
        onSecondaryContainer: AppColors.textPrimary,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        outline: AppColors.borderSoft,
        outlineVariant: AppColors.surfaceMuted,
        error: AppColors.error,
        onError: Colors.white,
      );

  final baseTextTheme = ThemeData(brightness: Brightness.light).textTheme;
  final textTheme = baseTextTheme
      .apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      )
      .copyWith(
        titleLarge: baseTextTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        titleMedium: baseTextTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(
          color: AppColors.textSecondary,
        ),
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.background,
    // Fuente empaquetada (ver pubspec.yaml) en vez del Roboto por defecto:
    // en Flutter Web, sin una fuente propia, CanvasKit la descarga de la
    // red recién al pintar el primer texto — si esa descarga no terminó
    // (típico justo después de una transición de pantalla), los glifos
    // salen recortados y no siempre se autocorrigen.
    fontFamily: 'Inter',
    textTheme: textTheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      centerTitle: true,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surfaceMuted,
      labelStyle: const TextStyle(
        color: AppColors.textSecondary,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
      side: const BorderSide(color: AppColors.borderSoft, width: 1),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    ),
    // La barra inferior no tenía NINGÚN theming: se quedaba con los valores
    // por defecto de Material 3, que derivan del ColorScheme y salen casi
    // blancos, con un indicador beige apenas visible. Acá se le da color
    // propio: superficie arena, pastilla de selección en terracota LLENA
    // (blanco encima, 4.8:1) y etiqueta en el terracota oscuro (6.4:1).
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.navSurface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.primary,
      indicatorShape: const StadiumBorder(),
      elevation: 0,
      height: 68,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith((estados) {
        final activo = estados.contains(WidgetState.selected);
        return IconThemeData(
          size: 24,
          color: activo ? Colors.white : AppColors.navInactive,
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((estados) {
        final activo = estados.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 11.5,
          height: 1.2,
          fontWeight: activo ? FontWeight.w800 : FontWeight.w600,
          color: activo ? AppColors.primaryDeep : AppColors.navInactive,
        );
      }),
    ),
    // El riel de tablet usa la misma gramática que la barra de celular para
    // que cambiar de tamaño de pantalla no cambie el lenguaje visual.
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: AppColors.navSurface,
      indicatorColor: AppColors.primary,
      indicatorShape: const StadiumBorder(),
      useIndicator: true,
      selectedIconTheme: const IconThemeData(color: Colors.white, size: 24),
      unselectedIconTheme: const IconThemeData(
        color: AppColors.navInactive,
        size: 24,
      ),
      selectedLabelTextStyle: const TextStyle(
        color: AppColors.primaryDeep,
        fontWeight: FontWeight.w800,
        fontSize: 12,
      ),
      unselectedLabelTextStyle: const TextStyle(
        color: AppColors.navInactive,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
    ),
  );
}
