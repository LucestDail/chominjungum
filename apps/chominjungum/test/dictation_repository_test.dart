import 'dart:convert';
import 'dart:io';

import 'package:chominjungum/domain/dictation_models.dart';
import 'package:chominjungum/services/dictation_repository.dart';
import 'package:chominjungum/services/local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangul_core/hangul_core.dart';

void main() {
  late Directory dir;
  const repo = DictationRepository();

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('cjm_repo_test');
    LocalStore.initAt(dir.path);
    await LocalStore.open();
  });

  tearDown(() async {
    await LocalStore.deleteAllFromDisk();
    await LocalStore.closeAll();
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  DictationPackage packageOf(List<String> words) {
    return DictationPackage(
      version: DictationPackage.currentVersion,
      items: [for (final w in words) DictationItem.fromExpectedText(w)],
    );
  }

  DictationAttempt attemptOf({
    required String id,
    required String itemId,
    String device = 'dev-1',
    String expected = '학교에 갔다.',
    String answer = '학교에 갔다.',
    int createdAtMs = 1000,
  }) {
    return DictationAttempt.fromScore(
      id: id,
      itemId: itemId,
      deviceBindingId: device,
      rawAnswer: answer,
      inputKind: AttemptInputKind.keyboard,
      createdAtMs: createdAtMs,
      score: DictationCompare.score(expected: expected, actual: answer),
    );
  }

  group('문제', () {
    test('수신한 묶음을 저장하고 다시 읽는다', () async {
      await repo.savePackage(packageOf(['학교에 갔다.', '값을 읽고 답을 썼다']));

      final loaded = repo.loadPackage();
      expect(loaded, isNotNull);
      expect(loaded!.items.length, 2);
      expect(
        loaded.items.map((e) => e.expectedText).toSet(),
        {'학교에 갔다.', '값을 읽고 답을 썼다'},
      );
    });

    test('분해 결과(glyphsJson)도 함께 살아남는다', () async {
      await repo.savePackage(packageOf(['값']));

      final item = repo.loadItems().single;
      final glyphs = HangulUtil.glyphsFromAddWordResponse(item.expectedGlyphsJson);
      expect(glyphs.length, 1);
      expect(glyphs.single.jongsung, isNotNull); // 받침 ㅄ 이 보존됐다
    });

    test('저장된 문제가 없으면 null — 호출한 쪽이 번들로 넘어갈 수 있게', () {
      expect(repo.loadPackage(), isNull);
      expect(repo.loadItems(), isEmpty);
    });

    test('같은 문제를 다시 받으면 덮어쓴다(중복 안 쌓임)', () async {
      await repo.savePackage(packageOf(['학교에 갔다.']));
      await repo.savePackage(packageOf(['학교에 갔다.']));

      expect(repo.loadItems().length, 1);
    });
  });

  group('답안', () {
    test('채점 이력이 재시작 후에도 남는다', () async {
      await repo.saveAttempt(attemptOf(id: 'a1', itemId: 'i1', answer: '학교에 갓다.'));

      await LocalStore.closeAll();
      LocalStore.initAt(dir.path);
      await LocalStore.open();

      final found = repo.attempt('a1');
      expect(found, isNotNull);
      expect(found!.rawAnswer, '학교에 갓다.');
      expect(found.correctCount, 6);
      expect(found.totalCount, 7);
      expect(found.scorePercent, 86);
    });

    test('글자별 정오가 보존된다 — 결과 화면의 오답 표시 원천', () async {
      await repo.saveAttempt(attemptOf(id: 'a1', itemId: 'i1', answer: '학교에 갓다.'));

      final matches = jsonDecode(repo.attempt('a1')!.matchesJson!) as List<dynamic>;
      expect(matches.length, 7);
      final wrong = matches.where((m) => (m as Map)['ok'] == false).toList();
      expect(wrong.length, 1);
      expect((wrong.single as Map)['i'], 4); // '갔' 자리
    });

    test('허브에 못 보낸 답안은 미제출로 남는다', () async {
      await repo.saveAttempt(attemptOf(id: 'a1', itemId: 'i1'));

      expect(repo.attempt('a1')!.isSubmitted, isFalse);
      expect(repo.pendingSubmissions().map((e) => e.id), ['a1']);
    });

    test('제출이 성공하면 그 시각이 남고 미제출 목록에서 빠진다', () async {
      await repo.saveAttempt(attemptOf(id: 'a1', itemId: 'i1'));
      await repo.markSubmitted('a1', 5555);

      final found = repo.attempt('a1')!;
      expect(found.isSubmitted, isTrue);
      expect(found.submittedAtMs, 5555);
      expect(repo.pendingSubmissions(), isEmpty);
      // 제출 표시가 채점 내용을 덮지 않는다
      expect(found.correctCount, 7);
    });

    test('없는 답안에 제출 표시를 해도 조용히 넘어간다', () async {
      await repo.markSubmitted('nope', 1);
      expect(repo.attempt('nope'), isNull);
    });

    test('기기별로 걸러낸다 — 교사 기기엔 여러 학생 제출이 섞인다', () async {
      await repo.saveAttempt(attemptOf(id: 'a1', itemId: 'i1', device: 'dev-1'));
      await repo.saveAttempt(attemptOf(id: 'a2', itemId: 'i1', device: 'dev-2'));

      expect(repo.attempts(deviceBindingId: 'dev-1').map((e) => e.id), ['a1']);
      expect(repo.attempts().length, 2);
    });

    test('문항별로 걸러낸다', () async {
      await repo.saveAttempt(attemptOf(id: 'a1', itemId: 'i1'));
      await repo.saveAttempt(attemptOf(id: 'a2', itemId: 'i2'));

      expect(repo.attempts(itemId: 'i2').map((e) => e.id), ['a2']);
    });

    test('목록은 최신순, 미제출 목록은 보낼 순서(오래된 것부터)', () async {
      await repo.saveAttempt(attemptOf(id: 'old', itemId: 'i1', createdAtMs: 100));
      await repo.saveAttempt(attemptOf(id: 'new', itemId: 'i1', createdAtMs: 900));

      expect(repo.attempts().map((e) => e.id), ['new', 'old']);
      expect(repo.pendingSubmissions().map((e) => e.id), ['old', 'new']);
    });

    test('알 수 없는 inputKind 가 와도 읽기가 실패하지 않는다', () async {
      await LocalStore.put(LocalStore.attemptsBox, 'a1', {
        'id': 'a1',
        'itemId': 'i1',
        'deviceBindingId': 'dev-1',
        'rawAnswer': '값',
        'inputKind': 'future_kind_we_do_not_know',
        'createdAtMs': 1,
      });

      expect(repo.attempt('a1')!.inputKind, AttemptInputKind.keyboard);
    });

    test('필수 필드가 빠진 기록은 목록에서 건너뛴다', () async {
      await repo.saveAttempt(attemptOf(id: 'good', itemId: 'i1'));
      await LocalStore.put(LocalStore.attemptsBox, 'bad', {'id': 'bad'});

      expect(repo.attempts().map((e) => e.id), ['good']);
    });
  });
}
