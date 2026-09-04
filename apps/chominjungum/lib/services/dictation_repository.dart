import '../domain/dictation_models.dart';
import 'local_store.dart';

/// 받아쓰기 문제·답안의 로컬 이력.
///
/// 앱을 다시 켜도 **교사가 낸 문제와 내가 쓴 답이 남아 있어야** 한다.
/// 그전에는 둘 다 메모리(riverpod state, 화면 `setState`)에만 있어 재시작하면 사라졌다.
///
/// 채점과 제출을 분리해 다룬다 — 허브에 연결되지 않아도 채점 이력은 남고,
/// 제출이 성공하면 그 시각만 덧붙인다([DictationAttempt.submittedAtMs]).
/// 교실에서 Wi-Fi 가 끊기거나 교사 기기가 먼저 닫혀도 학생 기록을 잃지 않는다.
class DictationRepository {
  const DictationRepository();

  // ── 문제 ────────────────────────────────────────────────

  /// 수신한 묶음을 저장한다. 같은 문제(id)는 덮어쓴다.
  Future<void> savePackage(DictationPackage package) async {
    for (final item in package.items) {
      await LocalStore.put(LocalStore.itemsBox, item.id, item.toJson());
    }
  }

  List<DictationItem> loadItems() {
    return LocalStore.values(LocalStore.itemsBox)
        .map(_tryItem)
        .whereType<DictationItem>()
        .toList(growable: false);
  }

  /// 저장된 문제가 없으면 null — 호출하는 쪽이 번들 기본값으로 넘어갈 수 있게.
  DictationPackage? loadPackage() {
    final items = loadItems();
    if (items.isEmpty) return null;
    return DictationPackage(version: DictationPackage.currentVersion, items: items);
  }

  // ── 답안 ────────────────────────────────────────────────

  Future<void> saveAttempt(DictationAttempt attempt) {
    return LocalStore.put(LocalStore.attemptsBox, attempt.id, attempt.toJson());
  }

  /// 제출이 성공했을 때 그 시각을 남긴다. 없는 답안이면 아무 일도 하지 않는다.
  Future<void> markSubmitted(String attemptId, int submittedAtMs) async {
    final found = attempt(attemptId);
    if (found == null) return;
    await saveAttempt(found.copyWith(submittedAtMs: submittedAtMs));
  }

  DictationAttempt? attempt(String attemptId) {
    final raw = LocalStore.get(LocalStore.attemptsBox, attemptId);
    return raw == null ? null : _tryAttempt(raw);
  }

  /// 최신순. [deviceBindingId] 를 주면 그 기기 것만 — 교사 기기에는 여러 학생
  /// 제출이 한 Box 에 섞여 들어오므로 읽을 때 걸러낸다.
  List<DictationAttempt> attempts({String? deviceBindingId, String? itemId}) {
    final list = LocalStore.values(LocalStore.attemptsBox)
        .map(_tryAttempt)
        .whereType<DictationAttempt>()
        .where((a) => deviceBindingId == null || a.deviceBindingId == deviceBindingId)
        .where((a) => itemId == null || a.itemId == itemId)
        .toList();
    list.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    return list;
  }

  /// 아직 교사 허브에 못 보낸 답안 (오래된 것부터 — 보낼 순서).
  List<DictationAttempt> pendingSubmissions({String? deviceBindingId}) {
    final list = attempts(deviceBindingId: deviceBindingId)
        .where((a) => !a.isSubmitted)
        .toList();
    return list.reversed.toList(growable: false);
  }

  // 깨진 기록 하나가 목록 전체를 못 읽게 만들지 않는다.
  static DictationItem? _tryItem(Map<String, Object?> json) {
    try {
      return DictationItem.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  static DictationAttempt? _tryAttempt(Map<String, Object?> json) {
    try {
      return DictationAttempt.fromJson(json);
    } catch (_) {
      return null;
    }
  }
}
