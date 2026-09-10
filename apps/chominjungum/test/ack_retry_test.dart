import 'dart:convert';
import 'dart:io';

import 'package:chominjungum/services/local_hub_service.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:sync_protocol/sync_protocol.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// 제출 회신(ACK)과 재전송.
///
/// 소켓에 밀어 넣는 것과 상대가 받는 것은 다르다. 그전에는 학생이 밀어 넣기만
/// 하고 성공했다고 여겨서, 끊기는 중이면 **제출이 조용히 사라지고** 학생 화면만
/// "제출됨"이 됐다. 교실에서는 알아채기 어렵다.
void main() {
  late SecretKey key;
  const sessionId = 'ack-test';

  setUp(() async {
    key = await SyncCrypto.newSessionKey();
  });

  Future<AttemptSubmitPayload> submitPayload(String attemptId) async =>
      AttemptSubmitPayload(
        attemptId: attemptId,
        itemId: 'i1',
        expectedText: '나비',
        rawAnswer: '나비',
        deviceBindingId: 'dev',
        correctCount: 2,
        totalCount: 2,
        submittedAtMs: 0,
        inputKind: 'keyboard',
      );

  testWidgets('허브가 회신하면 제출이 성공으로 끝난다', (tester) async {
    late bool ok;
    var receivedByHub = 0;

    await tester.runAsync(() async {
      final hub = LocalHubService(
        sessionId: sessionId,
        sessionKey: key,
        port: 0,
        onAttempt: (_) => receivedByHub++,
      );
      await hub.start();

      final client = await StudentHubClient.connect(
        wsUrl: 'ws://127.0.0.1:${hub.boundPort}/',
        sessionKey: key,
        sessionId: sessionId,
        onMessage: (_, __) {},
      );

      final p = await submitPayload('a1');
      ok = await client.sendWithAck(
        type: SyncMessageTypes.attemptSubmit,
        plainBytes: utf8.encode(p.encode()),
        attemptId: 'a1',
      );

      await client.close();
      await hub.stop();
    });

    expect(ok, isTrue, reason: '회신을 받아야 제출이 끝난 것이다');
    expect(receivedByHub, 1, reason: '회신을 받았으면 재전송하지 않는다');
  });

  testWidgets('🔴회신이 없으면 다시 보내고, 끝내 없으면 실패로 알린다', (tester) async {
    late bool ok;
    var attemptsSeen = 0;

    await tester.runAsync(() async {
      // 회신을 하지 않는 서버 — 답안은 받지만 ack 를 안 준다.
      // (끊기는 중이거나 잠깐 멈춘 교사 기기)
      final server = await shelf_io.serve(
        webSocketHandler((WebSocketChannel ch) {
          ch.stream.listen((_) => attemptsSeen++);
        }),
        InternetAddress.loopbackIPv4,
        0,
      );

      final client = await StudentHubClient.connect(
        wsUrl: 'ws://127.0.0.1:${server.port}/',
        sessionKey: key,
        sessionId: sessionId,
        onMessage: (_, __) {},
      );

      final p = await submitPayload('a2');
      ok = await client.sendWithAck(
        type: SyncMessageTypes.attemptSubmit,
        plainBytes: utf8.encode(p.encode()),
        attemptId: 'a2',
        attempts: 2,
        timeout: const Duration(milliseconds: 200),
      );

      await client.close();
      await server.close(force: true);
    });

    expect(ok, isFalse, reason: '화면이 "전달되지 않았다"고 알릴 수 있어야 한다');
    expect(attemptsSeen, 2, reason: '회신이 없으면 다시 보낸다');
  });
}
