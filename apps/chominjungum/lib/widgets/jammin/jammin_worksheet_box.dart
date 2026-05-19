import 'package:flutter/material.dart';

import '../../theme/jammin_tokens.dart';

/// jammin `#box2` — 워크시트 영역 (검은 테두리).
class JamminWorksheetBox extends StatelessWidget {
  const JamminWorksheetBox({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: JamminTokens.surfaceElevated,
        border: Border.all(color: Colors.black, width: 1),
      ),
      child: child,
    );
  }
}

/// jammin `.box1` — 옵션 바.
class JamminOptionBar extends StatelessWidget {
  const JamminOptionBar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      ),
    );
  }
}
