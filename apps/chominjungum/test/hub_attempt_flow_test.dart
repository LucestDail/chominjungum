import 'dart:async';
import 'dart:convert';

import 'package:chominjungum/domain/dictation_models.dart';
import 'package:chominjungum/services/local_hub_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_protocol/sync_protocol.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// 교사 허브 ↔ 학생 클라이언트 실제 WebSocket 왕복:
/// 출제 브로드캐스트 → 학생 수신 → 답안 제출 → 교사 수신.
void main() {
  late LocalHubService hub;
  late String sessionId;
  final receivedAttempts = <AttemptSubmitPayload>[];
  final clientCounts = <int>[];

  setUp(() async {
    receivedAttempts.clear();
    clientCounts.clear();
    sessionId = 'test-session';
    hub = LocalHubService(
      sessionId: sessionId,
      sessionKey: await SyncCrypto.newSessionKey(),
      port: 0,
      onAttempt: receivedAttempts.add,
      onClientCountChanged: clientCounts.add,
    );
    await hub.start();
  });

  tearDown(() async {
    await hub.stop();
  });

  Future<StudentHubClient> connectStudent({
    void Function(List<int> plain, SyncEnvelope env)? onMessage,
    void Function()? onDisconnected,
  }) {
    return StudentHubClient.connect(
      wsUrl: 'ws://127.0.0.1:${hub.boundPort}/',
      sessionKey: hub.sessionKey,
      sessionId: sessionId,
      onMessage: onMessage ?? (_, __) {},
      onDisconnected: onDisconnected,
    );
  }

  test('출제 → 학생 수신 → 채점 답안 제출 → 교사 수신', () async {
    final packageReceived = Completer<DictationPackage>();
    final student = await connectStudent(
      onMessage: (plain, env) {
        final pkg = tryDecodeDictationPackage(plain, env);
        if (pkg != null && !packageReceived.isCompleted) {
          packageReceived.complete(pkg);
        }
      },
    );
    addTearDown(student.close);

    final item = DictationItem.fromExpectedText('안녕하세요');
    await hub.broadcastEncrypted(
      type: SyncMessageTypes.dictationPackage,
      plainBytes: DictationPackage(
        version: DictationPackage.currentVersion,
        items: [item],
      ).toUtf8Bytes(),
    );

    final pkg = await packageReceived.future.timeout(const Duration(seconds: 5));
    expect(pkg.items.single.expectedText, '안녕하세요');

    await student.sendEncrypted(
      type: SyncMessageTypes.attemptSubmit,
      plainBytes: AttemptSubmitPayload(
        attemptId: 'attempt-1',
        itemId: pkg.items.single.id,
        expectedText: '안녕하세요',
        rawAnswer: '안녕하세오',
        deviceBindingId: 'device-1',
        correctCount: 4,
        totalCount: 5,
        submittedAtMs: 1700000000000,
      ).toUtf8Bytes(),
    );

    await _waitUntil(() => receivedAttempts.isNotEmpty);
    final attempt = receivedAttempts.single;
    expect(attempt.rawAnswer, '안녕하세오');
    expect(attempt.scorePercent, 80);
    expect(attempt.deviceBindingId, 'device-1');
    expect(clientCounts.first, 1);
  });

  test('다른 세션 키로 온 제출은 무시된다', () async {
    final foreignKey = await SyncCrypto.newSessionKey();
    final channel = WebSocketChannel.connect(
      Uri.parse('ws://127.0.0.1:${hub.boundPort}/'),
    );
    await channel.ready;
    addTearDown(() => channel.sink.close());

    final env = await SyncCrypto.seal(
      sessionKey: foreignKey,
      sessionId: sessionId,
      type: SyncMessageTypes.attemptSubmit,
      plainBytes: utf8.encode('{"attemptId":"x","itemId":"y"}'),
    );
    channel.sink.add(env.encode());

    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(receivedAttempts, isEmpty);
  });

  test('학생 연결 해제 시 접속 수가 줄어든다', () async {
    final student = await connectStudent();
    await _waitUntil(() => hub.clientCount == 1);
    await student.close();
    await _waitUntil(() => hub.clientCount == 0);
    expect(clientCounts.last, 0);
  });

  test('★허브가 멈추면 학생이 끊김을 통보받는다', () async {
    // 그전에는 학생 쪽에 끊김 감지가 아예 없어서, 연결이 죽어도 화면은
    // "허브에 연결됨" 그대로였고 제출은 조용히 실패했다.
    var disconnected = 0;
    await connectStudent(onDisconnected: () => disconnected++);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(disconnected, 0, reason: '아직 붙어 있는데 통보되면 안 된다');

    await hub.stop();
    for (var i = 0; disconnected == 0 && i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(disconnected, 1, reason: '끊기면 정확히 한 번 통보돼야 한다');
  });

  test('학생이 스스로 닫아도 통보는 한 번을 넘지 않는다', () async {
    var disconnected = 0;
    final student = await connectStudent(onDisconnected: () => disconnected++);
    await student.close();
    for (var i = 0; disconnected == 0 && i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(disconnected, lessThanOrEqualTo(1));
  });
}

Future<void> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('조건이 $timeout 안에 만족되지 않았습니다.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
