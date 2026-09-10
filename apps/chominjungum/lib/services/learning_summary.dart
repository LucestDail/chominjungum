import '../domain/dictation_models.dart';

/// 한 회차(하루) 요약.
class DailySummary {
  const DailySummary({
    required this.dayKey,
    required this.attempts,
    required this.correct,
    required this.graded,
  });

  /// `2026-09-10`. 정렬·표시에 그대로 쓴다.
  final String dayKey;
  final int attempts;
  final int correct;
  final int graded;

  double get accuracy => graded == 0 ? 0 : correct / graded;
}

/// 학생 본인의 **학습 요약** — 기기에 쌓인 이력만으로.
///
/// ## 무엇을 위한 화면인가
///
/// 오답 노트가 "무엇을 틀렸나"라면 이건 "얼마나 했고 나아지고 있나"다.
/// 초등 저학년에게는 **꾸준히 했다는 사실 자체**가 동기가 된다.
///
/// ⚠️**등수·비교를 만들지 않는다.** 이 앱은 학생 기기에 남의 답안을 두지 않고,
/// 그럴 수 있어도 하지 않는다 — 받아쓰기에서 아이를 줄 세우는 것은 목적이 아니다.
class LearningSummary {
  const LearningSummary({
    required this.totalAttempts,
    required this.gradedAttempts,
    required this.correct,
    required this.graded,
    required this.days,
    required this.streakDays,
    required this.recentAccuracy,
    required this.earlierAccuracy,
  });

  final int totalAttempts;
  final int gradedAttempts;
  final int correct;
  final int graded;

  /// 최근 순(오늘이 먼저).
  final List<DailySummary> days;

  /// 오늘부터 거슬러 **연속으로** 푼 날수. 하루 걸러도 끊긴다.
  final int streakDays;

  /// 최근 절반 / 이전 절반의 정답률. 둘을 비교해 "나아졌다"를 말한다.
  final double recentAccuracy;
  final double earlierAccuracy;

  bool get isEmpty => gradedAttempts == 0;

  double get accuracy => graded == 0 ? 0 : correct / graded;

  /// 나아지고 있는가. **표본이 적으면 판단하지 않는다**(null) —
  /// 두세 문제로 "늘었다/줄었다"를 말하면 거짓말이 된다.
  bool? get isImproving {
    if (gradedAttempts < minAttemptsForTrend) return null;
    const noise = 0.05; // 5%p 안쪽은 그냥 흔들림으로 본다
    if ((recentAccuracy - earlierAccuracy).abs() < noise) return null;
    return recentAccuracy > earlierAccuracy;
  }

  /// 추세를 말하려면 이만큼은 있어야 한다.
  static const minAttemptsForTrend = 6;

  static LearningSummary of(
    List<DictationAttempt> attempts, {
    required DateTime now,
  }) {
    // 채점된 것만 본다 — 풀다 만 것은 학습 기록이 아니다.
    final graded = [
      for (final a in attempts)
        if (a.totalCount != null && a.totalCount! > 0) a,
    ]..sort((a, b) => a.createdAtMs.compareTo(b.createdAtMs));

    if (graded.isEmpty) {
      return LearningSummary(
        totalAttempts: attempts.length,
        gradedAttempts: 0,
        correct: 0,
        graded: 0,
        days: const [],
        streakDays: 0,
        recentAccuracy: 0,
        earlierAccuracy: 0,
      );
    }

    final byDay = <String, List<DictationAttempt>>{};
    var correct = 0;
    var total = 0;
    for (final a in graded) {
      correct += a.correctCount ?? 0;
      total += a.totalCount ?? 0;
      byDay.putIfAbsent(_dayKey(a.createdAtMs), () => []).add(a);
    }

    final days = <DailySummary>[
      for (final e in byDay.entries)
        DailySummary(
          dayKey: e.key,
          attempts: e.value.length,
          correct: e.value.fold(0, (n, a) => n + (a.correctCount ?? 0)),
          graded: e.value.fold(0, (n, a) => n + (a.totalCount ?? 0)),
        ),
    ]..sort((a, b) => b.dayKey.compareTo(a.dayKey));

    // 앞뒤 절반의 정답률 — 홀수면 뒤쪽(최근)에 한 개 더 준다.
    final half = graded.length ~/ 2;
    double rate(Iterable<DictationAttempt> xs) {
      var c = 0, t = 0;
      for (final a in xs) {
        c += a.correctCount ?? 0;
        t += a.totalCount ?? 0;
      }
      return t == 0 ? 0 : c / t;
    }

    return LearningSummary(
      totalAttempts: attempts.length,
      gradedAttempts: graded.length,
      correct: correct,
      graded: total,
      days: days,
      streakDays: _streak(byDay.keys.toSet(), now),
      earlierAccuracy: rate(graded.take(half)),
      recentAccuracy: rate(graded.skip(half)),
    );
  }

  /// 오늘(또는 어제)부터 거슬러 연속으로 푼 날수.
  ///
  /// ⚠️오늘 아직 안 풀었어도 **어제까지 이어졌으면 끊긴 것이 아니다** —
  /// 아침에 앱을 열었다고 "연속 0일"이라 하면 억울하다.
  static int _streak(Set<String> dayKeys, DateTime now) {
    if (dayKeys.isEmpty) return 0;
    var cursor = DateTime(now.year, now.month, now.day);
    if (!dayKeys.contains(_dayKeyOf(cursor))) {
      cursor = cursor.subtract(const Duration(days: 1));
      if (!dayKeys.contains(_dayKeyOf(cursor))) return 0;
    }
    var n = 0;
    while (dayKeys.contains(_dayKeyOf(cursor))) {
      n++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return n;
  }

  static String _dayKey(int ms) =>
      _dayKeyOf(DateTime.fromMillisecondsSinceEpoch(ms));

  static String _dayKeyOf(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
