import 'package:chominjungum/services/dictation_composer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangul_core/hangul_core.dart';

/// 정규화가 **채점 경로에 실제로 걸려 있는지**.
///
/// 유틸을 만들어 놓고 안 쓰면 없는 것과 같다(초민정음에서 여러 번 겪은 패턴).
/// 화면 위젯을 띄우는 대신, 화면이 하는 것과 같은 순서로 돌려 결과를 비교한다.
void main() {
  test('조합이 덜 끝난 자모로 낸 답이 정답으로 채점된다', () {
    final item = DictationComposer.compose('학교');
    // iOS 자판이 조합 중에 내놓는 결합 자모 표현.
    const typed = '\u1112\u1161\u11A8\u1100\u116D';

    final raw = DictationCompare.score(
      expected: item.expectedText,
      actual: typed.trim(),
    );
    final wired = DictationCompare.score(
      expected: item.expectedText,
      actual: normalizeAnswer(typed),
    );

    expect(wired.ratio, 1.0, reason: '정규화하면 정답이다');
    expect(raw.ratio, lessThan(1.0), reason: '정규화 없이는 틀리게 채점된다');
  });

  test('앞뒤 공백·전각 물음표가 있어도 정답', () {
    final item = DictationComposer.compose('누구?');
    expect(
      DictationCompare.score(
        expected: item.expectedText,
        actual: normalizeAnswer('  누구？ '),
      ).ratio,
      1.0,
    );
  });

  test('⚠️맞춤법 오답은 그대로 오답이다', () {
    final item = DictationComposer.compose('갔다');
    expect(
      DictationCompare.score(
        expected: item.expectedText,
        actual: normalizeAnswer('갓다'),
      ).ratio,
      lessThan(1.0),
    );
  });
}
