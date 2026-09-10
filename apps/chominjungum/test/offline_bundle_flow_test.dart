import 'dart:convert';

import 'package:chominjungum/domain/dictation_models.dart';
import 'package:chominjungum/services/dictation_composer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangul_core/hangul_core.dart';
import 'package:sync_protocol/sync_protocol.dart';

/// 허브 없이 출제를 옮기는 경로 — 교실 Wi-Fi 가 단말 간 통신을 막을 때의 우회로.
///
/// 프로토콜 자체는 `sync_protocol` 테스트가 본다. 여기서는 **앱의 출제가
/// 그대로 실려서 돌아오는지**를 본다(가리기 규칙 포함).
void main() {
  test('출제 → 번들 → 학생이 여는 것까지 왕복', () async {
    final rule = const HideRule(mode: HideMode.jong).selectAll();
    final pkg = DictationPackage(
      version: DictationPackage.currentVersion,
      items: DictationComposer.composeAll('학교\n친구', hideRule: rule),
    );

    final bundle = await OfflineBundle.seal(
      sessionId: 's-offline',
      plainBytes: pkg.toUtf8Bytes(),
      createdAtMs: 1,
      title: '2문항',
    );

    // 학생 기기에서: 문자열만 받아 연다. **네트워크를 전혀 쓰지 않는다.**
    final decoded = OfflineBundle.decode(bundle.encode());
    final back = DictationPackage.fromJson(
      (jsonDecode(utf8.decode(await decoded.open())) as Map)
          .cast<String, Object?>(),
    );

    expect(back.items, hasLength(2));
    expect(back.items.first.expectedText, '학교');
    expect(back.items.first.hideRule.mode, HideMode.jong,
        reason: '가리기 규칙도 함께 건너가야 같은 학습지가 된다');
  });

  test('실제 크기의 열 문항 출제는 QR 을 넘어선다 — 파일로 안내해야 한다', () async {
    final pkg = DictationPackage(
      version: DictationPackage.currentVersion,
      items: DictationComposer.composeAll(
        List.generate(10, (i) => '문장연습$i').join('\n'),
      ),
    );
    final bundle = await OfflineBundle.seal(
      sessionId: 's',
      plainBytes: pkg.toUtf8Bytes(),
      createdAtMs: 0,
    );
    expect(bundle.fitsInQr, isFalse,
        reason: '열 문항이면 QR 로 안 된다는 것을 화면이 알려줘야 한다');
  });

  test('한 문항이면 QR 로도 된다', () async {
    final pkg = DictationPackage(
      version: DictationPackage.currentVersion,
      items: [DictationComposer.compose('나비')],
    );
    final bundle = await OfflineBundle.seal(
      sessionId: 's',
      plainBytes: pkg.toUtf8Bytes(),
      createdAtMs: 0,
    );
    expect(bundle.fitsInQr, isTrue);
  });
}
