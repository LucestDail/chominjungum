import 'dart:math' as math;
import 'dart:ui';

/// 학생이 그은 획 하나에 대한 판정.
class StrokeVerdict {
  const StrokeVerdict({
    required this.index,
    required this.ok,
    required this.reason,
  });

  /// 몇 번째 획인지(0부터).
  final int index;
  final bool ok;

  /// 사람이 읽을 사유. 틀렸을 때만 의미가 있다.
  final String reason;
}

/// 손글씨 획을 **획순 규칙으로** 본다 — 모양이 아니라 순서·방향.
///
/// ## 무엇을 판정하고 무엇을 판정하지 않나
///
/// 글씨를 "잘 썼는지"는 보지 않는다. 그건 인식이 필요하고, 인식 수단은 아직
/// 정하지 않았다(ML Kit 은 09-07 에 걷어냈다). 대신 **규칙으로 확실히 말할 수
/// 있는 것만** 본다:
///
///   - 획을 **몇 개** 그었나 (정통 획수와 맞나)
///   - 가로획을 **왼→오른쪽**으로 그었나
///   - 세로획을 **위→아래**로 그었나
///   - 획을 **위에서 아래, 왼쪽에서 오른쪽 순서**로 그었나
///
/// 이 넷은 초등 저학년 지도에서 실제로 고쳐 주는 것들이고, 좌표만으로 판정된다.
///
/// ⚠️**자산의 획순 표와는 다른 층위다.** 표(`strokeGroups`)는 *정답 글리프*가
/// 몇 획인지 말하고, 여기서는 *학생이 그은 것*을 본다.
class StrokeOrderCheck {
  const StrokeOrderCheck._();

  /// 가로/세로로 볼 최소 기울기 비율. 이보다 비스듬하면 대각선으로 보고
  /// 방향을 판정하지 않는다(ㅅ·ㅈ 의 삐침을 틀렸다고 하면 안 된다).
  static const _axisRatio = 2.0;

  /// 획으로 치지 않을 만큼 짧은 것(셀 크기 대비). 점 찍기·손 떨림.
  static const _minLengthRatio = 0.08;

  /// [strokes] 는 학생이 그은 획들(각 획은 점 목록), [cellSize] 는 칸 한 변.
  /// [expectedStrokeCount] 를 주면 획수도 본다.
  static List<StrokeVerdict> check(
    List<List<Offset>> strokes, {
    required double cellSize,
    int? expectedStrokeCount,
  }) {
    final out = <StrokeVerdict>[];
    final real = <List<Offset>>[];

    for (final s in strokes) {
      if (s.length < 2) continue;
      if (_length(s) >= cellSize * _minLengthRatio) real.add(s);
    }

    for (var i = 0; i < real.length; i++) {
      out.add(_checkOne(real[i], i));
    }

    // 획수는 전체를 다 본 뒤에야 말할 수 있다.
    if (expectedStrokeCount != null && real.length != expectedStrokeCount) {
      out.add(
        StrokeVerdict(
          index: real.length,
          ok: false,
          reason: real.length < expectedStrokeCount
              ? '획이 모자랍니다 (${real.length}/$expectedStrokeCount획)'
              : '획이 많습니다 (${real.length}/$expectedStrokeCount획)',
        ),
      );
    }

    // 순서: 대체로 위에서 아래, 같은 높이면 왼쪽에서 오른쪽.
    for (var i = 1; i < real.length; i++) {
      final prev = _start(real[i - 1]);
      final cur = _start(real[i]);
      final downward = cur.dy > prev.dy + cellSize * 0.15;
      final upward = cur.dy < prev.dy - cellSize * 0.15;
      if (upward) {
        out.add(
          StrokeVerdict(
            index: i,
            ok: false,
            reason: '위쪽 획을 먼저 긋습니다',
          ),
        );
      } else if (!downward && cur.dx < prev.dx - cellSize * 0.15) {
        out.add(
          StrokeVerdict(
            index: i,
            ok: false,
            reason: '왼쪽 획을 먼저 긋습니다',
          ),
        );
      }
    }

    return out;
  }

  /// 획 하나의 방향.
  static StrokeVerdict _checkOne(List<Offset> stroke, int index) {
    final a = _start(stroke);
    final b = _end(stroke);
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;

    if (dx.abs() > dy.abs() * _axisRatio) {
      // 가로획
      return StrokeVerdict(
        index: index,
        ok: dx > 0,
        reason: dx > 0 ? '' : '가로획은 왼쪽에서 오른쪽으로 긋습니다',
      );
    }
    if (dy.abs() > dx.abs() * _axisRatio) {
      // 세로획
      return StrokeVerdict(
        index: index,
        ok: dy > 0,
        reason: dy > 0 ? '' : '세로획은 위에서 아래로 긋습니다',
      );
    }
    // 대각선은 판정하지 않는다 — ㅅ·ㅈ 의 삐침을 틀렸다고 하면 안 된다.
    return StrokeVerdict(index: index, ok: true, reason: '');
  }

  static Offset _start(List<Offset> s) => s.first;
  static Offset _end(List<Offset> s) => s.last;

  static double _length(List<Offset> s) {
    var n = 0.0;
    for (var i = 1; i < s.length; i++) {
      n += (s[i] - s[i - 1]).distance;
    }
    return n;
  }

  /// 화면에 보여줄 한 줄 요약. 지적이 없으면 null.
  static String? summarize(List<StrokeVerdict> verdicts) {
    final bad = verdicts.where((v) => !v.ok).toList();
    if (bad.isEmpty) return null;
    // 같은 지적이 여러 번이면 한 번만 말한다 — 잔소리가 되면 안 읽는다.
    final seen = <String>{};
    final msgs = <String>[];
    for (final v in bad) {
      if (v.reason.isEmpty) continue;
      if (seen.add(v.reason)) msgs.add(v.reason);
    }
    if (msgs.isEmpty) return null;
    return msgs.take(2).join(' · ');
  }

  /// 두 점 사이 각도(도). 진단·테스트 보조.
  static double angleDeg(Offset a, Offset b) =>
      math.atan2(b.dy - a.dy, b.dx - a.dx) * 180 / math.pi;
}
