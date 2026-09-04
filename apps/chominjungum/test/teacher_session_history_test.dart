import 'dart:convert';
import 'dart:io';

import 'package:chominjungum/domain/dictation_models.dart';
import 'package:chominjungum/services/dictation_repository.dart';
import 'package:chominjungum/services/local_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// 교사 기기의 수업 이력.
///
/// 업싱크 큐는 업로드가 성공하면 비워진다(`upsync_service`). 그래서 큐만으로는
/// "지난 수업"이 기기에 남지 않는다 — 올리면 오히려 사라진다.
/// 이 이력은 업로드 여부와 무관하게 남아야 한다.
void main() {
  late Directory dir;
  const repo = DictationRepository();

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('cjm_session_test');
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

  test('수업을 열고 문제·답안을 묶어 남긴다', () async {
    await repo.saveSession(const TeacherSession(sessionId: 's1', startedAtMs: 100));
    await repo.updateSession('s1', (s) => s.withItem('i1'));
    await repo.updateSession('s1', (s) => s.withAttempt('a1'));

    final found = repo.session('s1')!;
    expect(found.itemIds, ['i1']);
    expect(found.attemptIds, ['a1']);
    expect(found.endedAtMs, isNull);
    expect(found.isUploaded, isFalse);
  });

  test('같은 문제를 다시 내도 목록이 부풀지 않는다', () async {
    await repo.saveSession(const TeacherSession(sessionId: 's1', startedAtMs: 100));
    await repo.updateSession('s1', (s) => s.withItem('i1'));
    await repo.updateSession('s1', (s) => s.withItem('i1'));
    await repo.updateSession('s1', (s) => s.withAttempt('a1'));
    await repo.updateSession('s1', (s) => s.withAttempt('a1'));

    final found = repo.session('s1')!;
    expect(found.itemIds, ['i1']);
    expect(found.attemptIds, ['a1']);
  });

  test('★업로드해도 이력은 남는다 (업싱크 큐와 다른 목적)', () async {
    await repo.saveSession(const TeacherSession(sessionId: 's1', startedAtMs: 100));
    await repo.updateSession('s1', (s) => s.withAttempt('a1'));
    await repo.updateSession('s1', (s) => s.copyWith(uploadedAtMs: 777));

    final found = repo.session('s1')!;
    expect(found.isUploaded, isTrue);
    expect(found.uploadedAtMs, 777);
    // 올렸다고 내용이 지워지지 않는다
    expect(found.attemptIds, ['a1']);
  });

  test('앱을 다시 켜도 지난 수업이 보인다', () async {
    await repo.saveSession(const TeacherSession(sessionId: 's1', startedAtMs: 100));
    await repo.updateSession('s1', (s) => s.copyWith(endedAtMs: 200));

    await LocalStore.closeAll();
    LocalStore.initAt(dir.path);
    await LocalStore.open();

    final found = repo.session('s1')!;
    expect(found.startedAtMs, 100);
    expect(found.endedAtMs, 200);
  });

  test('목록은 최근 수업부터', () async {
    await repo.saveSession(const TeacherSession(sessionId: 'old', startedAtMs: 100));
    await repo.saveSession(const TeacherSession(sessionId: 'new', startedAtMs: 900));

    expect(repo.sessions().map((e) => e.sessionId), ['new', 'old']);
  });

  test('없는 세션을 갱신해도 조용히 넘어간다', () async {
    await repo.updateSession('nope', (s) => s.withItem('i1'));
    expect(repo.session('nope'), isNull);
  });

  group('받은 답안', () {
    test('교사 기기에서는 수신 자체가 제출 완료다', () async {
      final saved = await repo.saveReceivedAttempt(
        attemptId: 'a1',
        itemId: 'i1',
        deviceBindingId: 'student-1',
        rawAnswer: '학교에 갓다.',
        correctCount: 6,
        totalCount: 7,
        submittedAtMs: 5000,
        inputKind: 'keyboard',
      );

      expect(saved.isSubmitted, isTrue);
      expect(saved.submittedAtMs, 5000);
      expect(repo.pendingSubmissions(), isEmpty);
      expect(repo.attempt('a1')!.scorePercent, 86);
    });

    test('글자별 정오를 함께 남긴다 (v2 payload)', () async {
      await repo.saveReceivedAttempt(
        attemptId: 'a1',
        itemId: 'i1',
        deviceBindingId: 'student-1',
        rawAnswer: '값',
        correctCount: 0,
        totalCount: 1,
        submittedAtMs: 1,
        matchesJson: jsonEncode([
          {'i': 0, 'ok': false, 'why': 'jong'},
        ]),
      );

      final matches = jsonDecode(repo.attempt('a1')!.matchesJson!) as List<dynamic>;
      expect((matches.single as Map)['why'], 'jong');
    });

    test('matches 없는 옛 payload 도 받는다 (하위호환)', () async {
      final saved = await repo.saveReceivedAttempt(
        attemptId: 'a1',
        itemId: 'i1',
        deviceBindingId: 'student-1',
        rawAnswer: '값',
        correctCount: 1,
        totalCount: 1,
        submittedAtMs: 1,
      );
      expect(saved.matchesJson, isNull);
      expect(repo.attempt('a1'), isNotNull);
    });

    test('여러 학생 제출이 한 Box 에 섞여도 기기별로 갈린다', () async {
      for (final d in ['student-1', 'student-2']) {
        await repo.saveReceivedAttempt(
          attemptId: 'a-$d',
          itemId: 'i1',
          deviceBindingId: d,
          rawAnswer: '값',
          correctCount: 1,
          totalCount: 1,
          submittedAtMs: 1,
        );
      }

      expect(repo.attempts().length, 2);
      expect(repo.attempts(deviceBindingId: 'student-2').single.id, 'a-student-2');
    });
  });
}
