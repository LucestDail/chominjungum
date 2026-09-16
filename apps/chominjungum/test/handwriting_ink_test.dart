import 'dart:io';
import 'dart:ui' show Offset, Size;

import 'package:chominjungum/services/handwriting_ink.dart';
import 'package:chominjungum/services/handwriting_recognizer.dart';
import 'package:flutter_test/flutter_test.dart';

/// 손글씨 잉크 변환 — **좌표를 다루는 부분은 전부 여기서 검증된다.**
///
/// 네이티브(ML Kit)는 리허설 뒤에 꽂기로 했으므로(2026-09-16 결정), 지금 잠글 수 있는
/// 것은 **화면 좌표 → 인식기 입력** 구간이다. 그 구간이 맞아 두면 나중에 꽂을 때
/// 새로 검증할 것이 네이티브 호출뿐이다.
void main() {
  const area = Size(100, 100);

  List<List<Offset>> line(int n, {double step = 5}) => [
        [for (var i = 0; i < n; i++) Offset(i * step, 10)]
      ];

  group('획 변환', () {
    test('점마다 시각이 증가한다 — 인식기는 쓰는 순서·속도를 쓴다', () {
      final ink = InkBuilder.fromOffsets(line(3), area: area, msPerPoint: 8);
      final ts = ink.strokes.single.points.map((p) => p.tMillis).toList();
      expect(ts, [0, 8, 16]);
    });

    test('시각이 획을 넘어 이어진다 (두 번째 획이 0부터 다시 시작하지 않는다)', () {
      final ink = InkBuilder.fromOffsets([
        [const Offset(0, 0), const Offset(10, 0)],
        [const Offset(0, 20), const Offset(10, 20)],
      ], area: area, msPerPoint: 5);
      expect(ink.strokes[0].points.last.tMillis, 5);
      expect(ink.strokes[1].points.first.tMillis, 10);
    });

    test('빈 획은 버린다', () {
      final ink = InkBuilder.fromOffsets([
        [],
        [const Offset(0, 0), const Offset(10, 0)],
        [],
      ], area: area);
      expect(ink.strokes, hasLength(1));
    });
  });

  group('⚠️ 촘촘한 점 솎기 — 안 하면 한 글자가 수천 점이 된다', () {
    test('최소 간격보다 가까운 점을 버린다', () {
      final dense = [
        [for (var i = 0; i < 20; i++) Offset(i * 0.5, 0)] // 0.5px 간격
      ];
      final ink = InkBuilder.fromOffsets(dense, area: area);
      expect(ink.pointCount, lessThan(20));
      expect(ink.pointCount, greaterThan(1), reason: '전부 버리면 획이 사라진다');
    });

    test('★ 자의 판별력 — 넉넉한 간격은 그대로 남긴다', () {
      final ink = InkBuilder.fromOffsets(line(5, step: 10), area: area);
      expect(ink.pointCount, 5);
    });

    test('첫 점은 언제나 남는다 (기준점이 없으면 획이 통째로 사라진다)', () {
      final ink = InkBuilder.fromOffsets([
        [const Offset(3, 3), const Offset(3.1, 3.1)]
      ], area: area);
      expect(ink.pointCount, 1);
      expect(ink.strokes.single.points.single.x, 3);
    });
  });

  group('🔴 망가진 입력에 터지지 않는다', () {
    test('NaN·무한대 좌표를 버린다 — 하나가 인식기를 통째로 실패시킨다', () {
      final ink = InkBuilder.fromOffsets([
        [const Offset(0, 0), Offset(double.nan, 5), Offset(double.infinity, 9), const Offset(20, 0)]
      ], area: area);
      for (final p in ink.strokes.single.points) {
        expect(p.x.isFinite && p.y.isFinite, isTrue);
      }
      expect(ink.pointCount, 2);
    });

    test('빈 입력', () {
      final ink = InkBuilder.fromOffsets([], area: area);
      expect(ink.isEmpty, isTrue);
      expect(ink.pointCount, 0);
    });
  });

  group('칸 밖 판정 — "왜 못 알아듣지" 의 원인을 코드가 가른다', () {
    test('칸 안이면 참', () {
      expect(InkBuilder.fitsInArea(InkBuilder.fromOffsets(line(3), area: area)), isTrue);
    });

    test('칸을 크게 벗어나면 거짓', () {
      final out = InkBuilder.fromOffsets([
        [const Offset(10, 10), const Offset(400, 10)]
      ], area: area);
      expect(InkBuilder.fitsInArea(out), isFalse);
    });

    test('⚠️ 아슬아슬한 경계는 봐준다 (선 두께 때문에 조금 넘친다)', () {
      final edge = InkBuilder.fromOffsets([
        [const Offset(0, 0), const Offset(102, 100)]
      ], area: area);
      expect(InkBuilder.fitsInArea(edge, tolerance: 4), isTrue);
    });

    test('빈 잉크는 칸 안으로 본다 (없는 것을 벗어났다고 하지 않는다)', () {
      expect(InkBuilder.fitsInArea(InkBuilder.fromOffsets([], area: area)), isTrue);
    });
  });

  group('인식기 계약', () {
    test('🔴 기본 구현은 "없다" 고 정직하게 답한다 — 빈 성공을 내지 않는다', () async {
      const r = UnavailableHandwritingRecognizer();
      expect(await r.isAvailable(), isFalse);

      final res = await r.recognize(InkBuilder.fromOffsets(line(3), area: area));
      expect(res.ok, isFalse,
          reason: '빈 결과 + 성공을 내면 사용자는 자기 글씨가 나쁜 줄 안다');
      expect(res.error, isNotNull);
      expect(res.best, isNull);
    });

    test('후보 0개와 실패를 구분한다', () {
      final empty = HandwritingResult.success(const []);
      expect(empty.ok, isTrue);
      expect(empty.isEmptyAfterRecognize, isTrue);

      final failed = HandwritingResult.failure('x');
      expect(failed.isEmptyAfterRecognize, isFalse);
    });

    test('best 는 첫 후보다', () {
      final r = HandwritingResult.success(const ['가', '카', '갸']);
      expect(r.best, '가');
    });
  });

  group('인식기에 넘길 모양', () {
    test('칸 크기가 함께 간다 — 없으면 기기마다 결과가 달라진다', () {
      final p = InkBuilder.fromOffsets(line(2), area: const Size(64, 80)).toPayload();
      expect(p['width'], 64.0);
      expect(p['height'], 80.0);
    });

    test('획 구조와 점 개수가 보존된다', () {
      final ink = InkBuilder.fromOffsets([
        [const Offset(0, 0), const Offset(10, 0)],
        [const Offset(0, 20), const Offset(10, 20), const Offset(20, 20)],
      ], area: area);
      final strokes = (ink.toPayload()['strokes']! as List);
      expect(strokes, hasLength(2));
      expect((strokes[0] as List), hasLength(2));
      expect((strokes[1] as List), hasLength(3));
      expect((strokes[0] as List).first, containsPair('t', 0));
    });
  });

  group('🔴 씨앗이 네이티브를 끌어오지 않는다 — 미루기로 한 바로 그 이유', () {
    /*
     * 2026-09-16 결정: 네이티브(ML Kit)는 **교실 2대 리허설이 끝난 뒤** 꽂는다.
     * 붙이는 순간 iOS 시뮬레이터 빌드가 깨지고, 이 저장소는 실기기가 한 대뿐이라
     * 그 리허설을 시뮬레이터 허브로 치러야 하기 때문이다.
     *
     * ⚠️ 그 결정은 **주석으로 지켜지지 않는다.** 누가 여기에 `google_mlkit_*` 를
     *    import 하면 리허설이 그날로 막힌다. 그래서 테스트가 들고 있는다.
     */
    for (final f in const ['handwriting_ink.dart', 'handwriting_recognizer.dart']) {
      test('$f 은 flutter/dart 밖을 import 하지 않는다', () {
        final src = File('lib/services/$f').readAsStringSync();
        expect(src.length, greaterThan(500), reason: '$f 이 비어 있다 — 공허한 통과 방지');

        final external = src
            .split('\n')
            .where((l) => l.startsWith("import 'package:"))
            .where((l) => !l.contains("package:flutter/"))
            .toList();
        expect(external, isEmpty,
            reason: '씨앗에 외부 패키지가 들어왔다 — 시뮬레이터가 깨지면 '
                '교실 2대 리허설(유일한 잔여 과제)을 못 한다: $external');
      });
    }
  });
}
