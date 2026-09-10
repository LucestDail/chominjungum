import 'package:chominjungum/domain/dictation_models.dart';
import 'package:chominjungum/services/learning_summary.dart';
import 'package:flutter_test/flutter_test.dart';

/// 학습 요약 — "얼마나 했고 나아지고 있나".
///
/// ⚠️표본이 적을 때 추세를 말하지 않는 것이 핵심이다. 두세 문제로
/// "늘었다/줄었다"를 말하면 거짓말이 된다.
void main() {
  final now = DateTime(2026, 9, 10, 12);

  DictationAttempt at(
    DateTime when, {
    int correct = 2,
    int total = 2,
    String id = 'a',
  }) =>
      DictationAttempt(
        id: '$id-${when.millisecondsSinceEpoch}',
        itemId: 'i',
        deviceBindingId: 'dev',
        rawAnswer: '나비',
        inputKind: AttemptInputKind.keyboard,
        createdAtMs: when.millisecondsSinceEpoch,
        correctCount: correct,
        totalCount: total,
      );

  test('이력이 없으면 비어 있다', () {
    final s = LearningSummary.of(const [], now: now);
    expect(s.isEmpty, isTrue);
    expect(s.streakDays, 0);
    expect(s.isImproving, isNull);
  });

  test('채점 안 된 답안은 학습 기록이 아니다', () {
    final unGraded = DictationAttempt(
      id: 'x',
      itemId: 'i',
      deviceBindingId: 'dev',
      rawAnswer: '',
      inputKind: AttemptInputKind.keyboard,
      createdAtMs: now.millisecondsSinceEpoch,
    );
    final s = LearningSummary.of([unGraded], now: now);
    expect(s.totalAttempts, 1);
    expect(s.gradedAttempts, 0);
    expect(s.isEmpty, isTrue);
  });

  test('날짜별로 묶고 최근이 먼저', () {
    final s = LearningSummary.of([
      at(DateTime(2026, 9, 8)),
      at(DateTime(2026, 9, 10), id: 'b'),
      at(DateTime(2026, 9, 10, 13), id: 'c'),
    ], now: now);
    expect(s.days.first.dayKey, '2026-09-10');
    expect(s.days.first.attempts, 2);
    expect(s.days.last.dayKey, '2026-09-08');
  });

  group('연속 일수', () {
    test('오늘부터 사흘 연속', () {
      final s = LearningSummary.of([
        at(DateTime(2026, 9, 10)),
        at(DateTime(2026, 9, 9), id: 'b'),
        at(DateTime(2026, 9, 8), id: 'c'),
      ], now: now);
      expect(s.streakDays, 3);
    });

    test('⚠️오늘 아직 안 풀었어도 어제까지 이어졌으면 끊긴 게 아니다', () {
      final s = LearningSummary.of([
        at(DateTime(2026, 9, 9)),
        at(DateTime(2026, 9, 8), id: 'b'),
      ], now: now);
      expect(s.streakDays, 2, reason: '아침에 앱을 열었다고 연속 0일이면 억울하다');
    });

    test('하루 걸렀으면 끊긴다', () {
      final s = LearningSummary.of([
        at(DateTime(2026, 9, 10)),
        at(DateTime(2026, 9, 7), id: 'b'),
      ], now: now);
      expect(s.streakDays, 1);
    });
  });

  group('나아지고 있는가', () {
    test('🔴표본이 적으면 판단하지 않는다', () {
      final s = LearningSummary.of([
        at(DateTime(2026, 9, 9), correct: 0),
        at(DateTime(2026, 9, 10), correct: 2, id: 'b'),
      ], now: now);
      expect(s.isImproving, isNull, reason: '두 문제로 "늘었다"를 말하면 거짓말이다');
    });

    test('표본이 쌓이고 뚜렷하게 올랐으면 참', () {
      final s = LearningSummary.of([
        for (var i = 0; i < 4; i++)
          at(DateTime(2026, 9, 8, i), correct: 0, id: 'old$i'),
        for (var i = 0; i < 4; i++)
          at(DateTime(2026, 9, 10, i), correct: 2, id: 'new$i'),
      ], now: now);
      expect(s.isImproving, isTrue);
      expect(s.recentAccuracy, 1.0);
      expect(s.earlierAccuracy, 0.0);
    });

    test('차이가 미미하면 판단하지 않는다 — 흔들림이다', () {
      final s = LearningSummary.of([
        for (var i = 0; i < 5; i++)
          at(DateTime(2026, 9, 9, i), correct: 1, total: 2, id: 'o$i'),
        for (var i = 0; i < 5; i++)
          at(DateTime(2026, 9, 10, i), correct: 1, total: 2, id: 'n$i'),
      ], now: now);
      expect(s.isImproving, isNull);
    });
  });

  test('전체 정답률', () {
    final s = LearningSummary.of([
      at(DateTime(2026, 9, 10), correct: 1, total: 2),
      at(DateTime(2026, 9, 10, 1), correct: 2, total: 2, id: 'b'),
    ], now: now);
    expect(s.accuracy, closeTo(3 / 4, 1e-9));
  });
}
