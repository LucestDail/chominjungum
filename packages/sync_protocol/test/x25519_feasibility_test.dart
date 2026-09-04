import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:sync_protocol/sync_protocol.dart';
import 'package:test/test.dart';

/// **B2 사전 검증 — 아직 프로토콜을 바꾸지 않았다.**
///
/// 현재 QR(`SessionPairingPayload.publicKeyB64`)에는 **대칭 세션 키가 그대로** 담긴다.
/// 코드 주석도 "MVP: 세션 대칭키(Base64). 추후 X25519 공개키 등으로 교체 가능"이라고
/// 적어 두었다. QR 을 촬영당하면 같은 Wi-Fi 의 제3자가 세션을 도청·위조할 수 있다.
///
/// 교체 방향(X25519 ECDH)이 **이 패키지로 실제 가능한지**만 여기서 확인한다.
/// 프로토콜 교체 자체는 사람 결정이 필요하다 — 하위호환과 목적이 양립하지 않고
/// (키를 QR 에서 빼는 것이 목적이라 옛 경로를 남기면 의미가 없다),
/// 교사·학생 앱을 동시에 올려야 하며, 실기기 리허설 전에 검증되지 않은 키 교환을
/// 넣으면 리허설 실패의 원인 분리가 어려워진다. 선택지는 `WEEKEND-…md` 에 적었다.
void main() {
  group('X25519 키 교환이 이 의존성으로 되는가', () {
    test('양쪽이 같은 공유 비밀에 도달한다', () async {
      final algorithm = X25519();

      final teacher = await algorithm.newKeyPair();
      final student = await algorithm.newKeyPair();

      final teacherPub = await teacher.extractPublicKey();
      final studentPub = await student.extractPublicKey();

      final onTeacher = await algorithm.sharedSecretKey(
        keyPair: teacher,
        remotePublicKey: studentPub,
      );
      final onStudent = await algorithm.sharedSecretKey(
        keyPair: student,
        remotePublicKey: teacherPub,
      );

      expect(await onTeacher.extractBytes(), await onStudent.extractBytes());
    });

    test('공개키는 QR 에 담을 수 있는 크기다 (32바이트)', () async {
      final keyPair = await X25519().newKeyPair();
      final pub = await keyPair.extractPublicKey();

      expect(pub.bytes.length, 32);
      // 지금 QR 에 넣는 대칭키와 같은 44자 base64 — QR 용량은 그대로다
      expect(base64Encode(pub.bytes).length, 44);
    });

    test('공유 비밀에서 유도한 키로 기존 envelope 이 그대로 동작한다', () async {
      final algorithm = X25519();
      final teacher = await algorithm.newKeyPair();
      final student = await algorithm.newKeyPair();

      final shared = await algorithm.sharedSecretKey(
        keyPair: teacher,
        remotePublicKey: await student.extractPublicKey(),
      );

      // 공유 비밀을 바로 쓰지 않고 HKDF 로 세션키를 뽑는다(같은 비밀을 여러 용도로
      // 쓰지 않기 위한 표준 절차). AES-GCM 256 이므로 32바이트.
      final sessionKey = await Hkdf(
        hmac: Hmac.sha256(),
        outputLength: 32,
      ).deriveKey(
        secretKey: shared,
        info: utf8.encode('chominjungum/session/v2'),
        nonce: utf8.encode('pairing'),
      );

      final envelope = await SyncCrypto.seal(
        sessionKey: sessionKey,
        sessionId: 's1',
        type: SyncMessageTypes.dictationPackage,
        plainBytes: utf8.encode('학교에 갔다.'),
      );
      final opened = await SyncCrypto.open(
        sessionKey: sessionKey,
        envelope: envelope,
      );

      expect(utf8.decode(opened), '학교에 갔다.');
    });

    test('상대 공개키가 다르면 다른 키가 나온다 (엉뚱한 기기와 붙지 않는다)', () async {
      final algorithm = X25519();
      final teacher = await algorithm.newKeyPair();
      final student = await algorithm.newKeyPair();
      final intruder = await algorithm.newKeyPair();

      final withStudent = await algorithm.sharedSecretKey(
        keyPair: teacher,
        remotePublicKey: await student.extractPublicKey(),
      );
      final withIntruder = await algorithm.sharedSecretKey(
        keyPair: teacher,
        remotePublicKey: await intruder.extractPublicKey(),
      );

      expect(
        await withStudent.extractBytes(),
        isNot(await withIntruder.extractBytes()),
      );
    });
  });

  group('지금 프로토콜의 성질 (교체 전 기준선)', () {
    test('QR 문자열에 대칭 세션 키가 그대로 들어 있다', () async {
      final key = await SyncCrypto.newSessionKey();
      final keyBytes = await SyncCrypto.sessionKeyBytes(key);

      final payload = SessionPairingPayload(
        sessionId: 's1',
        hostDisplayName: '교사',
        publicKeyB64: base64Encode(keyBytes),
        createdAtMs: 0,
        ttlSeconds: 600,
        hubPort: 8765,
        hubHost: '192.168.0.10',
      );

      // QR 을 촬영한 사람은 이 키로 세션을 열 수 있다 — B2 가 고칠 지점.
      final leaked = base64Decode(SessionPairingPayload.decode(payload.encode()).publicKeyB64);
      final reconstructed = await SyncCrypto.sessionKeyFromBytes(Uint8List.fromList(leaked));

      final envelope = await SyncCrypto.seal(
        sessionKey: key,
        sessionId: 's1',
        type: SyncMessageTypes.dictationPackage,
        plainBytes: utf8.encode('비밀'),
      );
      expect(
        utf8.decode(await SyncCrypto.open(sessionKey: reconstructed, envelope: envelope)),
        '비밀',
      );
    });
  });
}
