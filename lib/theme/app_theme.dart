import 'package:flutter/material.dart';

/// Paleta gourmet de la Super App: ámbar/terracota como color de marca,
/// crema/vainilla cálido de fondo y carbón/chocolate para texto y superficies.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFFB5451B); // Ámbar profundo / terracota
  static const Color primaryContainer = Color(0xFFF3D3BE);
  static const Color secondary = Color(0xFFC08A3E); // Bronce / miel
  static const Color secondaryContainer = Color(0xFFF1DDB6);
  static const Color background = Color(0xFFFDF6EC); // Crema / vainilla cálido
  static const Color surface = Color(0xFFFFFBF3);
  static const Color surfaceMuted = Color(0xFFF3E9D8);
  static const Color textPrimary = Color(
    0xFF2B2118,
  ); // Carbón / chocolate profundo
  static const Color textSecondary = Color(0xFF6B5B4C);
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
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    ),
  );
}
