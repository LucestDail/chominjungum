import 'package:hangul_core/hangul_core.dart';
import 'package:test/test.dart';

/// 답안 정규화 — "같은 답인데 다르게 적힌 것"만 맞춘다.
void main() {
  group('결합 자모 → 완성형', () {
    test('초성+중성+종성이 한 글자로 합쳐진다', () {
      // ᄒ ᅡ ᆨ  (U+1112 U+1161 U+11A8)
      expect(composeJamo('학'), '학');
    });

    test('받침 없는 글자', () {
      expect(composeJamo('가'), '가');
    });

    test('🔴종성처럼 보여도 뒤에 중성이 오면 다음 글자의 초성이다', () {
      // ᄀ ᅡ / ᄀ ᅩ  → "가고" (ㄱ 을 앞 글자 받침으로 먹으면 "각오" 가 된다)
      expect(composeJamo('가고'), '가고');
    });

    test('겹받침은 초성이 될 수 없으니 받침으로 붙는다', () {
      // ᄀ ᅡ ᆹ → 값
      expect(composeJamo('값'), '값');
    });

    test('합칠 수 없는 낱자는 호환 자모로 남는다', () {
      // 결합 자모 ᄀ 를 그대로 두면 학습지에서 자산을 못 찾는다.
      expect(composeJamo('ᄀ'), 'ㄱ');
      expect(composeJamo('ᅡ'), 'ㅏ');
    });

    test('이미 완성형인 글자는 건드리지 않는다', () {
      expect(composeJamo('학교에 간다'), '학교에 간다');
    });
  });

  group('공백', () {
    test('앞뒤 공백과 연속 공백을 정리한다', () {
      expect(collapseSpaces('  학교에   간다  '), '학교에 간다');
    });

    test('⚠️띄어쓰기 자체는 없애지 않는다 — 채점 대상이다', () {
      expect(collapseSpaces('학교에 간다'), '학교에 간다');
      expect(collapseSpaces('학교에간다'), '학교에간다');
    });
  });

  group('전각·유사 문자', () {
    test('전각 숫자·물음표가 반각이 된다', () {
      expect(normalizeAnswer('１２３？'), '123?');
    });

    test('전각 공백도 공백으로', () {
      expect(normalizeAnswer('가　나'), '가 나');
    });

    test('말줄임표는 마침표 한 글자로 — 학습지에 그 자산만 있다', () {
      expect(normalizeAnswer('가…'), '가.');
    });
  });

  group('전체 정규화', () {
    test('조합 중 자모 + 전각 + 공백이 섞여도 정답과 같아진다', () {
      const messy = '  학교  ！ ';
      expect(normalizeAnswer(messy), '학교 !');
    });

    test('⚠️맞춤법은 고치지 않는다 — 학생이 틀린 것이다', () {
      expect(normalizeAnswer('갓다'), '갓다');
    });

    test('빈 문자열', () {
      expect(normalizeAnswer('   '), '');
    });
  });

  group('정규화가 채점을 바꾼다', () {
    test('조합 중 자모로 낸 답도 정답으로 채점된다', () {
      const typed = '학교'; // 학교
      final raw = DictationCompare.score(expected: '학교', actual: typed);
      final fixed = DictationCompare.score(
        expected: '학교',
        actual: normalizeAnswer(typed),
      );
      expect(fixed.ratio, 1.0);
      expect(fixed.ratio, greaterThan(raw.ratio),
          reason: '정규화 전에는 같은 답이 틀리게 채점된다');
    });
  });
}
