import 'package:flutter/material.dart';

import '../../theme/jammin_tokens.dart';
import '../../theme/jammin_typography.dart';

/// 연결 상태·안내 문구.
class JamminStatusBanner extends StatelessWidget {
  const JamminStatusBanner({super.key, required this.message, this.tone = JamminStatusTone.info});

  final String message;
  final JamminStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (tone) {
      JamminStatusTone.info => (
          JamminTokens.brandSoft,
          JamminTokens.brandDark,
          JamminTokens.brandMid,
        ),
      JamminStatusTone.success => (
          const Color(0xFFD1FAE5),
          JamminTokens.success,
          JamminTokens.brandMid,
        ),
      JamminStatusTone.error => (
          const Color(0xFFFEE2E2),
          JamminTokens.danger,
          JamminTokens.danger,
        ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(JamminTokens.radiusMd),
        border: Border.all(color: border.withValues(alpha: 0.35)),
      ),
      child: Text(
        message,
        style: TextStyle(
          fontFamily: JamminTypography.family,
          fontSize: 15,
          height: 1.45,
          color: fg,
        ),
      ),
    );
  }
}

enum JamminStatusTone { info, success, error }
