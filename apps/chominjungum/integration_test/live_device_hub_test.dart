import 'package:chominjungum/app.dart';
import 'package:chominjungum/domain/app_role.dart';
import 'package:chominjungum/features/teacher/pairing_info_card.dart';
import 'package:chominjungum/features/teacher/teacher_home_screen.dart';
import 'package:chominjungum/providers/app_role_provider.dart';
import 'package:chominjungum/services/local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// **실기기 학생 ↔ 시뮬레이터 교사** 왕복을 사람과 함께 검증한다.
///
/// 자동 왕복은 `classroom_roundtrip_test.dart` 가 이미 덮는다. 이 파일은 그것으로
/// 알 수 없는 **실기기 전용 3가지**를 확인하기 위한 것이다:
///
///   1. iOS **로컬 네트워크 권한 프롬프트** (시뮬레이터에는 이 제약이 아예 없다)
///   2. **카메라 QR 스캔** (시뮬레이터에 카메라가 없다)
///   3. **기기 간 LAN 도달성** — `NetworkInfo` 가 준 IP 가 다른 기기에서 실제로 열리는가
///      (자동 테스트는 루프백을 쓴다)
///
/// ## 쓰는 법
///
/// ```bash
/// # 학생 앱(기본 타깃)을 실기기에 미리 설치해 둔다
/// flutter build ios --release && xcrun devicectl device install app --device <UDID> \
///   build/ios/iphoneos/Runner.app
/// # ⚠️ device 빌드 뒤에 simulator 빌드를 하려면 flutter clean + rm -rf ios/Pods 가 필요하다
/// #    (섞이면 objective_c.framework dlopen 실패로 앱이 흰 화면으로 죽는다)
///
/// flutter test integration_test/live_device_hub_test.dart -d <시뮬레이터 UDID>
/// ```
///
/// 실행하면 콘솔에 페어링 페이로드를 찍고 **최대 6분간 허브를 유지**한다.
/// 그동안 사람이 실기기에서:
///   ① 학생 앱 실행 → ② 시뮬레이터 화면의 QR 을 카메라로 스캔
///   → ③ 로컬 네트워크 권한 "허용" → ④ 문제를 받으면 답 입력·채점·제출
///
/// 학생이 붙으면 자동으로 출제하고, 제출이 오면 검증하고 끝난다.
/// 아무도 붙지 않으면 왜 실패했는지(=LAN 도달 불가 가능성) 안내하며 실패한다.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const waitForStudent = Duration(minutes: 6);
  const waitForSubmit = Duration(minutes: 6);
  const sentence = '학교에 갔다.';

  setUpAll(() async {
    await LocalStore.initForApp();
    await LocalStore.open();
  });

  /// 조건이 참이 될 때까지 화면을 계속 펌프하며 기다린다.
  /// (실기기의 사람 조작을 기다리는 동안 UI 가 멈추면 안 된다)
  Future<bool> pumpUntil(
    WidgetTester tester,
    bool Function() done,
    Duration limit, {
    String? progressLabel,
  }) async {
    final sw = Stopwatch()..start();
    var lastLog = 0;
    while (sw.elapsed < limit) {
      if (done()) return true;
      await tester.pump(const Duration(milliseconds: 200));
      // 실제 소켓 I/O 는 runAsync 안에서만 진행된다.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      final sec = sw.elapsed.inSeconds;
      if (progressLabel != null && sec ~/ 15 != lastLog) {
        lastLog = sec ~/ 15;
        debugPrint('[live] $progressLabel — ${sec}s 경과 (제한 ${limit.inSeconds}s)');
      }
    }
    return done();
  }

  testWidgets('실기기 학생이 QR 로 붙어 출제·제출까지 왕복한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appRoleProvider.overrideWithValue(AppRole.teacher)],
        child: const ChominjungumApp(role: AppRole.teacher),
      ),
    );
    await tester.pumpAndSettle();

    // ── 허브 기동 ─────────────────────────────────────────────────────────
    final startHub = find.byKey(TeacherHomeKeys.startHub);
    await tester.ensureVisible(startHub);
    await tester.pumpAndSettle();
    await tester.tap(startHub);
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 3)));
    await tester.pumpAndSettle();

    final cards = find.byType(PairingInfoCard);
    expect(cards, findsOneWidget,
        reason: '허브가 시작되고 QR 카드가 떠야 한다. IP 를 못 잡으면 카드가 안 뜬다 — '
            '시뮬레이터가 맥의 Wi-Fi IP 를 보는지 확인할 것');
    final pairing = tester.widget<PairingInfoCard>(cards).pairing;

    debugPrint('');
    debugPrint('═══════════════════════════════════════════════════════════');
    debugPrint('[live] 허브가 떴다. 이제 실기기에서 조작하세요.');
    debugPrint('[live]   허브 주소 : ws://${pairing.hubHost}:${pairing.hubPort}/');
    debugPrint('[live]   세션 ID   : ${pairing.sessionId}');
    debugPrint('[live] QR 이 시뮬레이터 화면에 떠 있습니다 — 실기기 학생 앱으로 스캔하세요.');
    debugPrint('[live] QR 이 안 읽히면 아래 문자열을 학생 화면 "페이로드 붙여넣기"에 넣으세요:');
    debugPrint(pairing.encode());
    debugPrint('═══════════════════════════════════════════════════════════');
    debugPrint('');

    // ── 학생 접속 대기 ────────────────────────────────────────────────────
    final connected = await pumpUntil(
      tester,
      () => find.textContaining('접속 학생 1명').evaluate().isNotEmpty ||
          find.textContaining('접속 학생 2명').evaluate().isNotEmpty,
      waitForStudent,
      progressLabel: '학생 접속 대기',
    );
    expect(connected, isTrue,
        reason: '학생이 붙지 않았다. 확인할 것: ①실기기가 같은 Wi-Fi 인가 '
            '②그 Wi-Fi 가 단말 간 통신을 허용하는가(클라이언트 격리면 안 된다 — '
            'docs/REHEARSAL.md §1) ③로컬 네트워크 권한을 허용했는가 '
            '④QR 의 hubHost(${pairing.hubHost})가 실기기에서 도달 가능한 주소인가');
    debugPrint('[live] ✅ 학생 접속 확인 — 기기 간 LAN 도달성 통과');

    // ── 출제 ──────────────────────────────────────────────────────────────
    final sentenceField = find.byKey(TeacherHomeKeys.sentence);
    await tester.ensureVisible(sentenceField);
    await tester.pumpAndSettle();
    await tester.enterText(sentenceField, sentence);
    await tester.pumpAndSettle();

    final broadcast = find.byKey(TeacherHomeKeys.broadcast);
    await tester.ensureVisible(broadcast);
    await tester.pumpAndSettle();
    await tester.tap(broadcast);
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
    await tester.pumpAndSettle();

    expect(find.textContaining('출제 실패'), findsNothing,
        reason: '출제는 기기에서 분해한다 — 네트워크 오류가 뜨면 회귀다');
    debugPrint('[live] ✅ 출제 전송("$sentence") — 실기기 학생 화면이 받아쓰기로 열려야 한다');
    debugPrint('[live] 이제 실기기에서: 답 입력 → 채점 → "선생님께 제출"');

    // ── 제출 대기 ─────────────────────────────────────────────────────────
    final submitted = await pumpUntil(
      tester,
      () => find.textContaining('제출 1건').evaluate().isNotEmpty ||
          find.textContaining('제출 2건').evaluate().isNotEmpty,
      waitForSubmit,
      progressLabel: '학생 제출 대기',
    );
    expect(submitted, isTrue,
        reason: '제출이 오지 않았다. 실기기에서 채점 후 "선생님께 제출"을 눌렀는지, '
            '허브 연결이 유지됐는지 확인할 것');
    debugPrint('[live] ✅ 제출 수신 — 왕복 완료');

    // 교사 화면이 실제로 무엇을 보여주는지 콘솔에 남긴다(현장 기록용).
    for (final t in find.byType(Text).evaluate()) {
      final w = t.widget as Text;
      final d = w.data;
      if (d != null && (d.contains('접속 학생') || d.contains('글자'))) {
        debugPrint('[live] 화면: $d');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
