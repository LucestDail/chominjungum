import 'dart:convert';

import 'package:chominjungum/domain/dictation_models.dart';
import 'package:chominjungum/services/upsync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sync_protocol/sync_protocol.dart';

AttemptSubmitPayload _attempt({
  String attemptId = 'a1',
  String itemId = 'i1',
  String device = 'device-1',
}) {
  return AttemptSubmitPayload(
    attemptId: attemptId,
    itemId: itemId,
    expectedText: '안녕하세요',
    rawAnswer: '안녕하세오',
    deviceBindingId: device,
    correctCount: 4,
    totalCount: 5,
    submittedAtMs: 1756801200000,
    matches: const [
      GlyphMatchSummary(index: 0, ok: true),
      GlyphMatchSummary(index: 4, ok: false, why: '글자 불일치'),
    ],
  );
}

const _okBody = '{"sessionId":"s","accepted":1,"duplicated":0,"rejected":[],'
    '"unassignedDevices":["device-1"]}';

void main() {
  const config = UpsyncConfig(
    baseUrl: 'http://localhost:8100',
    token: 'token-abc',
    classroomId: 'classroom-1',
  );

  group('PendingSession', () {
    test('같은 기기·같은 문항의 재제출은 최신 것만 남는다', () {
      final session = PendingSession(sessionId: 's1', startedAtMs: 1);
      session.addAttempt(_attempt(attemptId: 'first'));
      session.addAttempt(_attempt(attemptId: 'second'));

      expect(session.attempts, hasLength(1));
      expect(session.attempts.single.attemptId, 'second');
    });

    test('다른 기기의 제출은 함께 쌓인다', () {
      final session = PendingSession(sessionId: 's1', startedAtMs: 1);
      session.addAttempt(_attempt(attemptId: 'a', device: 'd1'));
      session.addAttempt(_attempt(attemptId: 'b', device: 'd2'));
      expect(session.attempts, hasLength(2));
    });

    test('같은 문항은 중복 저장되지 않는다', () {
      final session = PendingSession(sessionId: 's1', startedAtMs: 1);
      final item = DictationItem.fromExpectedText('안녕하세요');
      session.addItem(item);
      session.addItem(DictationItem.fromExpectedText('안녕하세요'));
      expect(session.items, hasLength(1));
    });

    test('JSON 왕복 — 앱을 껐다 켜도 큐가 살아남는다', () {
      final session = PendingSession(sessionId: 's1', startedAtMs: 100)
        ..endedAtMs = 200
        ..addItem(DictationItem.fromExpectedText('안녕하세요'))
        ..addAttempt(_attempt());

      final restored = PendingSession.fromJson(
        jsonDecode(jsonEncode(session.toJson())) as Map<String, Object?>,
      );

      expect(restored.sessionId, 's1');
      expect(restored.endedAtMs, 200);
      expect(restored.items.single.expectedText, '안녕하세요');
      expect(restored.attempts.single.matches, hasLength(2));
    });
  });

  group('업로드', () {
    test('서버 규약대로 배치를 보낸다', () async {
      late http.Request captured;
      final service = UpsyncService(
        client: MockClient((req) async {
          captured = req;
          return http.Response(_okBody, 200, headers: {'content-type': 'application/json'});
        }),
      );

      final session = PendingSession(sessionId: 'sess-1', startedAtMs: 100)
        ..addItem(DictationItem.fromExpectedText('안녕하세요'))
        ..addAttempt(_attempt());

      final result = await service.upload(config, session);

      expect(captured.url.path, '/api/sync/sessions');
      expect(captured.headers['Authorization'], 'Bearer token-abc');

      final body = jsonDecode(captured.body) as Map<String, Object?>;
      expect(body['sessionId'], 'sess-1');
      expect(body['classroomId'], 'classroom-1');
      expect(body['source'], 'LAN');
      expect((body['items'] as List), hasLength(1));

      final attempt = (body['attempts'] as List).single as Map<String, Object?>;
      expect(attempt['attemptId'], 'a1');
      expect(attempt['deviceBindingId'], 'device-1');
      expect(attempt['matches'], hasLength(2));

      expect(result.accepted, 1);
      expect(result.unassignedDevices, ['device-1']);
    });

    test('서버 주소 끝의 슬래시를 정리한다', () async {
      late Uri url;
      final service = UpsyncService(
        client: MockClient((req) async {
          url = req.url;
          return http.Response(_okBody, 200);
        }),
      );

      await service.upload(
        const UpsyncConfig(baseUrl: 'http://localhost:8100//', token: 't', classroomId: 'c'),
        PendingSession(sessionId: 's', startedAtMs: 1),
      );

      expect(url.toString(), 'http://localhost:8100/api/sync/sessions');
    });

    test('설정이 비어 있으면 올리지 않는다', () async {
      final service = UpsyncService(client: MockClient((_) async => http.Response('', 200)));
      expect(
        () => service.upload(UpsyncConfig.empty, PendingSession(sessionId: 's', startedAtMs: 1)),
        throwsA(isA<UpsyncException>()),
      );
    });

    test('401 은 토큰 문제로 안내한다', () async {
      final service = UpsyncService(
        // 한글 본문은 바이트로 넘긴다 (http.Response 는 기본이 latin1)
        client: MockClient((_) async =>
            http.Response.bytes(utf8.encode('{"message":"로그인이 필요합니다."}'), 401)),
      );
      await expectLater(
        service.upload(config, PendingSession(sessionId: 's', startedAtMs: 1)),
        throwsA(isA<UpsyncException>().having((e) => e.message, 'message', contains('토큰'))),
      );
    });

    test('네트워크가 끊겨도 예외만 던지고 큐는 호출자가 지킨다', () async {
      final service = UpsyncService(
        client: MockClient((_) async => throw const SocketExceptionStub()),
      );
      await expectLater(
        service.upload(config, PendingSession(sessionId: 's', startedAtMs: 1)),
        throwsA(isA<UpsyncException>().having((e) => e.message, 'message', contains('연결'))),
      );
    });
  });
}

/// dart:io 의존 없이 네트워크 실패를 흉내 낸다.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();

  @override
  String toString() => 'connection failed';
}
