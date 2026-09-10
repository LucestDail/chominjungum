import 'dart:convert';

import 'package:chominjungum/domain/dictation_models.dart';
import 'package:chominjungum/services/dictation_composer.dart';
import 'package:chominjungum/services/mistake_analysis.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangul_core/hangul_core.dart';

/// 오답 노트 — 쌓인 답안에서 취약 자모·음절을 뽑는다.
///
/// ⚠️앱 채점은 **음절 단위**라 "종성 ㅆ 를 틀렸다"고 단정할 수 없다. 틀린 글자에
/// 들어 있던 자모에 **책임을 나눠 싣는 근사**이고, 그 성질까지 테스트로 박아 둔다.
void main() {
  /// 정답 [text] 에 대해 [wrongIndexes] 를 틀린 답안을 만든다.
  DictationAttempt attemptFor(
    DictationItem item, {
    required Set<int> wrongIndexes,
    String? answer,
    int seq = 0,
  }) {
    final n = HangulUtil.hangulSplit(item.expectedText).length;
    return DictationAttempt(
      id: 'a$seq',
      itemId: item.id,
      deviceBindingId: 'dev',
      rawAnswer: answer ?? item.expectedText,
      inputKind: AttemptInputKind.keyboard,
      createdAtMs: seq,
      correctCount: n - wrongIndexes.length,
      totalCount: n,
      matchesJson: jsonEncode([
        for (var i = 0; i < n; i++) {'i': i, 'ok': !wrongIndexes.contains(i)},
      ]),
    );
  }

  test('이력이 없으면 비어 있다', () {
    final r = MistakeAnalysis.of(attempts: const [], items: const []);
    expect(r.isEmpty, isTrue);
    expect(r.jamo, isEmpty);
  });

  test('문항을 못 찾은 답안은 건너뛴다 — 정답을 모르면 분석할 수 없다', () {
    final item = DictationComposer.compose('나비');
    final orphan = attemptFor(item, wrongIndexes: {0});
    final r = MistakeAnalysis.of(attempts: [orphan], items: const []);
    expect(r.gradedAttempts, 0);
  });

  test('틀린 글자의 자모에 책임이 실린다', () {
    // "값" = 초성 ㄱ(4352) · 중성 ㅏ(4449) · 종성 ㅄ(4537)
    final item = DictationComposer.compose('값');
    final attempts = [
      for (var i = 0; i < 4; i++)
        attemptFor(item, wrongIndexes: {0}, seq: i, answer: '갑'),
    ];

    final r = MistakeAnalysis.of(attempts: attempts, items: [item]);
    expect(r.gradedAttempts, 4);

    final codes = {for (final w in r.jamo) w.code};
    expect(codes, contains(4537), reason: '겹받침 ㅄ 이 취약으로 잡혀야 한다');
    expect(codes, contains(4352));

    final ss = r.jamo.firstWhere((w) => w.code == 4537);
    expect(ss.wrong, 4);
    expect(ss.total, 4);
    expect(ss.errorRate, 1.0);
    expect(ss.letter, 'ㅄ', reason: '결합 자모가 아니라 호환 자모로 보여야 한다');
  });

  test('맞은 글자의 자모는 분모만 늘어 오답률이 낮아진다', () {
    final item = DictationComposer.compose('가가가');
    final attempts = [
      // 3글자 중 첫 글자만 틀린 답안 3회 → ㄱ·ㅏ 는 9번 나오고 3번 틀림
      for (var i = 0; i < 3; i++) attemptFor(item, wrongIndexes: {0}, seq: i),
    ];
    final r = MistakeAnalysis.of(attempts: attempts, items: [item]);
    final g = r.jamo.firstWhere((w) => w.code == 4352);
    expect(g.total, 9);
    expect(g.wrong, 3);
    expect(g.errorRate, closeTo(1 / 3, 1e-9));
  });

  test('표본이 적으면 약점이라 하지 않는다', () {
    final item = DictationComposer.compose('값');
    // 2회뿐 — minSamples(3) 미만
    final attempts = [
      for (var i = 0; i < 2; i++) attemptFor(item, wrongIndexes: {0}, seq: i),
    ];
    final r = MistakeAnalysis.of(attempts: attempts, items: [item]);
    expect(r.jamo, isEmpty, reason: '한두 번 틀린 것을 약점이라 하면 안 된다');
    expect(r.gradedAttempts, 2, reason: '표본 수 자체는 세어 화면에 밝힐 수 있어야 한다');
  });

  test('음절 오답과 "대신 쓴 글자"', () {
    final item = DictationComposer.compose('값');
    final attempts = [
      attemptFor(item, wrongIndexes: {0}, answer: '갑', seq: 0),
      attemptFor(item, wrongIndexes: {0}, answer: '갑', seq: 1),
      attemptFor(item, wrongIndexes: {0}, answer: '값', seq: 2),
    ];
    final r = MistakeAnalysis.of(attempts: attempts, items: [item]);
    final s = r.syllables.single;
    expect(s.syllable, '값');
    expect(s.wrong, 3);
    expect(s.wroteInstead.first, '갑', reason: '가장 많이 쓴 오답이 앞에 온다');
  });

  test('공백·특수문자는 세지 않는다', () {
    final item = DictationComposer.compose('가 나');
    final attempts = [
      for (var i = 0; i < 3; i++)
        attemptFor(item, wrongIndexes: {0, 1, 2}, seq: i),
    ];
    final r = MistakeAnalysis.of(attempts: attempts, items: [item]);
    expect(r.syllables.map((s) => s.syllable), isNot(contains(' ')));
  });

  test('손상된 이력 하나가 전체를 막지 않는다', () {
    final item = DictationComposer.compose('값');
    final broken = DictationAttempt(
      id: 'x',
      itemId: item.id,
      deviceBindingId: 'dev',
      rawAnswer: '값',
      inputKind: AttemptInputKind.keyboard,
      createdAtMs: 0,
      matchesJson: '{{{ 깨진 JSON',
    );
    final good = [
      for (var i = 0; i < 3; i++) attemptFor(item, wrongIndexes: {0}, seq: i),
    ];
    final r = MistakeAnalysis.of(attempts: [broken, ...good], items: [item]);
    expect(r.gradedAttempts, 3);
    expect(r.jamo, isNotEmpty);
  });

  group('오답 노트 → 가리기 학습지', () {
    test('취약 자모가 그대로 가리기 규칙이 된다', () {
      final item = DictationComposer.compose('값');
      final attempts = [
        for (var i = 0; i < 3; i++) attemptFor(item, wrongIndexes: {0}, seq: i),
      ];
      final rule = MistakeAnalysis.of(attempts: attempts, items: [item])
          .toHideRule();

      expect(rule.hasEffect, isTrue);
      // 같은 종류로 모드가 고정되고, 그 종류의 코드만 담긴다.
      expect(rule.codes.every((c) => isHidableInMode(c, rule.mode)), isTrue,
          reason: '모드와 안 맞는 코드가 섞이면 아무것도 안 가려진다');
    });

    test('약점이 없으면 빈 규칙', () {
      expect(
        const MistakeAnalysis(
          jamo: [],
          syllables: [],
          gradedAttempts: 0,
          gradedSyllables: 0,
        ).toHideRule().hasEffect,
        isFalse,
      );
    });
  });
}
