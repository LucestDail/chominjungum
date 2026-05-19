import 'package:flutter/material.dart';

import '../../theme/jammin_tokens.dart';

/// jammin `.jammin-page-shell` — 최대 너비 1140, 좌우 패딩.
class JamminPageShell extends StatelessWidget {
  const JamminPageShell({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: JamminTokens.pagePaddingH),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: JamminTokens.pageMaxWidth),
        child: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}
