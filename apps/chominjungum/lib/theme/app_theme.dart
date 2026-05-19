import 'package:flutter/material.dart';

/// jammin 톤을 반영한 M3 라이트 테마 ([PLAN.md](PLAN.md) 토큰).
class AppTheme {
  AppTheme._();

  static ThemeData light() {
    const primary = Color(0xFF6D5E00);
    const onPrimary = Color(0xFFFFFFFF);
    const primaryContainer = Color(0xFFFBE365);
    const secondary = Color(0xFF006D3D);
    const secondaryContainer = Color(0xFF93F7B9);
    const tertiary = Color(0xFF9C4234);
    const surface = Color(0xFFFFFBFF);

    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: primaryContainer,
      secondary: secondary,
      secondaryContainer: secondaryContainer,
      tertiary: tertiary,
      surface: surface,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      appBarTheme: const AppBarTheme(centerTitle: true, scrolledUnderElevation: 0),
      navigationBarTheme: NavigationBarThemeData(
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
      ),
      cardTheme: const CardThemeData(
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
    );
  }
}
