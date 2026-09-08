import 'dart:convert';

import 'package:chominjungum/domain/dictation_models.dart';
import 'package:chominjungum/services/dictation_composer.dart';
import 'package:chominjungum/services/local_hub_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sync_protocol/sync_protocol.dart';
import 'package:uuid/uuid.dart';

/// **실기기 학생 ↔ 시뮬레이터 허브** 왕복을 사람과 함께 검증한다.
///
/// 자동 왕복(교사 화면 UI 포함)은 `classroom_roundtrip_test.dart` 가 덮는다.
/// 이 파일은 그것으로 알 수 없는 **실기기 전용 3가지**만 본다:
///
///   1. iOS **로컬 네트워크 권한 프롬프트** (시뮬레이터에는 이 제약이 아예 없다)
///   2. **카메라 QR 스캔** (시뮬레이터에 카메라가 없다)
///   3. **기기 간 LAN 도달성** — 다른 기기가 실제로 이 허브에 닿는가
///
/// ## 왜 교사 화면 위젯을 쓰지 않나 (2026-09-08 에 네 번 헛돌고 배운 것)
///
/// 처음엔 `TeacherHomeScreen` 을 띄우고 **화면 텍스트("접속 학생 N명")로 판정**했는데,
/// 실기기가 실제로 붙었는데도(아이폰에 "허브에 연결됨"이 떴는데도) 감지하지 못했다:
///
///   - 교사 화면 body 가 `ListView` 라 **화면 밖 위젯은 빌드되지 않는다** —
///     제출 현황판이 트리에 아예 없어서 finder 가 0개를 봤다
///   - 그래서 매 폴링마다 드래그했더니 **화면이 계속 튀고**(사용자가 "무한 깜빡인다"),
///     내려가 있는 동안 **QR 이 화면 밖으로 밀려 스캔할 수 없었다**
///   - 20초에 한 번만 내려갔다 오게 고쳐도 `drag` 가 리스트를 제대로 밀지 못했다
///
/// ⇒ **화면을 거치지 말고 허브를 직접 소유한다.** 접속·제출을 콜백으로 받으므로
/// 판정이 위젯 트리·스크롤과 무관해지고, QR 은 페이로드만 있으면 직접 그릴 수 있다.
/// 교사 화면 UI 검증은 어차피 다른 테스트의 몫이다.
///
/// ## 쓰는 법
///
/// ```bash
/// # 학생 앱(기본 타깃)을 실기기에 미리 설치
/// flutter build ios --release && xcrun devicectl device install app --device <UDID> \
///   build/ios/iphoneos/Runner.app
/// # ⚠️ device 빌드 뒤 simulator 빌드를 하려면 flutter clean + rm -rf ios/Pods 가 필요하다
/// #    (섞이면 objective_c.framework dlopen 실패로 앱이 흰 화면으로 죽는다)
///
/// flutter test integration_test/live_device_hub_test.dart -d <시뮬레이터 UDID>
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const waitForStudent = Duration(minutes: 6);
  const waitForSubmit = Duration(minutes: 6);
  const sentence = '학교에 갔다.';

  testWidgets('실기기 학생이 QR 로 붙어 출제·제출까지 왕복한다', (tester) async {
    // ── 허브를 테스트가 직접 소유한다 (판정이 콜백으로 확실해진다) ──────────
    var clientCount = 0;
    AttemptSubmitPayload? received;

    final sessionId = const Uuid().v4();
    final key = await SyncCrypto.newSessionKey();
    final hub = LocalHubService(
      sessionId: sessionId,
      sessionKey: key,
      port: SyncDefaults.hubPort,
      onAttempt: (a) {
        received = a;
        debugPrint('[live] 제출 수신: "${a.rawAnswer}" '
            '(${a.correctCount}/${a.totalCount}글자 · 기기 ${a.deviceBindingId})');
      },
      onClientCountChanged: (n) {
        clientCount = n;
        debugPrint('[live] 접속 수 변화: $n');
      },
    );
    await tester.runAsync(hub.start);
    addTearDown(() async => hub.stop());

    final wifiIp = await tester.runAsync(() => NetworkInfo().getWifiIP());
    expect(wifiIp, isNotNull, reason: 'Wi-Fi IP 를 못 얻으면 학생이 붙을 주소가 없다');

    final payload = SessionPairingPayload(
      sessionId: sessionId,
      hostDisplayName: '교사',
      publicKeyB64: base64Encode(await SyncCrypto.sessionKeyBytes(key)),
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ttlSeconds: 900,
      hubPort: SyncDefaults.hubPort,
      hubHost: wifiIp,
    );

    // ── QR 만 그린다 (스크롤이 없으니 계속 보인다) ────────────────────────
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('학생 기기로 스캔하세요',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                QrImageView(
                  data: payload.encode(),
                  version: QrVersions.auto,
                  size: 300,
                  backgroundColor: Colors.white,
                ),
                const SizedBox(height: 16),
                Text('ws://${payload.hubHost}:${payload.hubPort}/'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    debugPrint('');
    debugPrint('═══════════════════════════════════════════════════════════');
    debugPrint('[live] 허브 가동 · ws://${payload.hubHost}:${payload.hubPort}/');
    debugPrint('[live] 시뮬레이터에 QR 이 떠 있습니다 — 실기기 학생 앱으로 스캔하세요.');
    debugPrint('[live] QR 이 안 읽히면 아래를 "페이로드 붙여넣기"에 넣으세요:');
    debugPrint(payload.encode());
    debugPrint('═══════════════════════════════════════════════════════════');

    /// 화면을 계속 펌프하면서(=UI 가 멈추지 않게) 조건을 기다린다.
    /// 판정은 **콜백 변수**로 하므로 위젯 트리·스크롤과 무관하다.
    Future<bool> waitFor(bool Function() done, Duration limit, String label) async {
      final sw = Stopwatch()..start();
      var lastLog = -1;
      while (sw.elapsed < limit) {
        if (done()) return true;
        await tester.pump(const Duration(milliseconds: 200));
        // 실제 소켓 I/O 는 runAsync 안에서만 진행된다.
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 400)));
        final sec = sw.elapsed.inSeconds;
        if (sec ~/ 20 != lastLog) {
          lastLog = sec ~/ 20;
          debugPrint('[live] $label — ${sec}s / ${limit.inSeconds}s');
        }
      }
      return done();
    }

    // ── 학생 접속 ─────────────────────────────────────────────────────────
    final connected =
        await waitFor(() => clientCount > 0, waitForStudent, '학생 접속 대기');
    expect(connected, isTrue,
        reason: '학생이 붙지 않았다. 확인할 것: ①실기기가 같은 Wi-Fi 인가 '
            '②그 Wi-Fi 가 단말 간 통신을 허용하는가(클라이언트 격리면 안 된다 — '
            'docs/REHEARSAL.md §1) ③로컬 네트워크 권한을 허용했는가 '
            '④hubHost(${payload.hubHost})가 실기기에서 도달 가능한가');
    debugPrint('[live] ✅ 접속 확인 ($clientCount) — QR 스캔 · iOS 로컬 네트워크 권한 · '
        '기기 간 LAN 도달성 통과');

    // ── 출제 (기기 내 분해 — 네트워크를 타지 않는다) ───────────────────────
    final item = DictationComposer.compose(sentence);
    final pkg =
        DictationPackage(version: DictationPackage.currentVersion, items: [item]);
    await tester.runAsync(() => hub.broadcastEncrypted(
          type: SyncMessageTypes.dictationPackage,
          plainBytes: pkg.toUtf8Bytes(),
        ));
    debugPrint('[live] 출제 전송: "$sentence" — 실기기가 받아쓰기 화면으로 열려야 한다');
    debugPrint('[live]   이제 실기기에서: 앱바 ✅ → 답 입력 → 채점 → "선생님께 제출"');

    // ── 제출 수신 ─────────────────────────────────────────────────────────
    final got = await waitFor(() => received != null, waitForSubmit, '학생 제출 대기');
    expect(got, isTrue,
        reason: '제출이 오지 않았다. 실기기에서 채점 후 "선생님께 제출"을 눌렀는지, '
            '허브 연결이 유지됐는지 확인할 것');

    final a = received!;
    debugPrint('[live] ✅ 왕복 완료 — 답안 "${a.rawAnswer}" '
        '${a.correctCount}/${a.totalCount}글자 (${a.scorePercent}점)');
    expect(a.expectedText, sentence, reason: '학생이 받은 문항이 교사가 낸 것과 같아야 한다');
    expect(a.rawAnswer, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 15)));
}
