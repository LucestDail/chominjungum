import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

/// 로컬 영속 저장소 — Hive Box 이름과 열기·닫기를 한곳에 모은다.
///
/// ## 왜 JSON 문자열로 저장하나
///
/// `TypeAdapter` 를 쓰면 `hive_generator` + `build_runner` 가 붙고 모델을 바꿀 때마다
/// 코드 생성을 돌려야 한다. 도메인 모델에는 이미 `toJson`/`fromJson` 이 있고
/// 동기화 프로토콜도 JSON 이라, **같은 표현을 그대로 저장**하는 편이 단순하고
/// 스키마 변화에도 견딘다(`Box<String>` 이라 타입 캐스팅 문제도 없다).
///
/// ## 키 규약
///
/// | Box | 키 | 값 |
/// |---|---|---|
/// | [itemsBox] | `DictationItem.id` | `DictationItem.toJson()` |
/// | [attemptsBox] | `DictationAttempt.id` | `DictationAttempt.toJson()` |
/// | [sessionsBox] | 허브 세션 id | 교사 출제·제출 스냅샷 |
///
/// 기기 구분은 **값 안의 `deviceBindingId`** 로 한다(Box 를 기기마다 나누지 않는다).
/// 학생 기기는 자기 것만 쌓이고, 교사 기기는 여러 학생 제출이 한 Box 에 섞여 들어오므로
/// 읽을 때 그 필드로 걸러낸다. 기기 ID 자체는 [DeviceBindingId] 가 SecureStorage 에 둔다.
///
/// Box 이름에 `.v1` 을 붙인 이유: 저장 형식을 바꿔야 할 때 새 Box 로 옮기고
/// 옛 Box 를 남겨 둘 수 있다(마이그레이션 중 데이터를 잃지 않는다).
class LocalStore {
  LocalStore._();

  static const itemsBox = 'cjm.items.v1';
  static const attemptsBox = 'cjm.attempts.v1';
  static const sessionsBox = 'cjm.sessions.v1';

  static const _all = [itemsBox, attemptsBox, sessionsBox];

  /// 앱에서 쓰는 초기화 — 플랫폼 경로를 Hive 가 잡는다.
  static Future<void> initForApp() => Hive.initFlutter();

  /// 정해진 경로로 초기화 (테스트·도구용).
  ///
  /// Hive 접근을 이 클래스 안으로 모아 두면, 호출하는 쪽이 `hive` 패키지를
  /// 직접 의존하지 않아도 된다(`hive` 는 `hive_flutter` 의 전이 의존이다).
  static void initAt(String path) => Hive.init(path);

  /// 열린 Box 를 모두 닫는다.
  static Future<void> closeAll() => Hive.close();

  /// 디스크의 Box 파일까지 지운다 (테스트 정리용).
  static Future<void> deleteAllFromDisk() => Hive.deleteFromDisk();

  /// Box 를 모두 연다. 초기화([initForApp] 또는 [initAt])가 먼저 필요하다.
  static Future<void> open() async {
    for (final name in _all) {
      if (!Hive.isBoxOpen(name)) {
        await Hive.openBox<String>(name);
      }
    }
  }

  static Box<String> box(String name) => Hive.box<String>(name);

  /// 저장된 JSON 을 그대로 담는다.
  static Future<void> put(String boxName, String key, Map<String, Object?> value) {
    return box(boxName).put(key, jsonEncode(value));
  }

  /// 없으면 null. 깨진 기록은 **던지지 않고 null** 로 취급한다 —
  /// 형식이 바뀐 옛 데이터 하나 때문에 화면 전체가 멈추면 안 된다.
  static Map<String, Object?>? get(String boxName, String key) {
    final raw = box(boxName).get(key);
    if (raw == null) return null;
    return _decode(raw);
  }

  /// Box 안의 모든 값. 깨진 기록은 건너뛴다.
  static List<Map<String, Object?>> values(String boxName) {
    return box(boxName)
        .values
        .map(_decode)
        .whereType<Map<String, Object?>>()
        .toList(growable: false);
  }

  static Future<void> delete(String boxName, String key) => box(boxName).delete(key);

  /// 테스트·기기 초기화용. 열려 있는 Box 의 내용만 비운다.
  static Future<void> clearAll() async {
    for (final name in _all) {
      if (Hive.isBoxOpen(name)) {
        await box(name).clear();
      }
    }
  }

  static Map<String, Object?>? _decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, Object?>.from(decoded);
      }
    } catch (_) {
      // 손상된 기록은 없는 것으로 본다
    }
    return null;
  }
}
