import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'domain/app_role.dart';
import 'providers/app_role_provider.dart';
import 'providers/dictation_providers.dart';
import 'services/local_store.dart';

Future<void> bootstrap(AppRole role) async {
  WidgetsFlutterBinding.ensureInitialized();
  // 문제·답안 이력을 담는 Box — 앱을 다시 켜도 남아야 한다
  await LocalStore.initForApp();
  await LocalStore.open();

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
