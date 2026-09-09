import 'dart:async';
import 'dart:convert';

import 'package:chominjungum/domain/dictation_models.dart';
import 'package:chominjungum/services/local_hub_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_protocol/sync_protocol.dart';

/// **페어링 v2 — QR 에서 세션 대칭키를 뺀다 (B2).**
///
/// v1 은 QR(`SessionPairingPayload.publicKeyB64`)에 **세션 대칭키를 그대로** 담았다.
/// QR 을 촬영당하면 같은 Wi-Fi 의 제3자가 도청·위조할 수 있었다.
///
/// v2 는 QR 에 **교사 공개키**만 담고, 접속한 학생이 자기 공개키를 `hello` 로 보내면
/// 교사가 ECDH+HKDF 로 **그 학생 전용 래핑 키**를 만들어 수업 세션 키를 감싸 보낸다
/// (`session.key`). 그 뒤 출제 브로드캐스트는 v1 과 똑같이 세션 키 하나로 나간다.
///
/// 왜 세션 키를 따로 두나: ECDH 는 학생마다 다른 비밀을 만들어서, 그것을 세션 키로
/// 쓰면 브로드캐스트를 학생 수만큼 암호화해야 한다. **키는 하나, 전달만 학생별.**
void main() {
  late LocalHubService hub;
  late String sessionId;
  late String hostPubB64;
  final received = <AttemptSubmitPayload>[];

  setUp(() async {
    received.clear();
    sessionId = 'v2-session';
    final hostPair = await SyncKeyExchange.newKeyPair();
    hostPubB64 = await SyncKeyExchange.publicKeyB64(hostPair);
    hub = LocalHubService(
      sessionId: sessionId,
      sessionKey: await SyncCrypto.newSessionKey(),
      port: 0,
      hostKeyPair: hostPair,
      onAttempt: received.add,
    );
    await hub.start();
  });

  tearDown(() async => hub.stop());

  Future<StudentHubClient> connectV2({
    void Function(List<int> plain, SyncEnvelope env)? onMessage,
    void Function()? onReady,
  }) {
    return StudentHubClient.connect(
      wsUrl: 'ws://127.0.0.1:${hub.boundPort}/',
      sessionId: sessionId,
      hostPublicKeyB64: hostPubB64, // ← QR 에는 이것만 들어간다
      onMessage: onMessage ?? (_, __) {},
      onSessionKeyReady: onReady,
    );
  }

  Future<void> waitUntil(bool Function() done, {String? what}) async {
    for (var i = 0; i < 100; i++) {
      if (done()) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    fail('${what ?? '조건'}이 5초 안에 만족되지 않았습니다.');
  }

  test('★QR 에 대칭키가 없어도 왕복이 된다 (hello → session.key → 출제 → 제출)',
      () async {
    final ready = Completer<void>();
    final gotPackage = Completer<DictationPackage>();
    final student = await connectV2(
      onReady: () => ready.complete(),
      onMessage: (plain, env) {
        final pkg = tryDecodeDictationPackage(plain, env);
        if (pkg != null && !gotPackage.isCompleted) gotPackage.complete(pkg);
      },
    );
    addTearDown(student.close);

    // 1) 핸드셰이크 — 교사가 감싸 보낸 세션 키를 학생이 풀었다
    await ready.future.timeout(const Duration(seconds: 5));
    expect(student.isReady, isTrue);

    // 2) 출제 — 그 뒤는 v1 과 똑같이 세션 키 하나로 브로드캐스트
    final pkg = DictationPackage(
      version: DictationPackage.currentVersion,
      items: [DictationItem.fromExpectedText('학교에 갔다.')],
    );
    await hub.broadcastEncrypted(
      type: SyncMessageTypes.dictationPackage,
      plainBytes: pkg.toUtf8Bytes(),
    );
    final got = await gotPackage.future.timeout(const Duration(seconds: 5));
    expect(got.items.single.expectedText, '학교에 갔다.');

    // 3) 제출 — 학생이 같은 키로 올려도 교사가 읽는다
    final attempt = AttemptSubmitPayload(
      attemptId: 'v2-a1',
      itemId: got.items.single.id,
      expectedText: '학교에 갔다.',
      rawAnswer: '학교에 갔다.',
      deviceBindingId: 'v2-device',
      correctCount: 7,
      totalCount: 7,
      submittedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await student.sendEncrypted(
      type: SyncMessageTypes.attemptSubmit,
      plainBytes: utf8.encode(jsonEncode(attempt.toJson())),
    );
    await waitUntil(() => received.isNotEmpty, what: '제출 수신');
    expect(received.single.rawAnswer, '학교에 갔다.');
  });

  test('학생 둘이 같은 수업 키를 받는다 (브로드캐스트 한 번으로 전원 수신)', () async {
    // ECDH 는 학생마다 다른 비밀을 만든다. 그것을 세션 키로 썼다면 이 테스트가 깨진다
    // — 키 래핑을 쓰는 이유가 바로 이것이다.
    final a = Completer<DictationPackage>();
    final b = Completer<DictationPackage>();
    final ra = Completer<void>();
    final rb = Completer<void>();
    final s1 = await connectV2(
      onReady: () => ra.complete(),
      onMessage: (p, e) {
        final pkg = tryDecodeDictationPackage(p, e);
        if (pkg != null && !a.isCompleted) a.complete(pkg);
      },
    );
    final s2 = await connectV2(
      onReady: () => rb.complete(),
      onMessage: (p, e) {
        final pkg = tryDecodeDictationPackage(p, e);
        if (pkg != null && !b.isCompleted) b.complete(pkg);
      },
    );
    addTearDown(() async {
      await s1.close();
      await s2.close();
    });

    await Future.wait([ra.future, rb.future]).timeout(const Duration(seconds: 5));

    await hub.broadcastEncrypted(
      type: SyncMessageTypes.dictationPackage,
      plainBytes: DictationPackage(
        version: DictationPackage.currentVersion,
        items: [DictationItem.fromExpectedText('꽃이 피었습니다')],
      ).toUtf8Bytes(),
    );

    final r = await Future.wait([a.future, b.future])
        .timeout(const Duration(seconds: 5));
    expect(r[0].items.single.expectedText, '꽃이 피었습니다');
    expect(r[1].items.single.expectedText, '꽃이 피었습니다');
  });

  test('★엉뚱한 공개키로는 세션 키를 못 푼다 (QR 을 훔쳐봐도 소용없다)', () async {
    // 도청자가 QR(=교사 공개키)을 알아도, 자기 키로는 다른 래핑 키가 나온다.
    // 즉 교사가 **다른 학생에게** 보낸 session.key 를 가로채도 풀 수 없다.
    final victim = await SyncKeyExchange.newKeyPair();
    final intruder = await SyncKeyExchange.newKeyPair();
    final hostPair = await SyncKeyExchange.newKeyPair();

    final forVictim = await SyncKeyExchange.deriveWrapKey(
      myKeyPair: hostPair,
      theirPublicKey: await victim.extractPublicKey(),
      sessionId: sessionId,
    );
    final atIntruder = await SyncKeyExchange.deriveWrapKey(
      myKeyPair: intruder,
      theirPublicKey: await hostPair.extractPublicKey(),
      sessionId: sessionId,
    );

    final sealed = await SyncCrypto.seal(
      sessionKey: forVictim,
      sessionId: sessionId,
      type: SyncMessageTypes.sessionKey,
      plainBytes: utf8.encode('세션키'),
    );
    await expectLater(
      SyncCrypto.open(sessionKey: atIntruder, envelope: sealed),
      throwsA(anything),
      reason: '남에게 감싼 키를 제3자가 풀 수 있으면 안 된다',
    );
  });

  test('세션 id 가 다른 hello 는 무시한다', () async {
    // 다른 수업의 학생이 잘못 붙어도 우리 세션 키를 흘리지 않는다.
    var replied = false;
    final client = await StudentHubClient.connect(
      wsUrl: 'ws://127.0.0.1:${hub.boundPort}/',
      sessionId: 'other-session', // ← 다른 세션
      hostPublicKeyB64: hostPubB64,
      onMessage: (_, __) {},
      onSessionKeyReady: () => replied = true,
    );
    addTearDown(client.close);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(replied, isFalse);
    expect(client.isReady, isFalse);
  });
}
