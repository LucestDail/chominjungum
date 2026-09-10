import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chominjungum/domain/dictation_models.dart';
import 'package:chominjungum/services/ai_consent.dart';
import 'package:chominjungum/services/classroom_board.dart';
import 'package:chominjungum/services/dictation_composer.dart';
import 'package:chominjungum/services/local_hub_service.dart';
import 'package:chominjungum/services/local_store.dart';
import 'package:chominjungum/services/worksheet_pdf.dart';
import 'package:chominjungum/widgets/hangul_writing_cell.dart';
import 'package:chominjungum/widgets/hangul_writing_worksheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sync_protocol/sync_protocol.dart';

/// 2026-09-10 **실기기 검증 이후**에 넣은 6종을 기기에서 태운다.
///
/// ## 왜 따로 있나
///
/// 09-10 에 실기기 왕복을 한 번 통과시킨 뒤에도 작업을 계속했고, 그 뒤에 넣은
/// 것들은 **기기에서 한 번도 안 돌았다**. `new_features_device_test.dart` 는
/// 그 검증 시점까지의 것만 덮는다.
///
/// 여기 있는 여섯은 전부 **호스트 테스트가 원리상 닿지 못하는 층**에 걸린다:
///
/// | 항목 | 호스트에서 못 보는 것 |
/// |---|---|
/// | AI 동의 | `flutter_secure_storage` = 실제 **키체인** |
/// | PDF 출력 | 실제 GPU 래스터(`toImage`)에서 나온 픽셀 |
/// | 학급 현황 | 실제 소켓으로 오는 `student.join` |
/// | 제출 ACK | 실제 소켓 왕복 |
/// | 오프라인 번들 | 실제 플랫폼 암호 구현 |
/// | 획순 지도 | 실제 포인터 이벤트(제스처 아레나) |
///
/// ⚠️**실기기에서는 `flutter drive` 로 돌린다** — `flutter test integration_test`
/// 는 실기기에서 `CONFIGURATION_BUILD_DIR` 타임아웃으로 죽는다(09-10 에 2회 연속).
/// 시뮬레이터에서는 둘 다 되므로 이 차이는 실기기에서만 드러난다.
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

  // ────────────────────────────────────────────────────────────
  // 1. AI 동의 — 실제 키체인
  // ────────────────────────────────────────────────────────────

  testWidgets('AI 키가 실제 키체인에 저장되고, 끄면 정말 지워진다', (tester) async {
    final consent = AiConsent();

    await tester.runAsync(() async {
      // 앞선 실행이 남긴 것이 있으면 판정이 흐려진다.
      await consent.disable();

      expect(await consent.isEnabled(), isFalse, reason: '기본은 꺼짐이어야 한다');
      expect(await consent.apiKey(), isNull);

      await consent.enable('sk-integration-test-key');

      // 여기가 핵심 — 호스트 테스트는 키체인에 못 쓴다.
      expect(await consent.isEnabled(), isTrue);
      expect(await consent.hasKey(), isTrue);
      expect(await consent.apiKey(), 'sk-integration-test-key');

      await consent.disable();

      expect(await consent.isEnabled(), isFalse);
      expect(
        await consent.hasKey(),
        isFalse,
        reason: '끄면 키도 지운다고 동의 문구에 적어 놓았다 — 실제로 지워져야 한다',
      );
      expect(await consent.apiKey(), isNull);
    });
  });

  testWidgets('학생 기기에서는 AI 를 켤 수 없다', (tester) async {
    // UI 로만 가리면 다른 경로가 생겼을 때 샌다(09-10 에 학생 화면에 남아 있던
    // jammin 호출 버튼이 그랬다). 호출 지점에서 막히는지 본다.
    expect(
      () => AiConsentGuard.assertTeacher(isTeacher: false),
      throwsStateError,
    );
    expect(
      () => AiConsentGuard.assertTeacher(isTeacher: true),
      returnsNormally,
    );
  });

  // ────────────────────────────────────────────────────────────
  // 2. PDF — 실제 GPU 래스터
  // ────────────────────────────────────────────────────────────

  testWidgets('실제 화면 픽셀에서 PDF 가 나오고 구조가 성립한다', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: Container(
                width: 200,
                height: 120,
                color: Colors.white,
                alignment: Alignment.center,
                child: const Text('받아쓰기', style: TextStyle(fontSize: 24)),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    late Uint8List pdf;
    late int w;
    late int h;
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      // 실제 GPU 에서 래스터화한다 — 호스트 테스트에는 이 경로가 없다.
      final image = await boundary.toImage(pixelRatio: 2.0);
      final bd = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      w = image.width;
      h = image.height;
      pdf = WorksheetPdf.fromRgba(
        rgba: bd!.buffer.asUint8List(),
        width: w,
        height: h,
        title: 'device test',
      );
      image.dispose();
    });

    expect(w, greaterThan(0));
    expect(h, greaterThan(0));

    // ── 판정을 내 파서에 맡기지 않는다(순환 논증) ──
    // 구조는 바이트로, 압축은 표준 zlib 으로 되돌려 확인한다.

    expect(
      String.fromCharCodes(pdf.take(8)),
      startsWith('%PDF-1.4'),
      reason: 'PDF 헤더가 아니다',
    );
    final tail = String.fromCharCodes(pdf.skip(pdf.length - 64));
    expect(tail.trimRight(), endsWith('%%EOF'));

    // startxref 가 가리키는 자리에 실제로 xref 표가 있어야 한다.
    // 오프셋을 틀리게 쓰면 뷰어가 조용히 복구해 버려서 눈으로는 안 보인다.
    final text = latin1.decode(pdf, allowInvalid: true);
    final sx = text.lastIndexOf('startxref');
    expect(sx, greaterThan(0));
    final offset = int.parse(
      text.substring(sx + 'startxref'.length).trim().split('\n').first.trim(),
    );
    expect(
      text.substring(offset, offset + 4),
      'xref',
      reason: 'startxref 오프셋이 xref 표를 안 가리킨다',
    );

    // 이미지 스트림이 실제로 풀리고, 정확히 w*h*3 바이트여야 한다.
    final sMark = text.indexOf('stream\n', text.indexOf('/Subtype /Image'));
    final eMark = text.indexOf('\nendstream', sMark);
    final deflated = pdf.sublist(sMark + 'stream\n'.length, eMark);
    final inflated = ZLibDecoder().convert(deflated);
    expect(
      inflated.length,
      w * h * 3,
      reason: '압축을 풀면 RGB 픽셀 수와 정확히 같아야 한다',
    );

    // 흰 배경 위에 합성했으므로 완전 검정으로 도배되면 알파 처리가 깨진 것이다.
    final allBlack = inflated.every((b) => b == 0);
    expect(allBlack, isFalse, reason: '알파 합성이 깨져 전부 검게 나왔다');
  });

  // ────────────────────────────────────────────────────────────
  // 3. 학급 현황 — 실제 소켓의 student.join
  // ────────────────────────────────────────────────────────────

  testWidgets('학생이 제출 전에도 실제 소켓으로 명단에 올라온다', (tester) async {
    final sessionId = 'late-${DateTime.now().millisecondsSinceEpoch}';
    final key = await SyncCrypto.newSessionKey();

    StudentJoinPayload? joined;
    final hub = LocalHubService(
      sessionId: sessionId,
      sessionKey: key,
      port: 0,
      onStudentJoined: (s) => joined ??= s,
    );

    await tester.runAsync(() async {
      await hub.start();
      final client = await StudentHubClient.connect(
        wsUrl: 'ws://127.0.0.1:${hub.boundPort}/',
        sessionKey: key,
        sessionId: sessionId,
        onMessage: (_, __) {},
      );
      await client.announce(
        deviceBindingId: 'device-alpha',
        displayName: '김철수',
      );
      for (var i = 0; i < 40 && joined == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await client.close();
      await hub.stop();
    });

    expect(joined, isNotNull, reason: '학생 접속 통지가 실제 소켓으로 안 왔다');
    expect(joined!.deviceBindingId, 'device-alpha');
    expect(joined!.displayName, '김철수');

    // 그 통지가 현황판까지 이어지는가 — 제출이 0건이어도 보여야 한다.
    final items = DictationComposer.composeAll('학교\n친구');
    final board = ClassroomBoard.of(
      attempts: const [],
      items: items,
      connectedDeviceIds: {joined!.deviceBindingId},
      knownNames: {joined!.deviceBindingId: joined!.displayName!},
    );

    expect(board.students, hasLength(1));
    expect(board.students.first.displayName, '김철수');
    expect(board.students.first.submitted, 0);
    expect(board.itemCount, 2);
    expect(
      board.submittedCount,
      0,
      reason: '아직 아무도 안 냈는데 제출 수가 올라갔다',
    );
  });

  // ────────────────────────────────────────────────────────────
  // 4. 제출 ACK — 실제 소켓 왕복
  // ────────────────────────────────────────────────────────────

  testWidgets('제출이 실제 소켓에서 회신을 받는다', (tester) async {
    final sessionId = 'ack-${DateTime.now().millisecondsSinceEpoch}';
    final key = await SyncCrypto.newSessionKey();

    AttemptSubmitPayload? got;
    final hub = LocalHubService(
      sessionId: sessionId,
      sessionKey: key,
      port: 0,
      onAttempt: (a) => got ??= a,
    );

    var acked = false;
    await tester.runAsync(() async {
      await hub.start();
      final client = await StudentHubClient.connect(
        wsUrl: 'ws://127.0.0.1:${hub.boundPort}/',
        sessionKey: key,
        sessionId: sessionId,
        onMessage: (_, __) {},
      );

      const attemptId = 'attempt-real-socket';
      acked = await client.sendWithAck(
        type: SyncMessageTypes.attemptSubmit,
        attemptId: attemptId,
        plainBytes: utf8.encode(
          const AttemptSubmitPayload(
            attemptId: attemptId,
            itemId: 'item-1',
            expectedText: '학교',
            rawAnswer: '학교',
            deviceBindingId: 'device-alpha',
            correctCount: 2,
            totalCount: 2,
            submittedAtMs: 1,
          ).encode(),
        ),
      );

      await client.close();
      await hub.stop();
    });

    expect(
      acked,
      isTrue,
      reason: '회신을 못 받았다 — 09-10 에 화면은 "제출됨"인데 조용히 사라지던 자리',
    );
    expect(got, isNotNull, reason: '허브가 제출을 못 받았다');
    expect(got!.attemptId, 'attempt-real-socket');
  });

  // ────────────────────────────────────────────────────────────
  // 5. 오프라인 번들 — 실제 플랫폼 암호
  // ────────────────────────────────────────────────────────────

  testWidgets('오프라인 번들이 기기에서 봉인·해제되고, QR 에는 안 들어간다', (tester) async {
    final items = DictationComposer.composeAll('학교\n친구\n나비');
    final pkg = DictationPackage(
      version: DictationPackage.currentVersion,
      items: items,
    );
    final plain = pkg.toUtf8Bytes();

    late OfflineBundle bundle;
    late List<int> opened;
    await tester.runAsync(() async {
      bundle = await OfflineBundle.seal(
        sessionId: 'bundle-dev',
        plainBytes: plain,
        createdAtMs: 1725900000000,
        title: '1학기 3회차',
      );
      // 파일로 나갔다 들어오는 경로를 그대로 탄다.
      opened = await OfflineBundle.decode(bundle.encode()).open();
    });

    expect(opened, equals(plain), reason: '봉인·해제 왕복에서 내용이 달라졌다');

    final restored = DictationPackage.fromJson(
      jsonDecode(utf8.decode(opened)) as Map<String, Object?>,
    );
    expect(restored.items, hasLength(3));
    expect(restored.items.map((i) => i.expectedText), ['학교', '친구', '나비']);

    // 손댄 파일은 거부해야 한다.
    final tampered = OfflineBundle.decode(bundle.encode()).toJson()
      ..['sessionId'] = 'other-session';
    await tester.runAsync(() async {
      await expectLater(
        OfflineBundle.fromJson(tampered).open(),
        throwsA(isA<FormatException>()),
      );
    });

    // ── QR 경계는 **3음절** 이다 (2026-09-11 실측) ──
    //
    //   2음절 1문항  898B → 들어간다
    //   4음절 1문항 1438B → 넘는다
    //   3문항       2262B · 10문항 11974B → 한참 넘는다   (상한 1200B)
    //
    // 즉 QR 로 되는 것은 **짧은 한 단어**뿐이고, 실제 받아쓰기(보통 10문항)는
    // 절대 안 된다. 무게의 70% 가 `expectedGlyphsJson` 인데, 그것은 학생 기기가
    // 로컬로 다시 분해할 수 있는 값이다(골든 벡터가 세 이식본의 동치를 강제).
    // 빼면 10문항이 962B 로 들어간다 — 다만 그건 프로토콜 변경이다.
    //
    // 지금 사용자에게 깨지지는 않는다: 번들 QR 화면 자체가 없고(`QrImageView`
    // 는 세션 페어링 전용), 교사 화면은 파일·클립보드로 떨구며 "QR 로는 너무
    // 커서" 를 덧붙인다. 그래서 **고치지 않고 사실을 못박아 둔다.**
    // 페이로드를 슬림화하면 이 단언이 깨지면서 결정이 바뀐 것을 알려 준다.
    expect(
      bundle.fitsInQr,
      isFalse,
      reason: '번들이 QR 에 들어갔다 — 페이로드가 슬림해졌다면 '
          'maxQrBytes 와 이 주석, 교사 화면 안내 문구를 함께 재검토할 것 '
          '(현재 ${bundle.encode().length}B / 상한 ${OfflineBundle.maxQrBytes}B)',
    );
  });

  // ────────────────────────────────────────────────────────────
  // 6. 획순 지도 — 실제 포인터 이벤트
  // ────────────────────────────────────────────────────────────

  testWidgets('거꾸로 그은 획을 실제 제스처에서 지적한다', (tester) async {
    final advice = <String?>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 360,
            child: HangulWritingWorksheet(
              text: '가',
              onStrokeAdvice: advice.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // ⚠️획은 **칸(`HangulWritingCell`) 안에서만** 받는다. 학습지 전체 사각형을
    // 기준으로 잡으면 칸 밖에 떨어져 아무 일도 안 일어난다(처음에 그랬다).
    final cell = find.byType(HangulWritingCell).first;
    expect(cell, findsOneWidget);
    final box = tester.getRect(cell);

    // 가로획을 **오른쪽에서 왼쪽으로** 긋는다 — 지도 대상이다.
    // 위젯 테스트가 아니라 실제 제스처 아레나를 지나간다.
    final y = box.center.dy;
    final from = Offset(box.right - box.width * 0.2, y);
    final to = Offset(box.left + box.width * 0.2, y);

    final g = await tester.startGesture(from);
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(Offset.lerp(from, to, i / 10)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle();

    final said = advice.whereType<String>().toList();
    expect(
      said,
      isNotEmpty,
      reason: '거꾸로 그었는데 아무 말도 안 했다 — 제스처가 캔버스에 안 닿았을 수 있다',
    );
    expect(said.last, contains('왼쪽에서 오른쪽'));
  });
}
