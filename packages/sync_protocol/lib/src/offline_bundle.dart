import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../sync_protocol.dart';

/// **허브 없이** 출제를 전달하는 오프라인 번들.
///
/// ## 왜 필요한가
///
/// 지금 출제는 교사 기기가 띄운 WebSocket 허브를 거친다. 그런데 교실 Wi-Fi 가
/// **단말 간 통신을 막아 두면**(클라이언트 격리) 앱의 전제가 통째로 무너진다 —
/// `docs/REHEARSAL.md` 가 "가장 먼저 확인할 것"으로 꼽은 위험이다.
///
/// 그때도 수업이 되게 하는 우회로가 이것이다. 출제를 **파일 한 개**로 만들어
/// AirDrop·USB·이메일로 옮기거나, 짧으면 QR 로 직접 보여 준다. 네트워크가
/// 아예 없어도 된다.
///
/// ## 형식
///
/// 허브가 보내는 것과 **같은 envelope**(AES-GCM)를 쓰고, 세션 키를 번들 안에
/// 함께 담는다.
///
/// ⚠️**그래서 이 파일을 가진 사람은 내용을 볼 수 있다.** 허브 경로는 QR 을 본
/// 사람만 풀 수 있지만 번들은 파일 자체가 열쇠다. 받아쓰기 문제는 수업 중
/// 어차피 읽어 주는 것이라 이 정도가 맞고, 대신 **번들에 답안·학생 정보는
/// 절대 담지 않는다**(출제 방향으로만 흐른다).
class OfflineBundle {
  const OfflineBundle({
    required this.version,
    required this.sessionId,
    required this.keyB64,
    required this.envelope,
    required this.createdAtMs,
    this.title,
  });

  /// 형식 버전. 학생 앱이 모르는 버전이면 **거부한다**(조용히 잘못 읽지 않는다).
  static const currentVersion = 1;

  final int version;
  final String sessionId;

  /// 이 번들을 푸는 대칭 키. 위 주석의 위험을 알고 담는 것이다.
  final String keyB64;

  /// 허브가 보내는 것과 같은 봉투.
  final SyncEnvelope envelope;
  final int createdAtMs;

  /// 교사가 붙이는 이름(`3월 2주 받아쓰기`). 학생 화면에 보인다.
  final String? title;

  Map<String, Object?> toJson() => {
        'v': version,
        'sessionId': sessionId,
        'key': keyB64,
        'env': envelope.toJson(),
        'createdAtMs': createdAtMs,
        if (title != null && title!.isNotEmpty) 'title': title,
      };

  String encode() => jsonEncode(toJson());

  factory OfflineBundle.fromJson(Map<String, Object?> json) {
    final v = (json['v'] as num?)?.toInt() ?? 0;
    if (v != currentVersion) {
      throw FormatException(
        '이 앱이 모르는 문제 파일 형식입니다(v$v). 앱을 최신으로 맞춰 주세요.',
      );
    }
    return OfflineBundle(
      version: v,
      sessionId: json['sessionId']! as String,
      keyB64: json['key']! as String,
      envelope:
          SyncEnvelope.fromJson((json['env']! as Map).cast<String, Object?>()),
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
      title: json['title'] as String?,
    );
  }

  static OfflineBundle decode(String raw) =>
      OfflineBundle.fromJson(jsonDecode(raw) as Map<String, Object?>);

  /// 출제 평문을 번들로 감싼다.
  static Future<OfflineBundle> seal({
    required String sessionId,
    required List<int> plainBytes,
    required int createdAtMs,
    String? title,
  }) async {
    final key = await SyncCrypto.newSessionKey();
    final env = await SyncCrypto.seal(
      sessionKey: key,
      sessionId: sessionId,
      type: SyncMessageTypes.dictationPackage,
      plainBytes: plainBytes,
    );
    return OfflineBundle(
      version: currentVersion,
      sessionId: sessionId,
      keyB64: base64Encode(await SyncCrypto.sessionKeyBytes(key)),
      envelope: env,
      createdAtMs: createdAtMs,
      title: title,
    );
  }

  /// 번들을 풀어 출제 평문을 돌려준다.
  Future<List<int>> open() async {
    final key = SecretKey(base64Decode(keyB64));
    if (envelope.sessionId != sessionId) {
      // 봉투와 겉면이 다르면 손댄 파일이다.
      throw const FormatException('문제 파일이 손상되었습니다.');
    }
    return SyncCrypto.open(sessionKey: key, envelope: envelope);
  }

  /// QR 로 보여도 되는 크기인가.
  ///
  /// QR 은 바이트가 커지면 **눈으로 못 읽을 만큼 촘촘해진다.** 넘으면 파일로
  /// 옮기라고 안내해야 한다 — 화면에 띄워 놓고 안 찍히는 것이 최악이다.
  bool get fitsInQr => encode().length <= maxQrBytes;

  /// 실측 기준으로 잡은 상한. QR 버전 40(약 2953바이트) 을 넘기지 않으면서
  /// 교실 조명·구형 카메라에서도 읽히도록 여유를 뒀다.
  static const maxQrBytes = 1200;
}
