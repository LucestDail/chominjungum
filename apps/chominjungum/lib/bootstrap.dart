import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'domain/app_role.dart';
import 'providers/app_role_provider.dart';
import 'providers/dictation_providers.dart';

Future<void> bootstrap(AppRole role) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  // jammin 서버 응답 스냅샷 — 빌드 시 번들, 실행 즉시 표시
  final bundled = await BundledDictationLoader.load();

  runApp(
    ProviderScope(
      overrides: [
        appRoleProvider.overrideWithValue(role),
        dictationPackageProvider.overrideWith((ref) => bundled),
      ],
      child: ChominjungumApp(role: role),
    ),
  );
}
