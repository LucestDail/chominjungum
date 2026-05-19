import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'jammin_tokens.dart';
import 'jammin_typography.dart';

/// jammin 웹(`jammin-tokens.css`, `jammin-ui.css`) 기반 M3 테마.
class AppTheme {
  AppTheme._();

  static ThemeData light() {
    const primary = JamminTokens.brand;
    const onPrimary = Colors.white;

    final colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: JamminTokens.brandSoft,
      onPrimaryContainer: JamminTokens.brandDark,
      secondary: JamminTokens.success,
      onSecondary: onPrimary,
      secondaryContainer: Color(0xFFD1FAE5),
      onSecondaryContainer: JamminTokens.brandDark,
      tertiary: JamminTokens.accent,
      onTertiary: onPrimary,
      error: JamminTokens.danger,
      onError: onPrimary,
      surface: JamminTokens.surfaceElevated,
      onSurface: JamminTokens.text,
      onSurfaceVariant: JamminTokens.textMuted,
      outline: JamminTokens.border,
      outlineVariant: JamminTokens.borderStrong,
      shadow: Colors.black26,
      scrim: Colors.black54,
      inverseSurface: JamminTokens.text,
      onInverseSurface: JamminTokens.surfaceElevated,
      inversePrimary: JamminTokens.brandLight,
      surfaceContainerHighest: JamminTokens.surface,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: JamminTokens.surface,
      fontFamily: JamminTypography.family,
    );

    return base.copyWith(
      textTheme: JamminTypography.textTheme(base.textTheme),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: JamminTokens.brand,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: JamminTypography.textTheme(base.textTheme).titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
        iconTheme: const IconThemeData(color: Colors.white),
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: JamminTokens.surfaceElevated,
        indicatorColor: JamminTokens.brandSoft,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: JamminTypography.family,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? JamminTokens.brand : JamminTokens.textMuted,
          );
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: JamminTokens.brand,
          foregroundColor: Colors.white,
          disabledBackgroundColor: JamminTokens.border,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          textStyle: const TextStyle(
            fontFamily: JamminTypography.family,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.04,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(JamminTokens.radiusSm),
          ),
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return JamminTokens.brandDark.withValues(alpha: 0.2);
            }
            if (states.contains(WidgetState.hovered)) {
              return JamminTokens.brandDark.withValues(alpha: 0.08);
            }
            return null;
          }),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: JamminTokens.brand,
          side: const BorderSide(color: JamminTokens.brand, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(
            fontFamily: JamminTypography.family,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(JamminTokens.radiusSm),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: JamminTokens.surfaceElevated,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(JamminTokens.radiusSm),
          borderSide: const BorderSide(color: JamminTokens.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(JamminTokens.radiusSm),
          borderSide: const BorderSide(color: JamminTokens.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(JamminTokens.radiusSm),
          borderSide: const BorderSide(color: JamminTokens.brandMid, width: 2),
        ),
        labelStyle: const TextStyle(
          fontFamily: JamminTypography.family,
          color: JamminTokens.textMuted,
        ),
        hintStyle: const TextStyle(
          fontFamily: JamminTypography.family,
          color: JamminTokens.textMuted,
        ),
      ),
      cardTheme: CardThemeData(
        color: JamminTokens.surfaceElevated,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(JamminTokens.radiusMd),
          side: const BorderSide(color: JamminTokens.border),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: const DividerThemeData(color: JamminTokens.border, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: JamminTokens.brandDark,
        contentTextStyle: const TextStyle(
          fontFamily: JamminTypography.family,
          color: Colors.white,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(JamminTokens.radiusMd),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
