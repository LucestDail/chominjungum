import 'package:hangul_core/hangul_core.dart';
import 'package:test/test.dart';

/// 획순 표 검산.
///
/// **두 가지가 동시에 맞아야** 표가 옳다:
///   1. 묶음 합계 = 자산의 실제 선분 수  ← 앱 쪽 테스트가 SVG 를 읽어 대조한다
///   2. 묶음 개수 = 정통 획수            ← 여기서 검사
/// 하나만 맞으면 표가 틀린 것이다.
void main() {
  test('표의 묶음 개수가 정통 획수와 같다', () {
    final wrong = <String>[];
    for (final e in strokeGroups.entries) {
      final expected = strokeCount[e.key];
      if (expected == null) {
        wrong.add('${e.key}: 정통 획수 미정의');
      } else if (e.value.length != expected) {
        wrong.add('${e.key}: 묶음 ${e.value.length} ≠ 획수 $expected');
      }
    }
    expect(wrong, isEmpty);
  });

  test('획수 표가 자모 40개를 모두 덮는다', () {
    const cho = 'ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ';
    const jung = 'ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ';
    for (final ch in (cho + jung).split('')) {
      expect(strokeCount[ch], isNotNull, reason: '$ch 획수가 없다');
    }
  });

  group('선분 묶기', () {
    test('ㄷ 은 1획(윗가로) + 2획(ㄴ 모양)', () {
      expect(groupSegments('ㄷ', 3), [
        [0],
        [1, 2],
      ]);
    });

    test('ㅇ 은 사분원 4개가 통째로 1획', () {
      expect(groupSegments('ㅇ', 4), [
        [0, 1, 2, 3],
      ]);
    });

    test('표에 없는 자모는 선분 하나가 한 획', () {
      expect(groupSegments('ㅏ', 2), [
        [0],
        [1],
      ]);
    });

    test('🔴자산이 바뀌어 합계가 안 맞으면 표를 믿지 않는다', () {
      // 잘못 묶어 엉뚱한 획순을 가르치느니 안내를 포기하는 편이 낫다.
      expect(groupSegments('ㄷ', 5), [
        [0],
        [1],
        [2],
        [3],
        [4],
      ]);
      expect(isStrokeOrderKnown('ㄷ', 5), isFalse);
    });
  });

  group('믿을 수 있는가 판정', () {
    test('표에 있고 검산이 맞으면 참', () {
      expect(isStrokeOrderKnown('ㄱ', 2), isTrue);
      expect(isStrokeOrderKnown('ㅎ', 6), isTrue);
    });

    test('표에 없어도 선분 수가 획수와 같으면 참', () {
      expect(isStrokeOrderKnown('ㅏ', 2), isTrue);
      expect(isStrokeOrderKnown('ㅂ', 4), isTrue);
    });

    test('선분 수가 획수와 다르면 거짓 — ㅟ 자산이 실제로 그렇다', () {
      // ㅟ = ㅜ + ㅣ = 3획인데 자산에는 선분이 2개뿐이다(2026-09-10 실측).
      expect(isStrokeOrderKnown('ㅟ', 2), isFalse);
    });

    test('모르는 글자는 거짓', () {
      expect(isStrokeOrderKnown('A', 1), isFalse);
    });
  });
}
