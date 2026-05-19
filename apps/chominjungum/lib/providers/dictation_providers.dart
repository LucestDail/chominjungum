import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/dictation_models.dart';

/// 교사 허브에서 수신한 현재 받아쓰기 묶음 (없으면 로컬 샘플 사용).
final dictationPackageProvider = StateProvider<DictationPackage?>((ref) => null);
