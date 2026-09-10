import 'package:chominjungum/services/local_hub_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_protocol/sync_protocol.dart';

/// 학생이 접속 직후 자기를 알린다 — 제출 전에도 교사 명단에 뜨게.
///
/// 교사가 가장 알고 싶은 것은 **"접속은 했는데 한 문제도 안 푼 학생"** 이다.
/// 제출로만 명단을 만들면 그 아이가 안 보인다.
void main() {
  testWidgets('접속 알림이 교사에게 도착한다', (tester) async {
    final joined = <StudentJoinPayload>[];
    const sessionId = 'join-test';

    await tester.runAsync(() async {
      final key = await SyncCrypto.newSessionKey();
      final hub = LocalHubService(
        sessionId: sessionId,
        sessionKey: key,
        port: 0,
        onStudentJoined: joined.add,
      );
      await hub.start();

      final client = await StudentHubClient.connect(
        wsUrl: 'ws://127.0.0.1:${hub.boundPort}/',
        sessionKey: key,
        sessionId: sessionId,
        onMessage: (_, __) {},
      );
      await client.announce(deviceBindingId: 'dev-1', displayName: '민준');

      for (var i = 0; i < 40 && joined.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await client.close();
      await hub.stop();
    });

    expect(joined, hasLength(1));
    expect(joined.single.deviceBindingId, 'dev-1');
    expect(joined.single.displayName, '민준');
  });

  testWidgets('이름을 안 적어도 접속은 알려진다 — 이름은 선택이다', (tester) async {
    final joined = <StudentJoinPayload>[];
    const sessionId = 'join-noname';

    await tester.runAsync(() async {
      final key = await SyncCrypto.newSessionKey();
      final hub = LocalHubService(
        sessionId: sessionId,
        sessionKey: key,
        port: 0,
        onStudentJoined: joined.add,
      );
      await hub.start();
      final client = await StudentHubClient.connect(
        wsUrl: 'ws://127.0.0.1:${hub.boundPort}/',
        sessionKey: key,
        sessionId: sessionId,
        onMessage: (_, __) {},
      );
      await client.announce(deviceBindingId: 'dev-2');
      for (var i = 0; i < 40 && joined.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await client.close();
      await hub.stop();
    });

    expect(joined.single.displayName, isNull);
  });

  test('이름이 비면 JSON 에 키를 싣지 않는다', () {
    const p = StudentJoinPayload(deviceBindingId: 'd', displayName: '');
    expect(p.toJson().containsKey('displayName'), isFalse);
  });
}
