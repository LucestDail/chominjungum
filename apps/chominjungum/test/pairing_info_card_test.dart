import 'package:chominjungum/features/teacher/pairing_info_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_protocol/sync_protocol.dart';

/// 페어링 문자열에는 세션 키가 들어 있다. 교실에서 교사 화면이 프로젝터에 뜨거나
/// 학생이 어깨너머로 보는 일이 흔하므로, **기본으로 보이면 안 된다**.
void main() {
  SessionPairingPayload payloadOf({String sessionId = 's1'}) {
    return SessionPairingPayload(
      sessionId: sessionId,
      hostDisplayName: '교사',
      // 실제로는 대칭 세션 키가 여기 담긴다 (이름과 다르다)
      publicKeyB64: 'VEVTVF9TRUNSRVRfS0VZ',
      createdAtMs: 1000,
      ttlSeconds: 600,
      hubPort: 8765,
      hubHost: '192.168.0.10',
    );
  }

  Future<void> pump(WidgetTester tester, SessionPairingPayload payload) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PairingInfoCard(
              key: ValueKey(payload.sessionId),
              pairing: payload,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('기본 화면에는 세션 키가 보이지 않는다', (tester) async {
    final payload = payloadOf();
    await pump(tester, payload);

    expect(find.text(payload.encode()), findsNothing);
    expect(find.textContaining('VEVTVF9TRUNSRVRfS0VZ'), findsNothing);
    // 대신 펼치는 수단을 안내한다
    expect(find.textContaining('연결 정보 보기'), findsOneWidget);
  });

  testWidgets('QR 은 그대로 보인다 — 학생이 스캔해야 한다', (tester) async {
    await pump(tester, payloadOf());
    expect(find.text('학생 스캔용 QR'), findsOneWidget);
  });

  testWidgets('교사가 펼치면 문자열이 보이고 경고가 함께 뜬다', (tester) async {
    final payload = payloadOf();
    await pump(tester, payload);

    await tester.tap(find.textContaining('연결 정보 보기'));
    await tester.pump();

    expect(find.text(payload.encode()), findsOneWidget);
    expect(find.textContaining('접속 키가 들어 있습니다'), findsOneWidget);
  });

  testWidgets('다시 숨길 수 있다', (tester) async {
    final payload = payloadOf();
    await pump(tester, payload);

    await tester.tap(find.textContaining('연결 정보 보기'));
    await tester.pump();
    await tester.tap(find.text('숨기기'));
    await tester.pump();

    expect(find.text(payload.encode()), findsNothing);
  });

  testWidgets('새 수업을 열면 펼친 상태가 따라오지 않는다', (tester) async {
    await pump(tester, payloadOf(sessionId: 's1'));
    await tester.tap(find.textContaining('연결 정보 보기'));
    await tester.pump();
    expect(find.textContaining('접속 키가 들어 있습니다'), findsOneWidget);

    // 허브를 다시 시작하면 세션 id 가 바뀐다 → key 가 달라져 새 상태
    await pump(tester, payloadOf(sessionId: 's2'));

    expect(find.textContaining('접속 키가 들어 있습니다'), findsNothing);
    expect(find.textContaining('연결 정보 보기'), findsOneWidget);
  });
}
