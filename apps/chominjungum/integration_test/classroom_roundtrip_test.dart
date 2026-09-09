import 'dart:async';
import 'dart:convert';

import 'package:chominjungum/app.dart';
import 'package:chominjungum/domain/app_role.dart';
import 'package:chominjungum/domain/dictation_models.dart';
import 'package:chominjungum/features/teacher/pairing_info_card.dart';
import 'package:chominjungum/features/teacher/teacher_home_screen.dart';
import 'package:chominjungum/providers/app_role_provider.dart';
import 'package:chominjungum/services/dictation_repository.dart';
import 'package:chominjungum/services/local_hub_service.dart';
import 'package:chominjungum/services/local_store.dart';
import 'package:chominjungum/widgets/jammin/jammin_status_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangul_core/hangul_core.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sync_protocol/sync_protocol.dart';
import 'package:uuid/uuid.dart';

/// 교실 한 사이클을 **실기동**으로 통과시킨다.
///
/// 위젯 테스트가 닿지 못하는 것만 여기서 본다 — 자세한 배경은 이 폴더의 README.md.
/// 요약: 교사 화면은 `NetworkInfo` 플러그인에 묶여 위젯 테스트가 아예 불가능했고,
/// 기존 e2e 는 `broadcastEncrypted` 를 직접 불러 **출제 앞단(자모 분해)을 지나가지
/// 않았다**. 그 틈에서 "출제가 원격 서버에 의존" 하는 버그가 107 GREEN 아래 살아 있었다.
/// `--dart-define` 으로 넘기는 실서버 정보. 비어 있으면 업싱크 단계를 건너뛴다.
const upsyncUrl = String.fromEnvironment('UPSYNC_URL');
const upsyncToken = String.fromEnvironment('UPSYNC_TOKEN');
const upsyncClassroom = String.fromEnvironment('UPSYNC_CLASSROOM');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// 교사 화면은 긴 스크롤 화면이다. 화면 밖 위젯을 `tap` 하면 **예외 없이 빗나가서**
  /// "눌렀는데 아무 일도 안 일어난" 것처럼 보인다(첫 실행에서 정확히 이걸 겪었다 —
  /// "연결 정보 보기"를 펼치자 내용이 길어져 "숨기기" 버튼이 화면 밖으로 밀렸다).
  /// 그래서 모든 조작 전에 먼저 스크롤로 끌어온다.
  Future<void> tapVisible(WidgetTester t, Finder f) async {
    await t.ensureVisible(f);
    await t.pumpAndSettle();
    await t.tap(f);
    await t.pumpAndSettle();
  }

  Future<void> typeVisible(WidgetTester t, Finder f, String text) async {
    await t.ensureVisible(f);
    await t.pumpAndSettle();
    await t.enterText(f, text);
    await t.pumpAndSettle();
  }

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
    await typeVisible(tester, find.byKey(TeacherHomeKeys.hostOverride), '127.0.0.1');

    // ── 2. 허브 기동 — 실제 WebSocket 서버 바인딩 ────────────────────────
    await tapVisible(tester, find.byKey(TeacherHomeKeys.startHub));
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
    await tapVisible(tester, find.text('연결 정보 보기 (QR을 못 읽을 때)'));
    expect(find.text(encoded), findsOneWidget);
    await tapVisible(tester, find.text('숨기기'));
    expect(find.text(encoded), findsNothing);

    // ── 4. 학생 연결 — 페어링 v2 (QR 에는 교사 **공개키**만 있다) ────────
    // v1 에서는 여기서 `publicKeyB64` 를 대칭키로 읽었다. v2 는 접속 후 `hello` 를
    // 보내고 교사가 감싸 보낸 세션 키를 받아야 비로소 메시지를 읽을 수 있다.
    final received = Completer<DictationPackage>();
    final keyReady = Completer<void>();
    late StudentHubClient student;

    await tester.runAsync(() async {
      student = await StudentHubClient.connect(
        wsUrl: 'ws://${pairing.hubHost}:${pairing.hubPort}/',
        sessionId: pairing.sessionId,
        hostPublicKeyB64: pairing.publicKeyB64,
        onSessionKeyReady: () {
          if (!keyReady.isCompleted) keyReady.complete();
        },
        onMessage: (plain, env) {
          final pkg = tryDecodeDictationPackage(plain, env);
          if (pkg != null && !received.isCompleted) received.complete(pkg);
        },
      );
      // 핸드셰이크가 끝나야 출제를 받을 수 있다.
      await keyReady.future.timeout(const Duration(seconds: 10));
    });
    await tester.pumpAndSettle();
    expect(student.isReady, isTrue,
        reason: 'v2 핸드셰이크(hello → session.key)가 끝나야 한다');

    // ── 5. ★출제 — 화면 버튼을 실제로 누른다 (여러 문항) ─────────────────
    // 여기가 핵심이다. 이 경로가 DictationComposer(기기 내 분해)를 지나야 하고,
    // **인터넷이 없어도 성공해야 한다**. 원격 jammin 호출로 되돌아가면 여기서 깨진다.
    //
    // 2026-09-08 부터 **한 줄이 한 문항**이다 — 받아쓰기 수업은 보통 열 문항을 낸다.
    // 한 문항만 내면 그 변경이 깨져도 모르므로 여기서 여러 줄을 넣는다.
    const sentences = ['학교에 갔다.', '꽃이 피었습니다', '값을 읽고 답을 썼다'];
    const sentence = '학교에 갔다.'; // 아래 단계들이 쓰는 대표 문항
    await typeVisible(
        tester, find.byKey(TeacherHomeKeys.sentence), sentences.join('\n'));
    await tapVisible(tester, find.byKey(TeacherHomeKeys.broadcast));
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
    await tester.pumpAndSettle();

    expect(find.textContaining('출제 실패'), findsNothing,
        reason: '출제가 실패하면 안 된다 — 원격 서버에 의존하고 있지 않은지 확인할 것');
    expect(find.textContaining('${sentences.length}문항'), findsWidgets,
        reason: '몇 문항을 보냈는지 교사에게 알려야 한다');

    final pkg = await tester.runAsync(
      () => received.future.timeout(const Duration(seconds: 10)),
    );
    expect(pkg, isNotNull);
    expect(pkg!.items.map((i) => i.expectedText), sentences,
        reason: '학생이 받은 문항 목록이 교사가 낸 것과 순서까지 같아야 한다');
    final item = pkg.items.first;
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
      // ⚠️서버는 attemptId·sessionId·classroomId 를 **UUID 로 검증**한다
      // (`SyncDtos.SyncAttempt.attemptId` 가 `UUID` 타입). 아무 문자열을 넣으면
      // 인증을 통과하고도 400 이 된다 — 실제로 여기서 한 번 걸렸다.
      // 앱은 `const Uuid().v4()` 를 쓰므로 같은 형식을 쓴다.
      attemptId: const Uuid().v4(),
      itemId: item.id,
      expectedText: item.expectedText,
      rawAnswer: wrongAnswer,
      deviceBindingId: 'itest-device-A',
      // 2026-09-08 추가 — 교사 화면이 "학생 a3f2…" 대신 이름으로 보여야 한다.
      studentName: '홍길동',
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
    expect(find.textContaining('홍길동'), findsWidgets,
        reason: '이름을 보낸 학생은 기기 ID 가 아니라 이름으로 보여야 한다');

    // ── 8. Hive 실파일에 남는다 ─────────────────────────────────────────
    const repo = DictationRepository();
    expect(repo.attempts(), isNotEmpty, reason: '답안이 디스크에 남아야 한다');
    expect(repo.loadPackage()?.items.map((i) => i.expectedText), sentences,
        reason: '받은 문항 전부가 디스크에 남아야 한다(재시작 후 이어서 푼다)');

    // ── 8.5 학생이 실제로 보는 받아쓰기 화면까지 들어간다 ────────────────
    // 이 화면을 방문하지 않아서 **오버플로 3건을 놓쳤다**(칸 32px·앱바·툴바).
    // 오버플로는 여기서 예외로 잡히므로, 경로를 지나가는 것만으로 방어가 된다.
    await tapVisible(tester, find.text('이 기기에서 미리보기'));
    expect(tester.takeException(), isNull, reason: '받아쓰기 화면이 넘치면 안 된다');
    for (final t in sentences) {
      expect(find.textContaining(t), findsWidgets,
          reason: '출제한 문항 "$t" 이 학생 화면에 보여야 한다');
    }
    // 뒤로 나와 교사 화면으로 복귀 (다음 단계가 교사 화면을 쓴다)
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // ── 9. (선택) 실제 서버로 업싱크 ─────────────────────────────────────
    // 서버 정보를 주면 앱의 업싱크 경로를 **끝까지** 태운다. 안 주면 건너뛴다
    // (기본 실행이 외부 서버에 의존하지 않도록).
    //
    //   flutter test integration_test -d <기기> \
    //     --dart-define=UPSYNC_URL=http://127.0.0.1:18100 \
    //     --dart-define=UPSYNC_TOKEN=<교사 JWT> \
    //     --dart-define=UPSYNC_CLASSROOM=<학급 UUID>
    //
    // ⚠️게이트웨이(nginx)는 외부 요청에 Basic 을 요구하고 앱은 그 자격을 못 보낸다.
    //   그래서 검증은 SSH 터널로 서버에 직결한다:
    //   `ssh -f -N -L 18100:127.0.0.1:8100 homelab25`
    if (upsyncUrl.isNotEmpty && upsyncToken.isNotEmpty && upsyncClassroom.isNotEmpty) {
      await typeVisible(tester, find.byKey(TeacherHomeKeys.serverUrl), upsyncUrl);
      await typeVisible(tester, find.byKey(TeacherHomeKeys.serverToken), upsyncToken);
      await typeVisible(tester, find.byKey(TeacherHomeKeys.classroomId), upsyncClassroom);
      await tapVisible(tester, find.byKey(TeacherHomeKeys.uploadNow));
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 5)));
      await tester.pumpAndSettle();

      // 실패했을 때 원인을 바로 알 수 있게 화면 상태를 함께 남긴다.
      final banners = tester
          .widgetList<JamminStatusBanner>(find.byType(JamminStatusBanner))
          .map((b) => b.message)
          .toList();
      final uploadBtn = tester
          .widget<FilledButton>(find.byKey(TeacherHomeKeys.uploadNow));
      debugPrint('[itest] 업싱크 배너=$banners · 버튼활성=${uploadBtn.onPressed != null}');

      expect(find.textContaining('업로드 완료'), findsOneWidget,
          reason: '업싱크가 성공해야 한다. 화면 배너=$banners · '
              '업로드버튼활성=${uploadBtn.onPressed != null}. '
              '401 이면 토큰, nginx 401 이면 Authorization 헤더를 다시 쓰는지 확인할 것');
      expect(find.textContaining('신규 1건'), findsOneWidget,
          reason: '이 세션의 제출 1건이 신규로 집계되어야 한다');
    }

    await tester.runAsync(() => student.close());
  });
}
