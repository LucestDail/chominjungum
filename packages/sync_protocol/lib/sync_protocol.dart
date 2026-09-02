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
