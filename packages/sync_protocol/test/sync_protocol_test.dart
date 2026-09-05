import 'dart:convert';

import 'package:sync_protocol/sync_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('SessionPairingPayload roundtrip', () {
    const p = SessionPairingPayload(
      sessionId: 's1',
      hostDisplayName: 'Teacher',
      publicKeyB64: 'abc',
      createdAtMs: 1,
      ttlSeconds: 60,
    );
    final decoded = SessionPairingPayload.decode(p.encode());
    expect(decoded.sessionId, 's1');
    expect(decoded.hubPort, SyncDefaults.hubPort);
  });

  test('AttemptSubmitPayload roundtrip', () {
    const p = AttemptSubmitPayload(
      attemptId: 'a1',
      itemId: 'i1',
      expectedText: '안녕하세요',
      rawAnswer: '안녕하세오',
      deviceBindingId: 'device-uuid',
      correctCount: 4,
      totalCount: 5,
      submittedAtMs: 1700000000000,
      studentName: '1번',
    );
    final decoded = AttemptSubmitPayload.decode(p.encode());
    expect(decoded.attemptId, 'a1');
    expect(decoded.expectedText, '안녕하세요');
    expect(decoded.correctCount, 4);
    expect(decoded.scorePercent, 80);
    expect(decoded.inputKind, 'keyboard');
    expect(decoded.studentName, '1번');
  });

  test('AttemptSubmitPayload v2 — matches·sessionId 왕복', () {
    const p = AttemptSubmitPayload(
      attemptId: 'a3',
      itemId: 'i3',
      expectedText: '안녕',
      rawAnswer: '안뇽',
      deviceBindingId: 'device',
      correctCount: 1,
      totalCount: 2,
      submittedAtMs: 1700000000000,
      sessionId: 'session-1',
      matches: [
        GlyphMatchSummary(index: 0, ok: true),
        GlyphMatchSummary(index: 1, ok: false, why: '글자 불일치'),
      ],
    );
    final decoded = AttemptSubmitPayload.decode(p.encode());
    expect(decoded.sessionId, 'session-1');
    expect(decoded.matches, hasLength(2));
    expect(decoded.matches![1].ok, isFalse);
    expect(decoded.matches![1].why, '글자 불일치');
  });

  test('v1 페이로드(matches 없음)도 그대로 읽힌다 — 하위호환', () {
    final v1 = AttemptSubmitPayload.fromJson({
      'attemptId': 'a4',
      'itemId': 'i4',
      'expectedText': '학교',
      'rawAnswer': '학교',
      'deviceBindingId': 'device',
      'correctCount': 2,
      'totalCount': 2,
      'submittedAtMs': 1700000000000,
      'inputKind': 'keyboard',
    });
    expect(v1.matches, isNull);
    expect(v1.sessionId, isNull);
    expect(v1.scorePercent, 100);
    // 다시 직렬화해도 없는 필드는 붙지 않는다
    expect(v1.encode().contains('matches'), isFalse);
  });

  test('AttemptSubmitPayload handles missing optional fields', () {
    final decoded = AttemptSubmitPayload.fromJson({
      'attemptId': 'a2',
      'itemId': 'i2',
    });
    expect(decoded.totalCount, 0);
    expect(decoded.ratio, 0);
    expect(decoded.studentName, isNull);
  });

  test('SyncEnvelope seal/open', () async {
    final key = await SyncCrypto.newSessionKey();
    final plain = utf8.encode('hello');
    final env = await SyncCrypto.seal(
      sessionKey: key,
      sessionId: 'sid',
      type: SyncMessageTypes.ack,
      plainBytes: plain,
    );
    final out = await SyncCrypto.open(sessionKey: key, envelope: env);
    expect(out, plain);
  });
}
