import 'package:chominjungum/widgets/hangul_writing_worksheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 받아쓰기 화면이 **좁은 화면에서 넘치지 않는지** 본다.
///
/// 2026-09-07 시뮬레이터에서 오버플로 3건이 실제로 발생하고 있었다:
/// 문항 칸(32px)·앱바·툴바(1.4px). 특히 **칸이 잘리면 학생이 그 칸에 답을 쓸 수 없어
/// 미관 문제가 아니라 기능 장애**였다. 원인은 `cellW = (maxW/lineBreakCount).clamp(60,140)` —
/// 좁은 화면에서 하한 60이 끌어올려 `칸수 × 60 > maxW` 가 됐다.
///
/// 오버플로는 위젯 테스트에서 예외로 잡히므로, 여기서 잠근다.
/// (그동안 이 화면에 위젯 테스트가 없어서 아무도 못 봤다.)
void main() {
  /// 실제로 쓰이는 기기 폭들. 논리 픽셀 = physicalSize / devicePixelRatio.
  const sizes = <String, Size>{
    'iPhone SE (가장 좁음)': Size(750, 1334),
    'iPhone 13/14': Size(1170, 2532),
    'iPhone 17 Pro': Size(1206, 2622),
    'iPhone 17 Pro Max': Size(1320, 2868),
  };

  /// 글자 수를 늘려 가며 — 교사는 긴 문장도 낸다.
  const sentences = <String>[
    '안녕하세요', // 5
    '강아지와고양이', // 7  ← 실측에서 32px 넘쳤던 문장
    '학교에 갔다.', // 7 (공백·구두점 포함)
    '값을 읽고 답을 썼다', // 10
    '오늘은 참 좋은 날입니다.', // 13
  ];

  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(
          body: SafeArea(child: SingleChildScrollView(child: child)),
        ),
      );

  group('받아쓰기 칸이 화면을 넘지 않는다', () {
    for (final entry in sizes.entries) {
      for (final sentence in sentences) {
        testWidgets('${entry.key} · "$sentence"', (tester) async {
          tester.view.physicalSize = entry.value;
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.reset);

          // 오버플로가 있으면 이 pump 안에서 예외가 나 테스트가 실패한다.
          await tester.pumpWidget(
            wrap(HangulWritingWorksheet(text: sentence, showGlyphGuides: false)),
          );
          await tester.pump();

          expect(tester.takeException(), isNull,
              reason: '칸이 화면을 넘으면 학생이 그 칸에 답을 쓸 수 없다');
        });
      }
    }
  });

  group('하단 도구 모음이 넘치지 않고 라벨을 유지한다', () {
    for (final entry in sizes.entries) {
      testWidgets(entry.key, (tester) async {
        tester.view.physicalSize = entry.value;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              bottomNavigationBar: HangulWritingToolbar(
                tool: HangulWriteTool.pen,
                onToolChanged: (_) {},
                onClearSelected: () {},
                onClearAll: () {},
                hasSelection: true,
              ),
              body: const SizedBox.shrink(),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull, reason: '툴바가 넘치면 안 된다');

        // 지우기는 되돌릴 수 없는 동작이라 라벨이 남아 있어야 한다
        // (아이콘만 남으면 초등학생이 뜻을 모른다).
        for (final label in ['펜', '지우개', '이 칸', '전체']) {
          final text = tester.widget<Text>(find.text(label));
          expect(text.data, label, reason: '"$label" 라벨이 보여야 한다');
        }
      });
    }
  });
}
