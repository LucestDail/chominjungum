import 'package:chominjungum/domain/dictation_models.dart';
import 'package:chominjungum/services/dictation_composer.dart';
import 'package:chominjungum/widgets/hangul_glyph_cell.dart';
import 'package:chominjungum/widgets/hangul_worksheet.dart';
import 'package:chominjungum/widgets/hangul_worksheet_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangul_core/hangul_core.dart';

/// 자모 가리기가 **출제 → 전송 → 렌더**까지 살아서 가는지.
///
/// 규칙 자체(`HideRule`)의 정확성은 `hangul_core` 쪽 테스트가 웹 TS 와 대조해
/// 잡는다. 여기서는 **배선**을 본다 — 규칙을 만들어도 학생 화면에서 칸이 비지
/// 않으면 기능이 없는 것과 같다.
void main() {
  group('출제에 규칙이 실린다', () {
    test('compose 가 규칙을 문항에 담는다', () {
      final rule = const HideRule(mode: HideMode.jong).selectAll();
      final item = DictationComposer.compose('학교', hideRule: rule);
      expect(item.hideRule.mode, HideMode.jong);
      expect(item.hideRule.hasEffect, isTrue);
    });

    test('여러 문항 모두에 같은 규칙이 걸린다', () {
      final rule = const HideRule(mode: HideMode.cho).selectAll();
      final items = DictationComposer.composeAll('학교\n친구', hideRule: rule);
      expect(items, hasLength(2));
      expect(items.every((i) => i.hideRule.mode == HideMode.cho), isTrue);
    });

    test('기본값은 안 가림', () {
      expect(DictationComposer.compose('학교').hideRule.hasEffect, isFalse);
    });
  });

  group('전송 왕복 — 학생 기기가 같은 규칙을 받는다', () {
    test('DictationPackage JSON 왕복', () {
      final rule = const HideRule(mode: HideMode.ja).toggle('4352_4520', true);
      final pkg = DictationPackage(
        version: DictationPackage.currentVersion,
        items: [DictationComposer.compose('학교', hideRule: rule)],
      );

      final back = DictationPackage.fromJson(
        Map<String, Object?>.from(pkg.toJson()),
      );
      expect(back.items.single.hideRule, rule);
    });

    test('안 가리면 JSON 에 키가 없다 — 옛 학생 앱이 모르는 키를 안 받는다', () {
      final item = DictationComposer.compose('학교');
      expect(item.toJson().containsKey('hideRule'), isFalse);
    });

    test('가리기가 있으면 키가 실린다', () {
      final rule = const HideRule(mode: HideMode.jong).selectAll();
      final json = DictationComposer.compose('학교', hideRule: rule).toJson();
      expect(json['hideRule'], isA<Map>());
    });
  });

  group('렌더 — 가려진 자모는 그려지지 않는다', () {
    /// 셀 안에 실제로 올라간 자산 경로를 센다. 가려지면 그 SVG 가 사라진다.
    List<String> assetsIn(WidgetTester tester) => tester
        .widgetList<SvgPicture>(find.byType(SvgPicture))
        .map((w) => w.bytesLoader)
        .whereType<SvgAssetLoader>()
        .map((l) => l.assetName)
        .toList();

    Future<void> pumpCell(WidgetTester tester, HideRule rule) async {
      // 값 = 초성 ᄀ4352 · 중성 ᅡ4449 · 종성 ᆹ4537
      final glyph = HangulUtil.hangulSplit('값').first;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: HangulGlyphCell(
                glyph: glyph,
                profile: HangulWorksheetProfile.editor.scaledToCellWidth(120),
                hidden: rule.partsOf(glyph),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('안 가리면 초·중·종 셋 다 그려진다', (tester) async {
      await pumpCell(tester, HideRule.empty);
      final a = assetsIn(tester);
      expect(a, contains('assets/hangul/4352.svg'));
      expect(a, contains('assets/hangul/4449.svg'));
      expect(a, contains('assets/hangul/4537.svg'));
    });

    testWidgets('종성을 가리면 종성만 사라진다', (tester) async {
      await pumpCell(tester, const HideRule(mode: HideMode.jong).selectAll());
      final a = assetsIn(tester);
      expect(a, contains('assets/hangul/4352.svg'), reason: '초성은 남아야 한다');
      expect(a, contains('assets/hangul/4449.svg'), reason: '중성은 남아야 한다');
      expect(a, isNot(contains('assets/hangul/4537.svg')));
    });

    testWidgets('자음 모드는 초성·종성이 함께 사라진다', (tester) async {
      await pumpCell(tester, const HideRule(mode: HideMode.ja).selectAll());
      final a = assetsIn(tester);
      expect(a, isNot(contains('assets/hangul/4352.svg')));
      expect(a, isNot(contains('assets/hangul/4537.svg')));
      expect(a, contains('assets/hangul/4449.svg'), reason: '중성은 남는다');
    });

    testWidgets('원고지 격자는 가려도 남는다 — 쓸 칸이 보여야 한다', (tester) async {
      await pumpCell(tester, const HideRule(mode: HideMode.ja).selectAll());
      expect(assetsIn(tester), contains('assets/hangul/000000.svg'));
    });

    testWidgets('워크시트 전체에도 규칙이 걸린다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HangulWorksheet(
              text: '값',
              showGlyphGuides: true,
              hideRule: const HideRule(mode: HideMode.jong).selectAll(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(assetsIn(tester), isNot(contains('assets/hangul/4537.svg')));
    });
  });
}
