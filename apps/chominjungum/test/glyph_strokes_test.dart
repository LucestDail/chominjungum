import 'dart:io';

import 'package:chominjungum/services/glyph_strokes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangul_core/hangul_core.dart';

/// 획순 표가 **실제 자산과 맞는지** 전수 대조.
///
/// `hangul_core` 쪽 테스트는 "묶음 개수 = 정통 획수"만 본다. 그것만 맞으면 표가
/// 옳다고 할 수 없다 — **묶음 합계가 자산의 선분 수와도 같아야** 한다. 둘 중
/// 하나만 맞으면 엉뚱한 선분을 한 획으로 묶어 **틀린 획순을 가르치게 된다.**
///
/// 자산이 바뀌면(변환기를 다시 돌리면) 여기서 깨진다.
void main() {
  String read(int code) =>
      File('assets/hangul/$code.svg').readAsStringSync();

  const cho = 'ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ';
  const jung = 'ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ';

  test('초성 19 · 중성 21 자산에서 획을 뽑을 수 있다', () {
    final failed = <String>[];
    for (var i = 0; i < cho.length; i++) {
      if (GlyphStrokeLoader.parse(read(4352 + i), code: 4352 + i) == null) {
        failed.add(cho[i]);
      }
    }
    for (var i = 0; i < jung.length; i++) {
      if (GlyphStrokeLoader.parse(read(4449 + i), code: 4449 + i) == null) {
        failed.add(jung[i]);
      }
    }
    expect(failed, isEmpty, reason: '글리프 그룹을 못 찾은 자모: $failed');
  });

  test('🔴자산의 그룹 id 는 믿을 수 없다 — 자모는 파일명으로 판단한다', () {
    // ㅟ(4465) 자산의 그룹 id 가 `_x3157_`(ㅗ)로 붙어 있다(2026-09-10 실측).
    // id 를 믿으면 ㅗ 의 획순 표를 찾아 **2획이 맞다고** 잘못 판정한다.
    final code = 4449 + jung.indexOf('ㅟ');
    expect(GlyphStrokeLoader.parse(read(code), code: code)!.letter, 'ㅟ');
    // 파일명으로 판단하면 자모 전체가 제 글자로 나온다.
    for (var i = 0; i < cho.length; i++) {
      expect(GlyphStrokeLoader.parse(read(4352 + i), code: 4352 + i)!.letter,
          cho[i]);
    }
    for (var i = 0; i < jung.length; i++) {
      expect(GlyphStrokeLoader.parse(read(4449 + i), code: 4449 + i)!.letter,
          jung[i]);
    }
  });

  test('★표의 묶음 합계가 자산의 실제 선분 수와 같다', () {
    final wrong = <String>[];
    for (final entry in strokeGroups.entries) {
      final idx = cho.indexOf(entry.key);
      if (idx < 0) continue;
      final g = GlyphStrokeLoader.parse(read(4352 + idx), code: 4352 + idx)!;
      final sum = entry.value.fold(0, (a, b) => a + b);
      if (sum != g.segments) {
        wrong.add('${entry.key}: 표 합계 $sum ≠ 자산 선분 ${g.segments}');
      }
    }
    expect(wrong, isEmpty,
        reason: '표가 자산과 어긋났다 — 이대로면 틀린 획순을 가르친다:\n${wrong.join("\n")}');
  });

  test('★믿을 수 있다고 판정한 자모는 획수까지 맞는다', () {
    final wrong = <String>[];
    void check(String letter, int code) {
      final g = GlyphStrokeLoader.parse(read(code), code: code);
      if (g == null || !g.isKnownOrder) return; // 모른다고 한 것은 검사 대상 아님
      final expected = strokeCount[letter];
      if (g.strokeCountOf != expected) {
        wrong.add('$letter: 획 ${g.strokeCountOf} ≠ 정통 $expected');
      }
    }

    for (var i = 0; i < cho.length; i++) {
      check(cho[i], 4352 + i);
    }
    for (var i = 0; i < jung.length; i++) {
      check(jung[i], 4449 + i);
    }
    expect(wrong, isEmpty);
  });

  test('⚠️ㅟ 는 자산에 선분이 모자라 "모른다"로 떨어진다', () {
    // ㅟ = ㅜ + ㅣ = 3획인데 자산 그룹에는 선분이 2개뿐이다(2026-09-10 실측).
    // 억지로 묶지 않고 안내를 포기하는 것이 맞다.
    final g = GlyphStrokeLoader.parse(read(4449 + jung.indexOf('ㅟ')), code: 4449 + jung.indexOf('ㅟ'))!;
    expect(g.isKnownOrder, isFalse);
  });

  test('알려진 획순 자모가 충분히 많다 — 안내가 실효가 있으려면', () {
    var known = 0;
    for (var i = 0; i < cho.length; i++) {
      if (GlyphStrokeLoader.parse(read(4352 + i), code: 4352 + i)!.isKnownOrder) known++;
    }
    for (var i = 0; i < jung.length; i++) {
      if (GlyphStrokeLoader.parse(read(4449 + i), code: 4449 + i)!.isKnownOrder) known++;
    }
    expect(known, greaterThanOrEqualTo(39), reason: '40개 중 $known개만 안다');
  });

  group('구체 사례', () {
    test('ㄱ — 선분 2개가 1획', () {
      final g = GlyphStrokeLoader.parse(read(4352), code: 4352)!;
      expect(g.segments, 2);
      expect(g.strokes, [
        [0, 1],
      ]);
      expect(g.isKnownOrder, isTrue);
    });

    test('ㅎ — 점·가로·원(사분원 4개) = 3획', () {
      final g = GlyphStrokeLoader.parse(read(4370), code: 4370)!;
      expect(g.segments, 6);
      expect(g.strokes.length, 3);
      expect(g.strokes.last, hasLength(4), reason: '원이 통째로 한 획이다');
    });

    test('ㅘ — 복합 모음은 그룹이 여러 개인데 모두 세어야 한다', () {
      final g = GlyphStrokeLoader.parse(read(4449 + jung.indexOf('ㅘ')), code: 4449 + jung.indexOf('ㅘ'))!;
      expect(g.segments, 4);
      expect(g.strokes.length, 4);
    });
  });
}
