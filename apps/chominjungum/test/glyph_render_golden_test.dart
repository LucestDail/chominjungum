import 'dart:io';

import 'package:chominjungum/widgets/hangul_glyph_cell.dart';
import 'package:chominjungum/widgets/hangul_worksheet_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangul_core/hangul_core.dart';

/// 자모 칸 렌더를 **이미지로 고정**한다.
///
/// 자모 자산은 jammin 원본에서 변환해 만든다(`tool/build_hangul_assets.py`).
/// 좌표를 원본 그대로 두고 전체 상자 좌표계로 옮기기만 하므로 렌더가 원본과 같아야
/// 하는데, 그것을 눈이 아니라 **파일로** 붙들어 둔다 — 자산을 다시 만들거나
/// 배치 수치를 건드리면 이 골든이 어긋난다.
///
/// 갱신: `flutter test --update-goldens test/glyph_render_golden_test.dart`
/// (갱신했으면 **결과 이미지를 반드시 눈으로 확인**하고 커밋할 것)
void main() {
  // 골든 환경은 기본적으로 폰트를 로드하지 않는다. 특수문자·숫자 자산은 원본이
  // `<text>` + KCC 도담도담체로 그리므로, 폰트를 실제로 올려야 판정이 유효하다.
  setUpAll(() async {
    final bytes = File('assets/fonts/KCCDodamdodamR.ttf').readAsBytesSync();
    final loader = FontLoader('KCCDodamdodamR')
      ..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  });

  Widget cell(String text) {
    final glyphs = HangulUtil.hangulSplit(text);
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final g in glyphs)
                HangulGlyphCell(
                  glyph: g,
                  profile: HangulWorksheetProfile.editor.scaledToCellWidth(120),
                ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('초·중·종이 모두 있는 글자 — 값', (tester) async {
    await tester.pumpWidget(cell('값'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Row).last,
      matchesGoldenFile('goldens/glyph_gab.png'),
    );
  });

  testWidgets('받침 없는 글자 · 여러 자모 — 학교에', (tester) async {
    await tester.pumpWidget(cell('학교에'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Row).last,
      matchesGoldenFile('goldens/glyph_hakgyoe.png'),
    );
  });

  testWidgets('특수문자·숫자 — 3개.', (tester) async {
    await tester.pumpWidget(cell('3개.'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Row).last,
      matchesGoldenFile('goldens/glyph_special.png'),
    );
  });
}
