import 'dart:convert';

import 'package:sync_protocol/sync_protocol.dart';
import 'package:test/test.dart';

/// 오프라인 번들 — 허브 없이 출제를 옮긴다.
///
/// 교실 Wi-Fi 가 단말 간 통신을 막으면(클라이언트 격리) 허브 경로가 통째로
/// 막힌다. 그때의 우회로라 **네트워크를 전혀 타지 않는 것**이 요점이다.
void main() {
  const plain = '{"version":1,"items":[]}';

  Future<OfflineBundle> make({String? title}) => OfflineBundle.seal(
        sessionId: 's1',
        plainBytes: utf8.encode(plain),
        createdAtMs: 1000,
        title: title,
      );

  test('봉인 → 문자열 → 해제 왕복', () async {
    final b = await make(title: '3월 2주');
    final decoded = OfflineBundle.decode(b.encode());
    expect(decoded.sessionId, 's1');
    expect(decoded.title, '3월 2주');
    expect(utf8.decode(await decoded.open()), plain);
  });

  test('제목이 없으면 키를 싣지 않는다', () async {
    final b = await make();
    expect(b.toJson().containsKey('title'), isFalse);
  });

  test('🔴모르는 버전은 거부한다 — 조용히 잘못 읽지 않는다', () {
    final json = jsonDecode('{"v":99,"sessionId":"s","key":"k",'
        '"env":{},"createdAtMs":0}') as Map<String, Object?>;
    expect(() => OfflineBundle.fromJson(json), throwsFormatException);
  });

  test('🔴봉투와 겉면의 세션이 다르면 손댄 파일이다', () async {
    final b = await make();
    final tampered = OfflineBundle(
      version: OfflineBundle.currentVersion,
      sessionId: 'other', // 겉면만 바꿔치기
      keyB64: b.keyB64,
      envelope: b.envelope,
      createdAtMs: b.createdAtMs,
    );
    expect(tampered.open(), throwsA(isA<FormatException>()));
  });

  test('🔴암호문을 건드리면 복호화가 실패한다', () async {
    final b = await make();
    final broken = OfflineBundle(
      version: b.version,
      sessionId: b.sessionId,
      keyB64: b.keyB64,
      envelope: SyncEnvelope(
        sessionId: b.envelope.sessionId,
        nonceB64: b.envelope.nonceB64,
        cipherTextB64: base64Encode(
          base64Decode(b.envelope.cipherTextB64)..[0] ^= 0xFF,
        ),
        macB64: b.envelope.macB64,
        type: b.envelope.type,
      ),
      createdAtMs: b.createdAtMs,
    );
    expect(broken.open(), throwsA(isA<Object>()));
  });

  group('QR 로 보여도 되는가', () {
    test('짧은 출제는 QR 에 들어간다', () async {
      final b = await make();
      expect(b.fitsInQr, isTrue);
    });

    test('★긴 출제는 QR 을 포기하고 파일로 안내해야 한다', () async {
      // 열 문항쯤 되는 실제 출제 크기.
      final big = await OfflineBundle.seal(
        sessionId: 's1',
        plainBytes: utf8.encode('x' * 4000),
        createdAtMs: 0,
      );
      expect(big.fitsInQr, isFalse,
          reason: '화면에 띄워 놓고 안 찍히는 것이 최악이다');
    });
  });
}
