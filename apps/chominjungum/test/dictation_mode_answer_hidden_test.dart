import 'package:chominjungum/domain/dictation_models.dart';
import 'package:chominjungum/features/dictation/dictation_practice_screen.dart';
import 'package:chominjungum/providers/dictation_providers.dart';
import 'package:chominjungum/services/dictation_composer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🔴받아쓰기 모드에서 **정답이 화면에 보이면 안 된다.**
///
/// 2026-09-10 발견: 받아쓰기 모드는 밑그림(`guideOpacity`)만 지웠고, 문항 제목은
/// `1. 나비 (2칸)` 처럼 **정답을 그대로 적어 두고 있었다.** 그러면 학생은 듣고
/// 받아 적는 게 아니라 위에 적힌 글자를 베낀다 — 받아쓰기가 성립하지 않는다.
///
/// 밑그림을 지우는 것과 정답 문구를 지우는 것은 **다른 코드 경로**라, 한쪽만
/// 고치면 이 결함이 되살아난다. 그래서 회귀로 잠근다.
void main() {
  Future<void> pump(WidgetTester tester, {required bool dictationMode}) async {
    // ⚠️표본 단어는 **화면의 다른 글자와 겹치지 않는 것**을 쓴다.
    // 처음에 '학교'를 썼다가 인쇄 머리글의 "초등학교"에 걸려 오탐이 났다.
    final pkg = DictationPackage(
      version: DictationPackage.currentVersion,
      items: [DictationComposer.compose('나비')],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // 화면이 허브·서버를 타지 않게 패키지를 직접 물린다.
          practicePackageProvider.overrideWith((ref) => AsyncValue.data(pkg)),
        ],
        child: const MaterialApp(home: DictationPracticeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    if (dictationMode) {
      await tester.tap(find.byKey(DictationPracticeKeys.dictationMode));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('연습 모드에서는 정답이 보인다 (밑그림 따라 쓰기)', (tester) async {
    await pump(tester, dictationMode: false);
    expect(find.textContaining('나비'), findsWidgets);
  });

  testWidgets('🔴받아쓰기 모드에서는 정답이 화면 어디에도 없다', (tester) async {
    await pump(tester, dictationMode: true);
    expect(
      find.textContaining('나비'),
      findsNothing,
      reason: '정답이 보이면 받아쓰기가 아니라 베껴 쓰기다',
    );
  });

  testWidgets('🔴학생 화면에는 jammin 서버 갱신 버튼이 없다', (tester) async {
    // 기본 역할이 학생이므로 override 없이 뜨는 화면이 곧 학생 화면이다.
    // 인터넷 없는 교실에서 누르면 실패만 보게 되고, "중앙 서버 없음" 전제와도 어긋난다.
    await pump(tester, dictationMode: false);
    expect(find.byIcon(Icons.cloud_download_outlined), findsNothing);
  });

  testWidgets('받아쓰기 모드에도 칸 수는 알려준다 — 몇 글자인지는 힌트가 아니다', (tester) async {
    await pump(tester, dictationMode: true);
    expect(find.textContaining('2칸'), findsOneWidget);
    expect(find.textContaining('1번'), findsOneWidget);
  });
}
