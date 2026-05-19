import 'package:flutter/material.dart';

import 'jammin_tokens.dart';

/// jammin `styles.css` — KCC 도담도담체 + section-heading 크기.
abstract final class JamminTypography {
  static const family = 'KCCDodamdodamR';

  static TextTheme textTheme(TextTheme base) {
    TextStyle d([FontWeight? w, double? size, double? height, Color? color]) =>
        TextStyle(
          fontFamily: family,
          fontWeight: w ?? FontWeight.w400,
          fontSize: size,
          height: height,
          color: color ?? JamminTokens.text,
          letterSpacing: 0,
        );

    return base.copyWith(
      displayLarge: d(FontWeight.w700, 40, 1.2),
      displayMedium: d(FontWeight.w700, 32, 1.25),
      displaySmall: d(FontWeight.w700, 28, 1.3),
      headlineLarge: d(FontWeight.w700, 40, 1.2),
      headlineMedium: d(FontWeight.w700, 32, 1.25),
      headlineSmall: d(FontWeight.w700, 24, 1.3),
      titleLarge: d(FontWeight.w700, 22, 1.35),
      titleMedium: d(FontWeight.w700, 18, 1.4),
      titleSmall: d(FontWeight.w700, 16, 1.4),
      bodyLarge: d(null, 18, 1.55, JamminTokens.text),
      bodyMedium: d(null, 16, 1.55, JamminTokens.text),
      bodySmall: d(null, 14, 1.5, JamminTokens.textMuted),
      labelLarge: d(FontWeight.w700, 16, 1.2),
      labelMedium: d(FontWeight.w700, 14, 1.2),
      labelSmall: d(FontWeight.w700, 12, 1.2, JamminTokens.textMuted),
    );
  }

  /// `.section-heading` — 2.5rem uppercase
  static TextStyle sectionHeading(BuildContext context) =>
      Theme.of(context).textTheme.headlineMedium!.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.06,
            color: JamminTokens.text,
          );

  /// `.section-subheading.text-muted`
  static TextStyle sectionSubheading(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium!.copyWith(
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w400,
            color: JamminTokens.textMuted,
          );
}
