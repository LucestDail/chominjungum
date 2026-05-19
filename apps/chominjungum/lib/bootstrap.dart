import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'domain/app_role.dart';

Future<void> bootstrap(AppRole role) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  runApp(
    ProviderScope(
      child: ChominjungumApp(role: role),
    ),
  );
}
