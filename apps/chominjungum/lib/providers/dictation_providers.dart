import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hangul_core/hangul_core.dart';

import '../domain/dictation_models.dart';
import '../services/bundled_dictation_loader.dart';
import '../services/device_binding_id.dart';
import '../services/dictation_repository.dart';
import '../services/jammin_add_word_service.dart';
import '../services/local_hub_service.dart';

export '../services/bundled_dictation_loader.dart' show BundledDictationLoader;

/// 기본 연습 문장.
const kDefaultPracticeWords = ['안녕하세요', '강아지와고양이'];

/// 교사 허브 수신 또는 앱 시작 시 로드한 받아쓰기 묶음.
final dictationPackageProvider = StateProvider<DictationPackage?>((ref) => null);

/// 학생 기기가 연결 중인 교사 허브 클라이언트 (미연결이면 null).
final studentHubClientProvider = StateProvider<StudentHubClient?>((ref) => null);

/// 문제·답안의 로컬 이력.
final dictationRepositoryProvider = Provider<DictationRepository>((ref) {
  return const DictationRepository();
});

/// 기기 단위 안정 ID (제출 시 학생 식별자).
final deviceBindingIdProvider = FutureProvider<String>((ref) {
  return DeviceBindingId.getOrCreate();
});

/// 앱에 번들된 기본 묶음 (서버 응답 스냅샷).
final bundledDefaultPackageProvider = FutureProvider<DictationPackage>((ref) {
  return BundledDictationLoader.load();
});

final _jamminAddWordServiceProvider = Provider<JamminAddWordService>((ref) {
  final service = JamminAddWordService();
  ref.onDispose(service.close);
  return service;
});

/// 네트워크로 jammin 갱신 (선택).
final jamminNetworkPackageProvider = FutureProvider<DictationPackage>((ref) async {
  final service = ref.watch(_jamminAddWordServiceProvider);
  final items = <DictationItem>[];
  for (final word in kDefaultPracticeWords) {
    final glyphs = await service.addWord(word);
    items.add(DictationItem.fromGlyphs(word, glyphs));
  }
  return DictationPackage(version: DictationPackage.currentVersion, items: items);
});

/// 표시용: 허브/부트스트랩 캐시 > 번들 Future.
final practicePackageProvider = Provider<AsyncValue<DictationPackage>>((ref) {
  final cached = ref.watch(dictationPackageProvider);
  if (cached != null && cached.items.isNotEmpty) {
    return AsyncValue.data(cached);
  }
  final bundled = ref.watch(bundledDefaultPackageProvider);
  return bundled.when(
    data: (pkg) {
      // 번들 로드 직후 캐시에 넣어 재진입 시 로딩 없음.
      Future.microtask(() {
        if (ref.read(dictationPackageProvider) == null) {
          ref.read(dictationPackageProvider.notifier).state = pkg;
        }
      });
      return AsyncValue.data(pkg);
    },
    loading: () => const AsyncValue.loading(),
    error: (e, st) => AsyncValue.error(e, st),
  );
});

List<HangulGlyph> dictationItemGlyphs(DictationItem item) =>
    HangulUtil.glyphsFromAddWordResponse(item.expectedGlyphsJson);

/// 오답 노트 → 출제 화면으로 넘기는 **가리기 규칙**.
///
/// 오답 노트가 "보기만 하는 화면"이면 값이 절반이다. 약한 자모를 찾았으면
/// 그걸로 바로 다음 학습지를 낼 수 있어야 한다(웹 교사 콘솔의 `handoff` 와 같은 발상).
final pendingHideRuleProvider = StateProvider<HideRule?>((ref) => null);
