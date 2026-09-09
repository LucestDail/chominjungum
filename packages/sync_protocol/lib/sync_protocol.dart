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

  /// **교사의 X25519 공개키**(Base64, 32바이트) — 페어링 v2.
  ///
  /// ⚠️v1 에서는 여기에 **세션 대칭키가 그대로** 들어 있었다. QR 을 촬영당하면
  /// 같은 Wi-Fi 의 제3자가 도청·위조할 수 있었다. v2 는 공개키만 담고,
  /// 실제 세션 키는 접속 후 핸드셰이크로 전달한다([SyncMessageTypes.hello] /
  /// [SyncMessageTypes.sessionKey]). 공개키도 32바이트라 **QR 용량은 그대로**다.
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
/// X25519 키 교환 — QR 에서 대칭키를 빼기 위한 것(페어링 v2).
///
/// ## 왜 세션 키를 따로 두나
///
/// ECDH 는 **양쪽 쌍마다 다른 비밀**을 만든다. 그것을 그대로 세션 키로 쓰면 교사가
/// 브로드캐스트할 때 **학생 수만큼 암호화**해야 한다. 그래서 교사는 수업용 대칭키를
/// 하나 만들어 두고, 접속한 학생에게 **그 학생만 풀 수 있게 감싸서** 한 번 전달한다
/// (키 래핑). 그 뒤 출제 브로드캐스트는 v1 과 똑같이 대칭키 하나로 나간다.
/// `hello` — 학생 → 교사, **평문**. 자기 X25519 공개키를 알린다(페어링 v2).
///
/// 암호 봉투([SyncEnvelope])가 아니라 평문인 이유: 이 메시지를 주고받아야 비로소
/// 공유 키가 생긴다. 공개키는 공개돼도 되는 값이라 평문으로 충분하다
/// (도청자가 봐도 세션 키를 얻지 못한다 — 그것이 ECDH 를 쓰는 이유다).
@immutable
class HelloPayload {
  const HelloPayload({required this.sessionId, required this.publicKeyB64});

  final String sessionId;
  final String publicKeyB64;

  Map<String, Object?> toJson() => {
        'v': 2,
        'type': SyncMessageTypes.hello,
        'sessionId': sessionId,
        'publicKeyB64': publicKeyB64,
      };

  factory HelloPayload.fromJson(Map<String, Object?> json) => HelloPayload(
        sessionId: json['sessionId']! as String,
        publicKeyB64: json['publicKeyB64']! as String,
      );

  String encode() => jsonEncode(toJson());

  static HelloPayload decode(String raw) =>
      HelloPayload.fromJson(jsonDecode(raw) as Map<String, Object?>);
}

/// 수신한 원문이 어떤 메시지인지 **열어보지 않고** 가른다.
///
/// 평문 `hello` 와 암호 봉투가 같은 소켓으로 오므로, `type` 만 먼저 읽는다.
/// 깨진 입력이면 null (교실망 잡음 방어).
String? peekMessageType(String raw) {
  try {
    final m = jsonDecode(raw) as Map<String, Object?>;
    return m['type'] as String?;
  } catch (_) {
    return null;
  }
}

abstract final class SyncKeyExchange {
  static final _x25519 = X25519();

  /// 이 수업(또는 이 학생)의 키 쌍.
  static Future<SimpleKeyPair> newKeyPair() => _x25519.newKeyPair();

  static Future<String> publicKeyB64(SimpleKeyPair pair) async =>
      base64Encode((await pair.extractPublicKey()).bytes);

  static SimplePublicKey publicKeyFromB64(String b64) =>
      SimplePublicKey(base64Decode(b64), type: KeyPairType.x25519);

  /// 상대 공개키와의 공유 비밀에서 **래핑 전용 키**를 유도한다.
  ///
  /// 공유 비밀을 그대로 쓰지 않고 HKDF 를 거치는 것은 표준 절차다
  /// (같은 비밀을 여러 용도로 재사용하지 않기 위해). [sessionId] 를 nonce 로 넣어
  /// 다른 수업의 래핑 키와 섞이지 않게 한다.
  static Future<SecretKey> deriveWrapKey({
    required SimpleKeyPair myKeyPair,
    required SimplePublicKey theirPublicKey,
    required String sessionId,
  }) async {
    final shared = await _x25519.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: theirPublicKey,
    );
    return Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: shared,
      info: utf8.encode('chominjungum/pairing/v2'),
      nonce: utf8.encode(sessionId),
    );
  }
}

abstract class SyncMessageTypes {
  static const dictationPackage = 'dictation.package';
  static const attemptSubmit = 'attempt.submit';
  static const ack = 'ack';

  /// 학생 → 교사, **평문**. 학생의 X25519 공개키를 보낸다(페어링 v2).
  static const hello = 'hello';

  /// 교사 → 학생, **학생별 유도키로 암호화**. 이 수업의 세션 대칭키를 감싸 보낸다.
  static const sessionKey = 'session.key';
}

/// 글자별 정오 요약 — 서버의 취약 자모 분석 원천 (프로토콜 v2).
@immutable
class GlyphMatchSummary {
  const GlyphMatchSummary({required this.index, required this.ok, this.why});

  final int index;
  final bool ok;
  final String? why;

  Map<String, Object?> toJson() => {
        'i': index,
        'ok': ok,
        if (why != null) 'why': why,
      };

  factory GlyphMatchSummary.fromJson(Map<String, Object?> json) {
    return GlyphMatchSummary(
      index: json['i'] as int? ?? 0,
      ok: json['ok'] == true,
      why: json['why'] as String?,
    );
  }
}

/// 학생 → 교사 허브로 보내는 답안·채점 결과 (`attempt.submit` body).
///
/// v2 에서 [matches]·[sessionId] 가 추가됐다. **둘 다 선택 항목**이라 v1 페이로드를
/// 보내는 구버전 앱과도 그대로 호환된다.
@immutable
class AttemptSubmitPayload {
  const AttemptSubmitPayload({
    required this.attemptId,
    required this.itemId,
    required this.expectedText,
    required this.rawAnswer,
    required this.deviceBindingId,
    required this.correctCount,
    required this.totalCount,
    required this.submittedAtMs,
    this.inputKind = 'keyboard',
    this.studentName,
    this.matches,
    this.sessionId,
  });

  final String attemptId;
  final String itemId;
  final String expectedText;
  final String rawAnswer;

  /// 학생 기기 식별자 (교사 화면 표시는 축약본 사용).
  final String deviceBindingId;
  final int correctCount;
  final int totalCount;
  final int submittedAtMs;

  /// `keyboard` / `ocrCanvas` / `ocrImage`.
  final String inputKind;
  final String? studentName;

  /// v2: 글자별 정오. 구버전 앱은 보내지 않는다.
  final List<GlyphMatchSummary>? matches;

  /// v2: 서버 업싱크 시 이 제출이 속한 허브 세션.
  final String? sessionId;

  double get ratio => totalCount == 0 ? 0 : correctCount / totalCount;

  int get scorePercent => (ratio * 100).round();

  Map<String, Object?> toJson() => {
        'v': 1,
        'attemptId': attemptId,
        'itemId': itemId,
        'expectedText': expectedText,
        'rawAnswer': rawAnswer,
        'deviceBindingId': deviceBindingId,
        'correctCount': correctCount,
        'totalCount': totalCount,
        'submittedAtMs': submittedAtMs,
        'inputKind': inputKind,
        if (studentName != null) 'studentName': studentName,
        if (matches != null) 'matches': matches!.map((m) => m.toJson()).toList(),
        if (sessionId != null) 'sessionId': sessionId,
      };

  factory AttemptSubmitPayload.fromJson(Map<String, Object?> json) {
    return AttemptSubmitPayload(
      attemptId: json['attemptId']! as String,
      itemId: json['itemId']! as String,
      expectedText: json['expectedText'] as String? ?? '',
      rawAnswer: json['rawAnswer'] as String? ?? '',
      deviceBindingId: json['deviceBindingId'] as String? ?? '',
      correctCount: json['correctCount'] as int? ?? 0,
      totalCount: json['totalCount'] as int? ?? 0,
      submittedAtMs: json['submittedAtMs'] as int? ?? 0,
      inputKind: json['inputKind'] as String? ?? 'keyboard',
      studentName: json['studentName'] as String?,
      matches: (json['matches'] as List<dynamic>?)
          ?.map((e) => GlyphMatchSummary.fromJson(Map<String, Object?>.from(e as Map)))
          .toList(),
      sessionId: json['sessionId'] as String?,
    );
  }

  String encode() => jsonEncode(toJson());

  static AttemptSubmitPayload decode(String raw) {
    return AttemptSubmitPayload.fromJson(jsonDecode(raw) as Map<String, Object?>);
  }

  Uint8List toUtf8Bytes() => Uint8List.fromList(utf8.encode(encode()));
}
