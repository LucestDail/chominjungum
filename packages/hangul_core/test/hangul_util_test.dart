import 'dart:convert';

import 'package:hangul_core/hangul_core.dart';
import 'package:test/test.dart';

void main() {
  group('HangulUtil', () {
    test('hangulSplit matches jammin syllable decomposition', () {
      final g = HangulUtil.hangulSplit('가');
      expect(g.length, 1);
      expect(g[0].word, '가');
      expect(g[0].chosung, String.fromCharCode(0x1100));
      expect(g[0].jungsung, String.fromCharCode(0x1161));
      expect(g[0].emptyJongsung, true);
      expect(g[0].specialFlag, false);
    });

    test('hangulSplit 받침', () {
      final g = HangulUtil.hangulSplit('값');
      expect(g[0].emptyJongsung, false);
      expect(g[0].jongsung, isNotNull);
    });

    test('special and number', () {
      final g = HangulUtil.hangulSplit('1,');
      expect(g[0].specialFlag, true);
      expect(g[1].specialFlag, true);
    });

    test('addWordJson roundtrip keys', () {
      final raw = HangulUtil.addWordJson('안녕');
      final list = jsonDecode(raw) as List<dynamic>;
      expect(list.length, 2);
      expect(list[0]['word'], '안');
      expect(list[1]['word'], '녕');
    });
  });

  group('DictationCompare', () {
    test('full match', () {
      final r = DictationCompare.score(expected: '가나', actual: '가나');
      expect(r.ratio, 1.0);
      expect(r.correctCount, 2);
    });

    test('partial', () {
      final r = DictationCompare.score(expected: '가나', actual: '가다');
      expect(r.correctCount, 1);
      expect(r.matches[1].isCorrect, false);
    });
  });
}
