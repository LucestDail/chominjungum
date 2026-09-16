import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// 🔴 **만들어 놓고 안 부르면 없는 것과 같다.**
///
/// `AiComposeService` 는 12개 테스트로 초록불이지만 **호출부를 지워도 전부 통과한다.**
/// 오늘 이 저장소에서 같은 모양을 두 번 겪었다 — 부모 모드에서 업싱크 UI 가 역할을
/// 안 보고 있었고, 형제 세션은 익명 프로필이 736만 행 쌓이는 것을 **아무도 그 경로를
/// 실제로 태워 보지 않아** 놓쳤다.
void main() {
  /// ⚠️ 주석을 지우고 본다 — 주석에 남은 이름을 "호출" 로 세면 자가 거짓말한다
  /// (2026-09-16 에 `contains('canUpsync')` 가 주석 때문에 통과한 적이 있다).
  String code(String path) {
    final f = File(path);
    expect(f.existsSync(), isTrue, reason: '검사 대상을 못 찾았다: $path');
    final src = f.readAsStringSync();
    expect(src.length, greaterThan(1000), reason: '$path 가 비어 있다 — 공허한 통과 방지');
    return src
        .split('\n')
        .where((l) {
          final t = l.trimLeft();
          return !t.startsWith('//') && !t.startsWith('///') && !t.startsWith('*');
        })
        .join('\n');
  }

  const screen = 'lib/features/teacher/teacher_home_screen.dart';

  test('🔴 AI 출제가 화면에서 실제로 불린다', () {
    final s = code(screen);
    expect(s, contains('AiComposeService'));
    // 정의가 아니라 **호출**이 있어야 한다
    expect('_composeWithAi'.allMatches(s).length, greaterThanOrEqualTo(2),
        reason: '핸들러가 정의만 되고 버튼에 연결되지 않았다');
    expect(s, contains('_ai.compose('));
  });

  test('🔴 동의가 켜져 있을 때만 UI 가 뜬다', () {
    final s = code(screen);
    // 버튼이 `isEnabled()` 뒤에 있어야 한다 — 꺼져 있는데 보이면 누르고 실패만 본다
    final at = s.indexOf('_aiConsent.isEnabled()');
    expect(at, greaterThan(0), reason: '동의 확인 없이 AI UI 가 그려진다');
    expect(s.substring(at, (at + 900).clamp(0, s.length)), contains('_composeWithAi'));
  });

  test('🔴 키·주소가 없으면 조용히 지나가지 않는다', () {
    final s = code(screen);
    /*
     * ⚠️ 첫 판은 `baseUrl()` 뒤 400자에 `_snack(` 이 있으면 통과였다 —
     *    안내를 지워도 **그 아래 다른 _snack** 때문에 통과했다.
     *    ⇒ **null 검사 블록 안**만 본다.
     */
    final at = s.indexOf('key == null || url == null');
    expect(at, greaterThan(0), reason: '키·주소 없음을 검사하지 않는다');
    final close = s.indexOf('}', at);
    final block = s.substring(at, close);
    expect(block, contains('_snack('),
        reason: '키·주소가 없을 때 조용히 return 한다 — '
            '"눌렀는데 아무 일도 안 일어난다" 가 가장 나쁜 실패다: $block');
  });

  test('⚠️ 결과를 덮어쓰지 않고 덧붙인다 (교사가 쓴 문장을 지우면 안 된다)', () {
    final s = code(screen);
    /*
     * ⚠️ 첫 판은 `r.items.join` 앞 300자에 'existing' 이 있으면 통과였다 —
     *    덮어쓰기로 바꿔도 **위쪽 `final existing = ...` 줄** 때문에 통과했다.
     *    ⇒ **대입문 자체**를 본다.
     */
    final at = s.indexOf('_sentence.text =');
    expect(at, greaterThan(0), reason: 'AI 결과를 입력란에 넣는 코드가 없다');
    final stmt = s.substring(at, s.indexOf(';', at));
    expect(stmt, contains('existing'),
        reason: 'AI 결과가 교사가 이미 쓴 문장을 덮어쓴다: $stmt');
  });

  test('학생 데이터가 호출에 실리지 않는다 (호출부 기준)', () {
    final s = code(screen);
    final at = s.indexOf('_ai.compose(');
    expect(at, greaterThan(0));
    final call = s.substring(at, s.indexOf(');', at));
    for (final leaked in ['attempt', 'nickname', 'deviceId', '_pending', 'submission']) {
      expect(call, isNot(contains(leaked)), reason: 'compose() 호출에 $leaked 가 실렸다');
    }
  });
}
