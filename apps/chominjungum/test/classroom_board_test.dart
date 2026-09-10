import 'package:chominjungum/services/classroom_board.dart';
import 'package:chominjungum/services/dictation_composer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_protocol/sync_protocol.dart';

/// 교실 현황판 — 서버 없이 교사 기기가 본 것만으로 명단·진도·통계를 만든다.
void main() {
  final items = DictationComposer.composeAll('나비\n구름\n바다');

  AttemptSubmitPayload sub(
    String device,
    int itemIndex, {
    String? name,
    int correct = 2,
    int total = 2,
    int at = 0,
  }) =>
      AttemptSubmitPayload(
        attemptId: '$device-$itemIndex-$at',
        itemId: items[itemIndex].id,
        expectedText: items[itemIndex].expectedText,
        rawAnswer: items[itemIndex].expectedText,
        deviceBindingId: device,
        studentName: name,
        correctCount: correct,
        totalCount: total,
        submittedAtMs: at,
        inputKind: 'keyboard',
      );

  test('제출이 없어도 접속한 학생은 명단에 뜬다', () {
    final b = ClassroomBoard.of(
      attempts: const [],
      items: items,
      connectedDeviceIds: {'dev-a', 'dev-b'},
    );
    expect(b.students, hasLength(2));
    expect(b.students.every((s) => !s.hasStarted), isTrue,
        reason: '한 문제도 안 푼 학생이 교사가 가장 알고 싶은 것이다');
    expect(b.allDone, isFalse);
  });

  test('진도와 정답률', () {
    final b = ClassroomBoard.of(
      attempts: [
        sub('dev-a', 0, correct: 2),
        sub('dev-a', 1, correct: 1),
      ],
      items: items,
      connectedDeviceIds: {'dev-a'},
    );
    final s = b.students.single;
    expect(s.submitted, 2);
    expect(s.total, 3);
    expect(s.progress, closeTo(2 / 3, 1e-9));
    expect(s.accuracy, closeTo(3 / 4, 1e-9));
    expect(s.isDone, isFalse);
  });

  test('같은 문항 재제출은 최신 것만 센다 — 새 제출이 아니다', () {
    final b = ClassroomBoard.of(
      attempts: [
        sub('dev-a', 0, correct: 0, at: 1),
        sub('dev-a', 0, correct: 2, at: 2), // 다시 풀어 맞혔다
      ],
      items: items,
    );
    final s = b.students.single;
    expect(s.submitted, 1, reason: '두 번 냈다고 두 문항이 되면 안 된다');
    expect(s.accuracy, 1.0, reason: '최신 결과를 쓴다');
  });

  test('덜 낸 학생이 위로 온다 — 교사가 도와줄 순서', () {
    final b = ClassroomBoard.of(
      attempts: [
        for (var i = 0; i < 3; i++) sub('fast', i),
        sub('slow', 0),
      ],
      items: items,
      connectedDeviceIds: {'fast', 'slow', 'idle'},
    );
    expect(b.students.map((s) => s.deviceBindingId).toList(),
        ['idle', 'slow', 'fast']);
    expect(b.doneCount, 1);
  });

  group('이름', () {
    test('학생이 적은 이름을 쓴다', () {
      final b = ClassroomBoard.of(
        attempts: [sub('dev-a', 0, name: '민준')],
        items: items,
      );
      expect(b.students.single.displayName, '민준');
    });

    test('도중에 바꿔 적으면 최근 것을 쓴다', () {
      final b = ClassroomBoard.of(
        attempts: [
          sub('dev-a', 0, name: '민', at: 1),
          sub('dev-a', 1, name: '민준', at: 2),
        ],
        items: items,
      );
      expect(b.students.single.displayName, '민준');
    });

    test('이름이 없으면 기기 ID 축약', () {
      final b = ClassroomBoard.of(
        attempts: [sub('a3f2beef', 0)],
        items: items,
      );
      expect(b.students.single.displayName, '학생 a3f2');
    });
  });

  test('학급 평균과 전원 완료 판정', () {
    final b = ClassroomBoard.of(
      attempts: [
        for (var i = 0; i < 3; i++) sub('a', i, correct: 2),
        for (var i = 0; i < 3; i++) sub('b', i, correct: 1),
      ],
      items: items,
      connectedDeviceIds: {'a', 'b'},
    );
    expect(b.allDone, isTrue);
    expect(b.averageAccuracy, closeTo(9 / 12, 1e-9));
    expect(b.submittedCount, 6);
  });

  test('학급 취약 자모도 함께 나온다', () {
    // 세 학생이 같은 문항을 틀리면 그 자모가 학급 약점이다.
    final attempts = [
      for (final d in ['a', 'b', 'c'])
        AttemptSubmitPayload(
          attemptId: '$d-0',
          itemId: items[0].id,
          expectedText: '나비',
          rawAnswer: '나비',
          deviceBindingId: d,
          correctCount: 0,
          totalCount: 2,
          submittedAtMs: 0,
          inputKind: 'keyboard',
          matches: const [
            GlyphMatchSummary(index: 0, ok: false),
            GlyphMatchSummary(index: 1, ok: true),
          ],
        ),
    ];
    final b = ClassroomBoard.of(attempts: attempts, items: items);
    expect(b.weakness.gradedAttempts, 3);
    expect(b.weakness.jamo, isNotEmpty);
  });

  test('아무도 없으면 비어 있다', () {
    final b = ClassroomBoard.of(attempts: const [], items: items);
    expect(b.isEmpty, isTrue);
    expect(b.allDone, isFalse, reason: '아무도 없는데 "전원 완료"면 안 된다');
    expect(b.averageAccuracy, 0);
  });
}
