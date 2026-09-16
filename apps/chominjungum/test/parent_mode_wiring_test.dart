import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// 🔴 **결정을 코드가 지키는지** 소스로 확인한다.
///
/// 2026-09-16 결정: *"집에서 부모 기기가 허브 — 오프라인 번들로 이미 되고 **서버가 필요 없다**"*.
///
/// `AppRole.canUpsync` 는 11개 테스트로 초록불이지만, **화면이 그걸 안 보면 소용없다.**
/// 실제로 이 작업 전까지 `teacher_home_screen.dart` 는 역할을 **전혀 보지 않았고**,
/// 부모 모드를 켰다면 **학교 서버 업싱크 화면이 그대로 보였을 것**이다.
/// (이 워크스페이스가 열 번 넘게 기록한 *"로직은 맞는데 안 불린다"* 패턴.)
void main() {
  String read(String p) {
    final f = File(p);
    // ⚠️ 못 찾으면 조용히 빈 문자열을 쓰지 않는다 — 모든 단언이 공허하게 통과한다
    expect(f.existsSync(), isTrue, reason: '검사 대상을 못 찾았다: $p (패키지 루트에서 돌려야 한다)');
    return f.readAsStringSync();
  }

  test('🔴 업싱크 UI 가 역할 판정 뒤에 있다', () {
    final raw = read('lib/features/teacher/teacher_home_screen.dart');
    /*
     * 🔴 **주석을 먼저 지운다.** 첫 판은 `contains('canUpsync')` 만 봤는데,
     *    판정을 `if (true)` 로 바꿔도 **주석에 남은 단어** 때문에 통과했다
     *    (2026-09-16 변이 검증에서 실제로 안 잡혔다). 제품이 아니라 자가 느슨했다.
     */
    final s = raw.split('\n').where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
    }).join('\n');

    expect(s, contains('canUpsync'),
        reason: '부모 모드에서 학교 서버 업싱크가 그대로 보인다 — 2026-09-16 결정 위반');
    // 판정이 **실제로 그 패널을 감싸는가** — 호출부 바로 앞에 있어야 한다
    final panelAt = s.indexOf('_buildUpsyncPanel(context)');
    expect(panelAt, greaterThan(0));
    final before = s.substring((panelAt - 300).clamp(0, panelAt), panelAt);
    expect(before, contains('canUpsync'),
        reason: '업싱크 패널 호출부 앞에 역할 판정이 없다 — 부모에게도 그대로 보인다');
  });

  test('역할 이름을 하드코딩하지 않는다 (부모인데 "교사" 라고 뜨면 안 된다)', () {
    final s = read('lib/features/teacher/teacher_home_screen.dart');
    for (final bad in ["hostDisplayName: '교사'", "JamminBrandTitle(subtitle: '교사')"]) {
      expect(s, isNot(contains(bad)), reason: '하드코딩된 역할 이름: $bad');
    }
  });

  test('부모 엔트리가 실재하고 parent 역할로 기동한다', () {
    final s = read('lib/main_parent.dart');
    expect(s, contains('AppRole.parent'));
    expect(s, contains('bootstrap('));
  });

  test('라우터가 "교사인가" 가 아니라 "허브인가" 를 묻는다', () {
    final s = read('lib/router/app_router.dart');
    expect(s, contains('role.isHub'));
    expect(s, isNot(contains('role == AppRole.teacher')),
        reason: '역할이 셋인데 교사만 보면 부모가 학생 화면으로 떨어진다');
  });

  /// ⚠️ **자 자신의 검사** — 이 파일이 실제로 코드를 읽었는지.
  test('검사 대상이 비어 있지 않다 (공허한 통과 방지)', () {
    expect(read('lib/features/teacher/teacher_home_screen.dart').length, greaterThan(5000));
    expect(read('lib/router/app_router.dart').length, greaterThan(200));
  });
}
