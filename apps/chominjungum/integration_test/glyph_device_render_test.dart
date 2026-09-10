import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/glyph_ink.dart';

/// 자모 자산 83개가 **실기기에서** 원본대로 그려지는지 픽셀로 판정한다.
///
/// ## 왜 실기기여야 하나
///
/// 호스트 골든과 시뮬레이터는 맥의 폰트·그래픽 스택을 쓴다. 기기에서만 갈리는 것:
///
///   - 앱 번들에 폰트가 실제로 들어갔는지 (`<text>` 자산이 대체 글리프로 깨진다)
///   - Impeller 가 SVG 의 특정 기능(점선·stroke 단위)을 호스트와 같게 그리는지
///   - 자산이 번들에 누락되지 않았는지 (`pubspec` 의 `assets:` 누락은 호스트에서도
///     잡히지만, 플랫폼별 번들링 사고는 기기에서만 드러난다)
///
/// 그래서 **호스트에서 잰 것과 같은 측정을 기기에서 다시 재고 대조**한다.
/// 사람이 화면을 보는 대신 숫자가 판정한다.
///
/// 실행:
///   flutter test test/glyph_ink_host_test.dart          # 기준선 먼저
///   flutter drive --driver=test_driver/integration_test.dart \
///     --target=integration_test/glyph_device_render_test.dart -d <기기ID>
///   python3 tool/compare_glyph_ink.py
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('자모 자산 83개 실기기 렌더 측정', (tester) async {
    final results = <GlyphInk>[];
    for (final code in GlyphAssetCatalog.all) {
      results.add(await measureAsset(tester, code));
    }

    // 여기서 바로 걸러 낼 수 있는 것: 아무것도 안 그려진 자산.
    // (기기에 자산이 없거나 파서가 죽으면 이렇게 나온다)
    final blanks = results.where((r) => r.isBlank).map((r) => r.code).toList();
    expect(blanks, isEmpty, reason: '기기에서 렌더되지 않은 자산: $blanks');

    binding.reportData = <String, dynamic>{
      'glyph_ink_device': {
        'canvas': kInkCanvas,
        'threshold': kInkThreshold,
        'glyphs': results.map((r) => r.toJson()).toList(),
      },
    };
  });
}
