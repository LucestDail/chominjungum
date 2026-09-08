import 'package:chominjungum/domain/dictation_models.dart';
import 'package:chominjungum/features/dictation/attempt_submit_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(DictationPackage package) {
    return ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: AttemptSubmitSheet(package: package)),
      ),
    );
  }

  final package = DictationPackage(
    version: DictationPackage.currentVersion,
    items: [DictationItem.fromExpectedText('안녕하세요')],
  );

  testWidgets('답안 입력 후 채점하면 점수와 글자별 정오가 표시된다', (tester) async {
    await tester.pumpWidget(wrap(package));

    await tester.enterText(find.byType(TextField), '안녕하세오');
    await tester.tap(find.widgetWithText(FilledButton, '채점'));
    await tester.pumpAndSettle();

    expect(find.text('80점'), findsOneWidget);
    expect(find.text('4/5글자'), findsOneWidget);
    expect(find.text('정답: 안녕하세요'), findsOneWidget);
  });

  testWidgets('허브 미연결이면 제출 버튼이 비활성이다', (tester) async {
    await tester.pumpWidget(wrap(package));

    await tester.enterText(find.byType(TextField), '안녕하세요');
    await tester.tap(find.widgetWithText(FilledButton, '채점'));
    await tester.pumpAndSettle();

    expect(find.text('100점'), findsOneWidget);
    final submit = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '선생님께 제출'),
    );
    expect(submit.onPressed, isNull);
    expect(find.textContaining('허브에 연결되어 있지 않아'), findsOneWidget);
  });

}
