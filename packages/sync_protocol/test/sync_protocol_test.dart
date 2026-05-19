import 'dart:convert';
import 'dart:typed_data';

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
