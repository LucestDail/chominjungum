import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/glyph_ink.dart';

/// 자모 자산 83개의 잉크 분포를 **호스트에서** 재어 기준선을 만든다.
///
/// 이 파일 하나로는 "자산이 비지 않았다" 정도만 본다. 진짜 목적은 같은 측정을
/// 실기기에서 돌려(`integration_test/glyph_device_render_test.dart`) **두 결과를
/// 대조**하는 것이다 — 기기에서만 나타나는 폰트 누락·SVG 미지원이 여기서 걸린다.
///
///   flutter test test/glyph_ink_host_test.dart       # 기준선 생성
///   tool/compare_glyph_ink.py                        # 기기 결과와 대조
void main() {
  // 특수문자·숫자 자산은 `<text>` + KCC 도담도담체로 그린다. 골든 환경은 폰트를
  // 자동으로 올려 주지 않으므로 직접 올려야 판정이 유효하다.
  setUpAll(() async {
    final bytes = File('assets/fonts/KCCDodamdodamR.ttf').readAsBytesSync();
    final loader = FontLoader('KCCDodamdodamR')
      ..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  });

  testWidgets('자산 83개 전부 렌더된다 — 잉크 기준선 기록', (tester) async {
    final results = <GlyphInk>[];
    for (final code in GlyphAssetCatalog.all) {
      results.add(await measureAsset(tester, code));
    }

    expect(results.length, 83, reason: '자산 수가 바뀌었다');

    // 빈 자산은 하나도 없어야 한다.
    // ⚠️공백(32)조차 원본은 **원고지 칸 그림**이다(빈 파일이 아니다) — 실제로
    // 그렇게 확인했다. 그러니 "안 그려짐"은 전부 렌더 실패로 봐야 한다.
    final blanks = results.where((r) => r.isBlank).map((r) => r.code).toList();
    expect(blanks, isEmpty, reason: '렌더되지 않은 자산이 있다: $blanks');

    final out = File('build/glyph_ink_host.json');
    out.parent.createSync(recursive: true);
    out.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'canvas': kInkCanvas,
        'threshold': kInkThreshold,
        'glyphs': results.map((r) => r.toJson()).toList(),
      }),
    );
  });

  testWidgets('배치가 웹과 같다 — 부위별 잉크 경계 고정', (tester) async {
    // ## 왜 이렇게까지 재나
    //
    // 앱은 배치를 **자산에 구워** 넣고(변환기가 `translate`/`scale` 을 박는다),
    // 웹은 **CSS 로** 배치한다(`hangul-metrics.ts`). 규칙이 두 곳에 따로 적혀
    // 있으니 한쪽만 바뀌면 조용히 갈라진다 — 2026-09-09 에 실제로 갈라져 있었다.
    //
    // 웹의 배치 사각형(상자 623.6 기준, `hangul-metrics.ts`):
    //   초성 (0, 0, 419.5, 218.3)   → 우 0.6727 · 하 0.3501
    //   중성 (0, 0, 623.6, 400.9)   → 우 1.0000 · 하 0.6429
    //   종성 (0, 402.5, 623.6, 221.1) → 상 0.6455 · 하 1.0000
    //
    // 자산에는 부위 테두리(점선 안내선)가 함께 들어 있어 **잉크 경계가 곧 배치
    // 사각형**이다. 선 굵기만큼 안쪽으로 들어오므로 그만큼 여유를 준다.
    const tol = 0.025; // 안내선 stroke 두께 몫

    void near(double got, double want, String what) {
      expect(
        (got - want).abs(),
        lessThan(tol),
        reason: '$what: 기대 ${want.toStringAsFixed(4)} · 실측 ${got.toStringAsFixed(4)}',
      );
    }

    // 부위마다 양 끝 자모를 본다 — 모두 같은 캔버스라 경계가 같아야 한다.
    for (final code in [4352, 4370]) {
      final r = await measureAsset(tester, code);
      near(r.left, 0.0, '초성 $code 좌');
      near(r.top, 0.0, '초성 $code 상');
      near(r.right, 419.5 / 623.6, '초성 $code 우');
      near(r.bottom, 218.3 / 623.6, '초성 $code 하');
    }
    for (final code in [4449, 4469]) {
      final r = await measureAsset(tester, code);
      near(r.top, 0.0, '중성 $code 상');
      near(r.right, 1.0, '중성 $code 우');
      near(r.bottom, 400.9 / 623.6, '중성 $code 하');
    }
    for (final code in [4520, 4546]) {
      final r = await measureAsset(tester, code);
      near(r.top, (623.6 - 221.1) / 623.6, '종성 $code 상');
      near(r.bottom, 1.0, '종성 $code 하');
      near(r.right, 1.0, '종성 $code 우');
    }
  });
}
