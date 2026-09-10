
import 'package:chominjungum/services/stroke_order_check.dart';
import 'package:flutter_test/flutter_test.dart';

/// 손글씨 획을 **규칙으로** 본다 — 모양이 아니라 순서·방향.
///
/// 글씨를 "잘 썼는지"는 인식이 필요해서 판정하지 않는다. 좌표만으로 확실히
/// 말할 수 있는 것(획수·방향·순서)만 본다.
void main() {
  const cell = 100.0;

  List<Offset> line(double x1, double y1, double x2, double y2) =>
      [Offset(x1, y1), Offset((x1 + x2) / 2, (y1 + y2) / 2), Offset(x2, y2)];

  group('방향', () {
    test('가로획을 오른쪽으로 그으면 맞다', () {
      final v = StrokeOrderCheck.check([line(10, 20, 90, 20)], cellSize: cell);
      expect(v.every((x) => x.ok), isTrue);
    });

    test('🔴가로획을 왼쪽으로 그으면 지적한다', () {
      final v = StrokeOrderCheck.check([line(90, 20, 10, 20)], cellSize: cell);
      expect(v.single.ok, isFalse);
      expect(v.single.reason, contains('왼쪽에서 오른쪽'));
    });

    test('세로획은 위에서 아래', () {
      expect(
        StrokeOrderCheck.check([line(50, 10, 50, 90)], cellSize: cell)
            .every((x) => x.ok),
        isTrue,
      );
      final up = StrokeOrderCheck.check([line(50, 90, 50, 10)], cellSize: cell);
      expect(up.single.reason, contains('위에서 아래'));
    });

    test('⚠️대각선은 판정하지 않는다 — ㅅ 삐침을 틀렸다고 하면 안 된다', () {
      final v = StrokeOrderCheck.check([line(50, 10, 20, 90)], cellSize: cell);
      expect(v.every((x) => x.ok), isTrue);
    });
  });

  group('획수', () {
    test('모자라면 알려준다', () {
      final v = StrokeOrderCheck.check(
        [line(10, 20, 90, 20)],
        cellSize: cell,
        expectedStrokeCount: 2,
      );
      expect(v.any((x) => x.reason.contains('모자랍니다')), isTrue);
    });

    test('많아도 알려준다', () {
      final v = StrokeOrderCheck.check(
        [line(10, 20, 90, 20), line(10, 50, 90, 50), line(10, 80, 90, 80)],
        cellSize: cell,
        expectedStrokeCount: 2,
      );
      expect(v.any((x) => x.reason.contains('많습니다')), isTrue);
    });

    test('⚠️점 찍기·손 떨림은 획으로 세지 않는다', () {
      final v = StrokeOrderCheck.check(
        [
          line(10, 20, 90, 20),
          [const Offset(50, 50), const Offset(51, 51)], // 아주 짧다
        ],
        cellSize: cell,
        expectedStrokeCount: 1,
      );
      expect(v.any((x) => x.reason.contains('많습니다')), isFalse);
    });
  });

  group('순서', () {
    test('위에서 아래로 그으면 맞다', () {
      final v = StrokeOrderCheck.check(
        [line(10, 20, 90, 20), line(10, 70, 90, 70)],
        cellSize: cell,
      );
      expect(v.every((x) => x.ok), isTrue);
    });

    test('🔴아래 획을 먼저 그으면 지적한다', () {
      final v = StrokeOrderCheck.check(
        [line(10, 70, 90, 70), line(10, 20, 90, 20)],
        cellSize: cell,
      );
      expect(v.any((x) => x.reason.contains('위쪽 획을 먼저')), isTrue);
    });

    test('같은 높이면 왼쪽부터', () {
      final v = StrokeOrderCheck.check(
        [line(70, 20, 70, 80), line(20, 20, 20, 80)],
        cellSize: cell,
      );
      expect(v.any((x) => x.reason.contains('왼쪽 획을 먼저')), isTrue);
    });
  });

  group('요약', () {
    test('지적이 없으면 null', () {
      expect(
        StrokeOrderCheck.summarize(
          StrokeOrderCheck.check([line(10, 20, 90, 20)], cellSize: cell),
        ),
        isNull,
      );
    });

    test('같은 지적이 여러 번이어도 한 번만 말한다 — 잔소리가 되면 안 읽는다', () {
      final v = StrokeOrderCheck.check(
        [line(90, 20, 10, 20), line(90, 60, 10, 60)],
        cellSize: cell,
      );
      final msg = StrokeOrderCheck.summarize(v)!;
      expect('왼쪽에서 오른쪽'.allMatches(msg).length, 1);
    });
  });
}
