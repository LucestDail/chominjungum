import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _kStudentName = 'student_name_v1';

/// 학생이 스스로 적는 표시 이름 — **선택**이다.
///
/// ## 왜 필요한가
///
/// 교사 화면은 제출을 `학생 a3f2…`(기기 ID 8자)로 보여준다. 한두 대면 몰라도
/// 교실에서는 **누구 것인지 알 수 없다.** 서버를 쓰면 나중에 기기를 명단에 배정해
/// 소급 반영되지만(`POST /classrooms/{id}/devices`), **수업 중에는 교사가 바로 알아야
/// 피드백을 줄 수 있다.**
///
/// ## 개인정보
///
/// - **비워 둘 수 있다.** 비우면 지금까지처럼 기기 ID 축약으로 보인다
/// - 기기에만 저장하고(secure storage), **교사 기기로만** 전송한다
/// - **서버 업싱크에는 포함되지 않는다** — 업싱크 규약(`SyncDtos.SyncAttempt`)에
///   이름 필드가 없고, 서버는 기기↔학생 매핑으로 이름을 붙인다
class StudentProfile {
  StudentProfile._();

  static const _storage = FlutterSecureStorage();

  /// 표시 이름 상한 — 교사 화면 목록에서 한 줄을 넘지 않을 정도.
  static const maxLength = 20;

  /// ⚠️**실패하면 조용히 null 을 준다.** 이름은 선택 기능인데 저장소 오류로
  /// **제출이 막히면 안 된다** — 실제로 그렇게 만들었다가 e2e 테스트가 잡았다
  /// (플러그인이 없는 환경에서 `_submit` 이 통째로 실패했다).
  static Future<String?> load() async {
    try {
      final v = await _storage.read(key: _kStudentName);
      final t = v?.trim();
      return (t == null || t.isEmpty) ? null : t;
    } catch (_) {
      return null;
    }
  }

  /// 비우거나 공백만 주면 삭제한다(= 기기 ID 표시로 되돌아간다).
  /// 저장 실패도 삼킨다 — 타이핑 중에 예외가 튀면 안 된다.
  static Future<void> save(String? name) async {
    try {
      final t = name?.trim();
      if (t == null || t.isEmpty) {
        await _storage.delete(key: _kStudentName);
        return;
      }
      await _storage.write(
        key: _kStudentName,
        value: t.length > maxLength ? t.substring(0, maxLength) : t,
      );
    } catch (_) {
      // 이름은 선택 기능이다. 저장 못 해도 수업은 계속돼야 한다.
    }
  }
}
