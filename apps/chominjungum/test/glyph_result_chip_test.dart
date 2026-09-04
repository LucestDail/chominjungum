import 'package:chominjungum/features/dictation/glyph_result_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 받아쓰기에서 배우는 지점은 "무엇이 맞다"가 아니라
/// **"내가 이렇게 썼고 실제로는 이렇다"** 는 대조다.
/// 그전에는 정답만 띄워서 자기가 쓴 글자가 보이지 않았다.
void main() {
  Future<void> pump(WidgetTester tester, Widget chip) {
    return tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: chip))));
  }

  testWidgets('맞은 글자는 글자와 체크만 보여준다', (tester) async {
    await pump(tester, const GlyphResultChip(isCorrect: true, expected: '갔', actual: '갔'));

    expect(find.text('갔'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    // 맞았으면 화살표(대조)가 필요 없다
    expect(find.byIcon(Icons.arrow_right_alt), findsNothing);
  });

  testWidgets('틀린 글자는 내가 쓴 것과 정답을 함께 보여준다', (tester) async {
    await pump(tester, const GlyphResultChip(isCorrect: false, expected: '갔', actual: '갓'));

    expect(find.text('갓'), findsOneWidget); // 내가 쓴 것
    expect(find.text('갔'), findsOneWidget); // 정답
    expect(find.byIcon(Icons.arrow_right_alt), findsOneWidget);
  });

  testWidgets('내가 쓴 글자에 취소선이 붙는다 — 이건 아니라는 표시', (tester) async {
    await pump(tester, const GlyphResultChip(isCorrect: false, expected: '갔', actual: '갓'));

    final written = tester.widget<Text>(find.text('갓'));
    expect(written.style?.decoration, TextDecoration.lineThrough);

    final answer = tester.widget<Text>(find.text('갔'));
    expect(answer.style?.decoration, isNot(TextDecoration.lineThrough));
    expect(answer.style?.fontWeight, FontWeight.bold);
  });

  testWidgets('빠뜨린 글자는 빈 칸 기호로 자리를 표시한다', (tester) async {
    await pump(tester, const GlyphResultChip(isCorrect: false, expected: '다', actual: null));

    expect(find.text('□'), findsOneWidget);
    expect(find.text('다'), findsOneWidget);
  });

  testWidgets('덧붙여 쓴 글자(정답에 없는 자리)도 표시된다', (tester) async {
    await pump(tester, const GlyphResultChip(isCorrect: false, expected: null, actual: '요'));

    expect(find.text('요'), findsOneWidget);
    expect(find.text('□'), findsOneWidget);
  });

  testWidgets('맞은 글자와 틀린 글자의 색이 다르다', (tester) async {
    await pump(tester, const GlyphResultChip(isCorrect: true, expected: '가', actual: '가'));
    final okColor = tester.widget<Text>(find.text('가')).style?.color;

    await pump(tester, const GlyphResultChip(isCorrect: false, expected: '나', actual: '다'));
    final wrongColor = tester.widget<Text>(find.text('다')).style?.color;

    expect(okColor, isNot(wrongColor));
  });
}
