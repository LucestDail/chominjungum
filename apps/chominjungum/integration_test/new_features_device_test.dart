import 'dart:convert';

import 'package:chominjungum/domain/dictation_models.dart';
import 'package:chominjungum/services/dictation_composer.dart';
import 'package:chominjungum/services/dictation_repository.dart';
import 'package:chominjungum/services/dictation_speaker.dart';
import 'package:chominjungum/services/glyph_strokes.dart';
import 'package:chominjungum/services/local_hub_service.dart';
import 'package:chominjungum/services/local_store.dart';
import 'package:chominjungum/services/mistake_analysis.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangul_core/hangul_core.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sync_protocol/sync_protocol.dart';

/// 2026-09-10 추가분을 **실기기에서** 태운다.
///
/// ## 왜 필요한가
///
/// 09-07 에 자동 테스트 107개가 전부 통과하는데도 실환경 버그 3건이 살아 있었다.
/// 위젯 테스트는 플러그인·자산 번들·실제 소켓을 지나가지 않는다. 오늘 넣은 것 중
/// 그 경로에 걸리는 것:
///
///   - **`flutter_tts` 는 새 플러그인이다** — iOS 파드가 실제로 붙었는지는
///     기기에서만 안다(시뮬레이터도 아니고 실기기 번들에서)
///   - **획순 파서는 자산을 `rootBundle` 로 읽는다** — 파일시스템이 아니라
///     번들에서 읽히는지는 기기에서만 확인된다
///   - **가리기 규칙은 암호화 왕복을 타고** 학생 기기로 간다
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

  testWidgets('TTS 플러그인이 실기기에 실제로 붙어 있다', (tester) async {
    // 엔진이 없으면 `DictationSpeaker` 가 조용히 꺼지도록 만들어 두었다.
    // 그 방어가 **실기기에서도 꺼지지 않는지** = 파드가 붙었는지를 본다.
    final speaker = DictationSpeaker();
    await tester.runAsync(() async {
      await speaker.speak('가나다', rate: DictationSpeaker.defaultRate);
      await speaker.stop();
    });
    expect(
      speaker.isAvailable,
      isTrue,
      reason: 'TTS 가 실기기에서 꺼졌다 — iOS 파드가 안 붙었을 수 있다 '
          '(pod install / flutter clean 확인)',
    );
    await speaker.dispose();
  });

  testWidgets('획순 자산을 앱 번들에서 읽는다', (tester) async {
    // 테스트에서는 파일시스템으로 읽었지만, 앱은 `rootBundle` 을 쓴다.
    // `pubspec` 의 assets 선언이 빠지면 여기서만 드러난다.
    final loader = GlyphStrokeLoader();
    late GlyphStrokes? g;
    await tester.runAsync(() async {
      g = await loader.load(4352); // ㄱ
    });
    expect(g, isNotNull, reason: '번들에서 자모 자산을 못 읽었다');
    expect(g!.letter, 'ㄱ');
    expect(g!.strokes, [
      [0, 1],
    ], reason: 'ㄱ 은 선분 2개가 1획');
    expect(g!.isKnownOrder, isTrue);

    // 획순을 모른다고 판정해야 하는 자모도 기기에서 같게 나오는지.
    late GlyphStrokes? wi;
    await tester.runAsync(() async {
      wi = await loader.load(4465); // ㅟ — 자산에 선분이 모자라다
    });
    expect(wi!.isKnownOrder, isFalse);
  });

  testWidgets('가리기 규칙이 암호화 왕복을 타고 학생에게 도착한다', (tester) async {
    final sessionId = 'dev-${DateTime.now().millisecondsSinceEpoch}';
    final key = await SyncCrypto.newSessionKey();

    final hub = LocalHubService(
      sessionId: sessionId,
      sessionKey: key,
      port: 0, // 임의 포트 — 리허설 중인 허브와 부딪히지 않게
    );

    DictationPackage? received;
    await tester.runAsync(() async {
      await hub.start();
      final client = await StudentHubClient.connect(
        wsUrl: 'ws://127.0.0.1:${hub.boundPort}/',
        sessionKey: key,
        sessionId: sessionId,
        onMessage: (plain, env) {
          received ??= tryDecodeDictationPackage(plain, env);
        },
      );

      // 종성만 가려 출제한다.
      final rule = const HideRule(mode: HideMode.jong).selectAll();
      final pkg = DictationPackage(
        version: DictationPackage.currentVersion,
        items: DictationComposer.composeAll('학교\n친구', hideRule: rule),
      );
      await hub.broadcastEncrypted(
        type: SyncMessageTypes.dictationPackage,
        plainBytes: pkg.toUtf8Bytes(),
      );

      // 실제 소켓이라 도착까지 기다린다.
      for (var i = 0; i < 40 && received == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await client.close();
      await hub.stop();
    });

    expect(received, isNotNull, reason: '학생이 출제를 못 받았다');
    expect(received!.items, hasLength(2));

    final rule = received!.items.first.hideRule;
    expect(rule.mode, HideMode.jong);
    expect(rule.hasEffect, isTrue);

    // 실제로 가려지는지 — "학" 의 종성 ㄱ 이 빠져야 한다.
    final hak = HangulUtil.hangulSplit('학').first;
    expect(rule.partsOf(hak).jong, isTrue);
    expect(rule.partsOf(hak).cho, isFalse, reason: '초성은 남아야 한다');
  });

  testWidgets('오답 노트가 실제 Hive 저장분에서 계산된다', (tester) async {
    final repo = DictationRepository();
    final item = DictationComposer.compose('값');

    await tester.runAsync(() async {
      await repo.savePackage(
        DictationPackage(
          version: DictationPackage.currentVersion,
          items: [item],
        ),
      );
      for (var i = 0; i < 3; i++) {
        await repo.saveReceivedAttempt(
          attemptId: 'dev-attempt-$i',
          itemId: item.id,
          deviceBindingId: 'dev',
          rawAnswer: '갑',
          correctCount: 0,
          totalCount: 1,
          submittedAtMs: i,
          inputKind: 'keyboard',
          matchesJson: jsonEncode([
            {'i': 0, 'ok': false},
          ]),
        );
      }
    });

    // 메모리가 아니라 **디스크에 쓰인 것**을 다시 읽어 계산한다.
    final analysis = MistakeAnalysis.of(
      attempts: repo.attempts(),
      items: repo.loadItems(),
    );

    expect(analysis.gradedAttempts, 3);
    expect(analysis.jamo, isNotEmpty, reason: '취약 자모가 안 나왔다');
    expect(
      analysis.jamo.map((w) => w.code),
      contains(4537),
      reason: '겹받침 ㅄ 이 잡혀야 한다',
    );
    expect(analysis.syllables.first.wroteInstead, contains('갑'));

    // 오답 노트 → 가리기 학습지 연결까지.
    final rule = analysis.toHideRule();
    expect(rule.hasEffect, isTrue);
    expect(rule.codes.every((c) => isHidableInMode(c, rule.mode)), isTrue);
  });
}
