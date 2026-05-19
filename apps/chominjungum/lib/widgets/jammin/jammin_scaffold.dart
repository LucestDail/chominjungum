import 'package:flutter/material.dart';

import '../../theme/jammin_tokens.dart';
import 'jammin_page_shell.dart';

/// jammin `#mainNav.jammin-nav` + `section.page-section` 레이아웃.
class JamminScaffold extends StatelessWidget {
  const JamminScaffold({
    super.key,
    this.title,
    this.titleWidget,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.denseTop = true,
    this.extendBody = false,
  }) : assert(title != null || titleWidget != null);

  final String? title;
  final Widget? titleWidget;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool denseTop;
  final bool extendBody;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: titleWidget ?? Text(title!),
        actions: actions,
      ),
      extendBody: extendBody,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
      body: SafeArea(
        child: JamminPageShell(
          child: Padding(
            padding: EdgeInsets.only(
              top: denseTop ? 24 : JamminTokens.sectionPaddingTop,
              bottom: bottomNavigationBar != null ? 0 : JamminTokens.sectionPaddingBottom,
            ),
            child: body,
          ),
        ),
      ),
    );
  }
}
