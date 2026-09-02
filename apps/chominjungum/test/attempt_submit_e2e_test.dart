import 'package:chominjungum/domain/dictation_models.dart';
import 'package:chominjungum/features/dictation/attempt_submit_sheet.dart';
import 'package:chominjungum/providers/dictation_providers.dart';
import 'package:chominjungum/services/local_hub_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_protocol/sync_protocol.dart';

/// 학생 UI에서 채점 후 제출한 답안이 교사 허브까지 도달하는지 확인.
void main() {
  testWidgets('채점 → 제출 탭 → 교사 허브가 답안을 수신한다', (tester) async {
    final received = <AttemptSubmitPayload>[];
    late final LocalHubService hub;
    late final StudentHubClient client;

    // 실제 WebSocket I/O는 fake-async 밖(runAsync)에서만 진행된다.
    await tester.runAsync(() async {
      hub = LocalHubService(
        sessionId: 'sheet-session',
        sessionKey: await SyncCrypto.newSessionKey(),
        port: 0,
        onAttempt: received.add,
      );
      await hub.start();
      client = await StudentHubClient.connect(
        wsUrl: 'ws://127.0.0.1:${hub.boundPort}/',
        sessionKey: hub.sessionKey,
        sessionId: hub.sessionId,
        onMessage: (_, __) {},
      );
    });
    addTearDown(() async {
      await client.close();
      await hub.stop();
    });

    final package = DictationPackage(
      version: DictationPackage.currentVersion,
      items: [DictationItem.fromExpectedText('안녕하세요')],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          studentHubClientProvider.overrideWith((ref) => client),
          deviceBindingIdProvider.overrideWith((ref) async => 'device-widget'),
        ],
        child: MaterialApp(
          home: Scaffold(body: AttemptSubmitSheet(package: package)),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '안녕하세오');
    await tester.tap(find.widgetWithText(FilledButton, '채점'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, '선생님께 제출'));
    await tester.pump();

    await tester.runAsync(() async {
      for (var i = 0; received.isEmpty && i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pumpAndSettle();

    expect(received, hasLength(1));
    expect(received.single.rawAnswer, '안녕하세오');
    expect(received.single.expectedText, '안녕하세요');
    expect(received.single.correctCount, 4);
    expect(received.single.totalCount, 5);
    expect(received.single.deviceBindingId, 'device-widget');

    expect(find.text('제출 완료'), findsOneWidget);
    expect(find.textContaining('선생님께 제출했습니다'), findsOneWidget);
  });
}
