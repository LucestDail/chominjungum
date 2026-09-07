import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:chominjungum/app.dart';
import 'package:chominjungum/domain/app_role.dart';
import 'package:chominjungum/domain/dictation_models.dart';
import 'package:chominjungum/features/teacher/pairing_info_card.dart';
import 'package:chominjungum/features/teacher/teacher_home_screen.dart';
import 'package:chominjungum/providers/app_role_provider.dart';
import 'package:chominjungum/services/dictation_repository.dart';
import 'package:chominjungum/services/local_hub_service.dart';
import 'package:chominjungum/services/local_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangul_core/hangul_core.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sync_protocol/sync_protocol.dart';

/// 교실 한 사이클을 **실기동**으로 통과시킨다.
///
/// 위젯 테스트가 닿지 못하는 것만 여기서 본다 — 자세한 배경은 이 폴더의 README.md.
/// 요약: 교사 화면은 `NetworkInfo` 플러그인에 묶여 위젯 테스트가 아예 불가능했고,
/// 기존 e2e 는 `broadcastEncrypted` 를 직접 불러 **출제 앞단(자모 분해)을 지나가지
/// 않았다**. 그 틈에서 "출제가 원격 서버에 의존" 하는 버그가 107 GREEN 아래 살아 있었다.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await LocalStore.initForApp();
    await LocalStore.open();
    await LocalStore.clearAll();
  });

  tearDown(() async {
    await LocalStore.clearAll();
  });

  testWidgets('교사 허브 기동 → 학생 연결 → 출제 → 채점 제출 → 현황판 → 영속화',
      (tester) async {
    // ── 1. 교사 앱을 실제로 띄운다 (실제 플러그인·실제 소켓) ──────────────
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appRoleProvider.overrideWithValue(AppRole.teacher)],
        child: const ChominjungumApp(role: AppRole.teacher),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(TeacherHomeKeys.startHub), findsOneWidget,
        reason: '교사 화면이 렌더되어야 한다 (위젯 테스트로는 여기까지 오지 못했다)');

    // 시뮬레이터는 Wi-Fi IP 를 못 줄 수 있다. 학생이 같은 프로세스에 있으니 루프백을 쓴다.
    await tester.enterText(find.byKey(TeacherHomeKeys.hostOverride), '127.0.0.1');
    await tester.pumpAndSettle();

    // ── 2. 허브 기동 — 실제 WebSocket 서버 바인딩 ────────────────────────
    await tester.tap(find.byKey(TeacherHomeKeys.startHub));
    // 소켓 I/O 는 runAsync 안에서만 진행된다.
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
    await tester.pumpAndSettle();

    final card = tester.widget<PairingInfoCard>(find.byType(PairingInfoCard));
    final pairing = card.pairing;
    expect(pairing.hubHost, '127.0.0.1');
    expect(pairing.hubPort, SyncDefaults.hubPort);

    // ── 3. B1: 세션 키는 기본으로 감춰져 있다 ────────────────────────────
    final encoded = pairing.encode();
    expect(find.text(encoded), findsNothing,
        reason: '세션 키가 든 문자열이 기본 노출되면 안 된다');
    await tester.tap(find.text('연결 정보 보기 (QR을 못 읽을 때)'));
    await tester.pumpAndSettle();
    expect(find.text(encoded), findsOneWidget);
    await tester.tap(find.text('숨기기'));
    await tester.pumpAndSettle();
    expect(find.text(encoded), findsNothing);

    // ── 4. 학생 연결 — 실제 WS + AES-GCM ────────────────────────────────
    final keyBytes = Uint8List.fromList(base64Decode(pairing.publicKeyB64));
    final studentKey = await SyncCrypto.sessionKeyFromBytes(keyBytes);
    final received = Completer<DictationPackage>();
    late StudentHubClient student;

    await tester.runAsync(() async {
      student = await StudentHubClient.connect(
        wsUrl: 'ws://${pairing.hubHost}:${pairing.hubPort}/',
        sessionKey: studentKey,
        sessionId: pairing.sessionId,
        onMessage: (plain, env) {
          final pkg = tryDecodeDictationPackage(plain, env);
          if (pkg != null && !received.isCompleted) received.complete(pkg);
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();

    // ── 5. ★출제 — 화면 버튼을 실제로 누른다 ─────────────────────────────
    // 여기가 핵심이다. 이 경로가 DictationComposer(기기 내 분해)를 지나야 하고,
    // **인터넷이 없어도 성공해야 한다**. 원격 jammin 호출로 되돌아가면 여기서 깨진다.
    const sentence = '학교에 갔다.';
    await tester.enterText(find.byKey(TeacherHomeKeys.sentence), sentence);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(TeacherHomeKeys.broadcast));
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
    await tester.pumpAndSettle();

    expect(find.textContaining('출제 실패'), findsNothing,
        reason: '출제가 실패하면 안 된다 — 원격 서버에 의존하고 있지 않은지 확인할 것');

    final pkg = await tester.runAsync(
      () => received.future.timeout(const Duration(seconds: 10)),
    );
    expect(pkg, isNotNull);
    final item = pkg!.items.single;
    expect(item.expectedText, sentence);

    // 서버 없이 분해된 결과가 jammin 스키마와 같아야 한다.
    final glyphs = HangulUtil.glyphsFromAddWordResponse(item.expectedGlyphsJson);
    expect(glyphs, hasLength(sentence.length));

    // ── 6. 학생이 채점하고 제출한다 ──────────────────────────────────────
    const wrongAnswer = '학교에 갔다,'; // 마지막 글자만 틀림
    final score = DictationCompare.score(
      expected: item.expectedText,
      actual: wrongAnswer,
    );
    final attempt = AttemptSubmitPayload(
      attemptId: 'itest-attempt-1',
      itemId: item.id,
      expectedText: item.expectedText,
      rawAnswer: wrongAnswer,
      deviceBindingId: 'itest-device-A',
      correctCount: score.correctCount,
      totalCount: score.totalCount,
      submittedAtMs: DateTime.now().millisecondsSinceEpoch,
      sessionId: pairing.sessionId,
    );

    await tester.runAsync(() async {
      await student.sendEncrypted(
        type: SyncMessageTypes.attemptSubmit,
        plainBytes: utf8.encode(jsonEncode(attempt.toJson())),
      );
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    await tester.pumpAndSettle();

    // ── 7. 교사 현황판에 반영된다 ────────────────────────────────────────
    expect(find.textContaining('제출 1건'), findsOneWidget,
        reason: '교사 화면이 제출을 받아 표시해야 한다');

    // ── 8. Hive 실파일에 남는다 ─────────────────────────────────────────
    const repo = DictationRepository();
    expect(repo.attempts(), isNotEmpty, reason: '답안이 디스크에 남아야 한다');
    expect(repo.loadPackage()?.items.single.expectedText, sentence);

    await tester.runAsync(() => student.close());
  });
}
