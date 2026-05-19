import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/app_role.dart';

final appRoleProvider = Provider<AppRole>(
  (ref) => throw UnimplementedError('bootstrap에서 override 필요'),
);
