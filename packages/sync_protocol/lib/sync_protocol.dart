import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:meta/meta.dart';

/// 교사 로컬 WebSocket 허브 기본 포트 (30000번대).
abstract final class SyncDefaults {
  static const int hubPort = 30020;
}

/// QR 코드 등으로 교환하는 1회성 페어링 페이로드 (평문 JSON).
@immutable
class SessionPairingPayload {
  const SessionPairingPayload({
    required this.sessionId,
    required this.hostDisplayName,
    required this.publicKeyB64,
    required this.createdAtMs,
    required this.ttlSeconds,
    this.hubPort = SyncDefaults.hubPort,
    this.hubHost,
  });

  final String sessionId;
  final String hostDisplayName;
  /// MVP: 세션 대칭키(Base64). 추후 X25519 공개키 등으로 교체 가능.
  final String publicKeyB64;
  final int createdAtMs;
  final int ttlSeconds;
  final int hubPort;
  /// 교사 기기 LAN IPv4 (학생이 WebSocket 연결에 사용).
  final String? hubHost;

  Map<String, Object?> toJson() => {
        'v': 1,
        'sessionId': sessionId,
        'hostDisplayName': hostDisplayName,
        'publicKeyB64': publicKeyB64,
        'createdAtMs': createdAtMs,
        'ttlSeconds': ttlSeconds,
        'hubPort': hubPort,
        if (hubHost != null) 'hubHost': hubHost,
      };

  factory SessionPairingPayload.fromJson(Map<String, Object?> json) {
    return SessionPairingPayload(
      sessionId: json['sessionId']! as String,
      hostDisplayName: json['hostDisplayName']! as String,
      publicKeyB64: json['publicKeyB64']! as String,
      createdAtMs: json['createdAtMs'] as int? ?? 0,
      ttlSeconds: json['ttlSeconds'] as int? ?? 300,
      hubPort: json['hubPort'] as int? ?? SyncDefaults.hubPort,
      hubHost: json['hubHost'] as String?,
    );
  }

  String encode() => jsonEncode(toJson());

  static SessionPairingPayload decode(String raw) {
    final map = jsonDecode(raw) as Map<String, Object?>;
    return SessionPairingPayload.fromJson(map);
  }
}

/// 앱 간 전송 단위 — [cipherText]는 AES-GCM 암호문, [mac]은 인증 태그.
@immutable
class SyncEnvelope {
  const SyncEnvelope({
    required this.sessionId,
    required this.nonceB64,
    required this.cipherTextB64,
    required this.macB64,
    required this.type,
  });

  final String sessionId;
  final String nonceB64;
  final String cipherTextB64;
  final String macB64;
  final String type;

  Map<String, Object?> toJson() => {
        'v': 1,
        'sessionId': sessionId,
        'nonceB64': nonceB64,
        'cipherTextB64': cipherTextB64,
        'macB64': macB64,
        'type': type,
      };

  factory SyncEnvelope.fromJson(Map<String, Object?> json) {
    return SyncEnvelope(
      sessionId: json['sessionId']! as String,
      nonceB64: json['nonceB64']! as String,
      cipherTextB64: json['cipherTextB64']! as String,
      macB64: json['macB64']! as String,
      type: json['type']! as String,
    );
  }

  String encode() => jsonEncode(toJson());

  static SyncEnvelope decode(String raw) {
    final map = jsonDecode(raw) as Map<String, Object?>;
    return SyncEnvelope.fromJson(map);
  }
}

/// 세션 대칭키로 envelope 암·복호화 (교사 허브가 생성한 키를 페어링 후 양쪽에 저장).
class SyncCrypto {
  SyncCrypto._();

  static final _algo = AesGcm.with256bits();

  static Future<SecretKey> newSessionKey() => _algo.newSecretKey();

  static Future<Uint8List> sessionKeyBytes(SecretKey key) async {
    return Uint8List.fromList(await key.extractBytes());
  }

  static Future<SecretKey> sessionKeyFromBytes(Uint8List bytes) async {
    return SecretKey(bytes);
  }

  static Future<SyncEnvelope> seal({
    required SecretKey sessionKey,
    required String sessionId,
    required String type,
    required List<int> plainBytes,
  }) async {
    final box = await _algo.encrypt(
      plainBytes,
      secretKey: sessionKey,
    );
    return SyncEnvelope(
      sessionId: sessionId,
      nonceB64: base64Encode(box.nonce),
      cipherTextB64: base64Encode(box.cipherText),
      macB64: base64Encode(box.mac.bytes),
      type: type,
    );
  }

  static Future<Uint8List> open({
    required SecretKey sessionKey,
    required SyncEnvelope envelope,
  }) async {
    final nonce = base64Decode(envelope.nonceB64);
    final cipherText = base64Decode(envelope.cipherTextB64);
    final mac = Mac(base64Decode(envelope.macB64));
    final secretBox = SecretBox(cipherText, nonce: nonce, mac: mac);
    return Uint8List.fromList(await _algo.decrypt(secretBox, secretKey: sessionKey));
  }
}

/// 도메인 메시지 타입 상수 (평문 JSON body 암호화 전).
abstract class SyncMessageTypes {
  static const dictationPackage = 'dictation.package';
  static const attemptSubmit = 'attempt.submit';
  static const ack = 'ack';
}
