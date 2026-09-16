import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

/// 손글씨 **잉크** — 획 좌표를 인식기에 넘길 수 있는 모양으로 담는다.
///
/// ## 왜 순수 Dart 인가 (2026-09-16)
///
/// 손글씨 인식 수단은 **ML Kit Digital Ink** 로 정했다(양 플랫폼·한국어 `ko` 지원).
/// 그런데 그 네이티브 의존성을 붙이는 순간 **iOS 시뮬레이터 빌드가 깨진다**
/// (arm64 슬라이스 부재는 Digital Ink 만이 아니라 `GoogleMLKit`·`MLKitCommon`·
/// `MLKitVision` 파드 전체·iOS 26+).
///
/// 🔴 이 저장소는 실기기가 **한 대뿐**이라 교실 왕복 검증을 **시뮬레이터 허브**로
/// 통과시켜 왔고(`PLAN §204`), 유일한 잔여 과제가 그 2대 리허설이다.
/// 그리고 `PLAN §231` 이 *"다시 할 때는 **시뮬레이터 검증을 포기하지 않는 대안**을
/// 먼저 따질 것"* 이라고 스스로 적어 뒀다.
///
/// ⇒ **판정(여기)과 실행(네이티브)을 갈랐다.** 좌표를 다루는 부분은 전부 여기 있고
/// 브라우저·기기 없이 테스트된다. 네이티브는 [HandwritingRecognizer] 뒤에 꽂힌다.
/// 리허설이 끝난 뒤 꽂으면 **잃을 것이 없다**(2026-09-16 사용자 결정).
class HandwritingInk {
  const HandwritingInk({required this.strokes, required this.area});

  /// 획 목록. 각 획은 점의 나열이다.
  final List<HandwritingStroke> strokes;

  /// 글씨를 쓴 칸의 크기 — 인식기가 글자 크기를 가늠하는 데 쓴다.
  ///
  /// ⚠️ 이걸 안 넘기면 인식기가 좌표의 절대값으로 판단해, **칸 크기가 다른 기기에서
  /// 결과가 달라진다.** 아이패드와 아이폰이 다르게 읽히면 원인을 찾기 어렵다.
  final Size area;

  bool get isEmpty => strokes.isEmpty;

  int get pointCount => strokes.fold(0, (n, s) => n + s.points.length);

  /// 인식기에 넘길 표준 모양.
  ///
  /// 🔴 **여기서 바로 네이티브를 부르지 않는다.** 이 형태가 곧 계약이고,
  /// 실제 인식기는 이걸 받아 각자의 형식으로 옮긴다.
  Map<String, Object?> toPayload() => {
        'width': area.width,
        'height': area.height,
        'strokes': [
          for (final s in strokes)
            [
              for (final p in s.points) {'x': p.x, 'y': p.y, 't': p.tMillis}
            ]
        ],
      };
}

class HandwritingStroke {
  const HandwritingStroke(this.points);
  final List<InkPoint> points;
}

/// 한 점 — 좌표와 **시각**.
///
/// ⚠️ 시각이 왜 필요한가: 인식기는 **획이 그려진 순서와 속도**를 쓴다.
/// 시각이 전부 0이면 인식률이 떨어진다(같은 모양이라도 쓰는 방법이 다르면 다른 글자다).
class InkPoint {
  const InkPoint(this.x, this.y, this.tMillis);
  final double x;
  final double y;
  final int tMillis;
}

/// 화면에서 받은 획을 [HandwritingInk] 로 옮긴다.
class InkBuilder {
  const InkBuilder._();

  /// 점 사이 최소 거리(px). 이보다 촘촘한 점은 버린다.
  ///
  /// ⚠️ 손가락·펜은 초당 수십~수백 점을 낸다. 그대로 보내면 **한 글자에 수천 점**이 되어
  /// 인식이 느려지고 배터리를 먹는다. 모양은 바뀌지 않는 선에서 솎는다.
  static const minGap = 2.0;

  /// 너무 짧은 획은 **점 찍힌 실수**로 본다 — 버리면 인식이 깨끗해진다.
  ///
  /// ⚠️ 다만 **0 으로 두지 않는다.** 한글에는 진짜 점 획이 없지만(ㅗ·ㅜ 의 짧은 획도
  /// 선이다) 구두점은 점이다. 그래서 *길이* 가 아니라 *점 개수* 로만 거른다.
  static const minPointsPerStroke = 1;

  /// @param raw `HangulWritingCell.onStrokesChanged` 가 주는 것
  /// @param area 칸 크기
  /// @param startedAt 첫 점의 기준 시각(없으면 0부터)
  /// @param msPerPoint 시각 정보가 없을 때 점마다 더할 간격
  ///
  /// 🔴 화면 위젯은 시각을 안 준다. 그래서 **균등 간격으로 추정**한다 —
  /// 없는 것을 있는 척하지 않도록 이 사실을 여기 적어 둔다. 실제 속도가 필요해지면
  /// `HangulWritingCell` 이 시각을 함께 주도록 바꿔야 한다.
  static HandwritingInk fromOffsets(
    List<List<Offset>> raw, {
    required Size area,
    int startedAt = 0,
    int msPerPoint = 8,
  }) {
    final strokes = <HandwritingStroke>[];
    var t = startedAt;

    for (final s in raw) {
      if (s.isEmpty) continue;
      final pts = <InkPoint>[];
      Offset? last;
      for (final o in s) {
        // ⚠️ 유한하지 않은 좌표는 버린다 — NaN 하나가 인식기를 통째로 실패시킨다
        if (!o.dx.isFinite || !o.dy.isFinite) continue;
        if (last != null && (o - last).distance < minGap) continue;
        pts.add(InkPoint(o.dx, o.dy, t));
        t += msPerPoint;
        last = o;
      }
      if (pts.length < minPointsPerStroke) continue;
      strokes.add(HandwritingStroke(pts));
    }
    return HandwritingInk(strokes: strokes, area: area);
  }

  /// 획이 칸을 벗어났는지 — **인식 전에 사람에게 알려 줄 수 있다.**
  ///
  /// ⚠️ 벗어난 채로 인식을 돌리면 "왜 못 알아듣지" 가 되는데, 원인은 모델이 아니라
  /// 글씨가 칸 밖이라서다. 그 구분을 코드가 해 준다.
  static bool fitsInArea(HandwritingInk ink, {double tolerance = 4.0}) {
    if (ink.isEmpty) return true;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final s in ink.strokes) {
      for (final p in s.points) {
        minX = math.min(minX, p.x);
        minY = math.min(minY, p.y);
        maxX = math.max(maxX, p.x);
        maxY = math.max(maxY, p.y);
      }
    }
    return minX >= -tolerance &&
        minY >= -tolerance &&
        maxX <= ink.area.width + tolerance &&
        maxY <= ink.area.height + tolerance;
  }
}
