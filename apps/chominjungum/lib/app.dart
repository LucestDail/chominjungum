import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'domain/app_role.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

class ChominjungumApp extends StatefulWidget {
  const ChominjungumApp({super.key, required this.role});

  final AppRole role;

  @override
  State<ChominjungumApp> createState() => _ChominjungumAppState();
}

class _ChominjungumAppState extends State<ChominjungumApp> {
  late final GoRouter _router = createRouter(widget.role);

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '초민정음',
      theme: AppTheme.light(),
      routerConfig: _router,
    );
  }
}
