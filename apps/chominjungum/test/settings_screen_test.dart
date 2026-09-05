import 'package:chominjungum/domain/app_role.dart';
import 'package:chominjungum/features/settings/settings_screen.dart';
import 'package:chominjungum/providers/app_role_provider.dart';
import 'package:chominjungum/providers/dictation_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 설정 화면은 두 가지의 제자리다:
/// 기기 ID(그전에는 어디에도 볼 곳이 없었다)와 폰트 OFL 고지.
void main() {
  const deviceId = '3f2a91c4-8b7e-4d16-9a03-5c7e1d2f8b40';

  Future<void> pump(WidgetTester tester, {AppRole role = AppRole.student}) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          appRoleProvider.overrideWithValue(role),
          deviceBindingIdProvider.overrideWith((ref) async => deviceId),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
  }

  testWidgets('역할을 보여준다', (tester) async {
    await pump(tester, role: AppRole.teacher);
    await tester.pump();

    expect(find.text('교사'), findsOneWidget);
  });

  testWidgets('기기 ID 는 기본으로 줄여서 보여준다', (tester) async {
    await pump(tester);
    await tester.pump();

    expect(find.text('3f2a91c4…'), findsOneWidget);
    expect(find.text(deviceId), findsNothing);
    expect(find.text('전체 보기'), findsOneWidget);
  });

  testWidgets('전체 보기를 누르면 펼쳐지고 다시 접힌다', (tester) async {
    await pump(tester);
    await tester.pump();

    await tester.tap(find.text('전체 보기'));
    await tester.pump();
    expect(find.text(deviceId), findsOneWidget);

    await tester.tap(find.text('접기'));
    await tester.pump();
    expect(find.text(deviceId), findsNothing);
  });

  testWidgets('복사 버튼이 기기 ID 를 클립보드에 넣는다', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );

    await pump(tester);
    await tester.pump();
    await tester.tap(find.text('복사'));
    await tester.pump();

    expect(copied, [deviceId]);

    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('폰트 고지 (OFL 사본 동봉)', () {
    test('HTML 조각에서 태그를 걷어내고 읽을 수 있는 텍스트만 남긴다', () {
      const raw = '''
출처 링크 : https://gongu.copyright.or.kr/example

<img id="wrtImg" src="https://example.com/x.png">
<p style="font-size: 0.9rem;">
<span>
title : <a href="https://example.com"> KCC도담도담체</a>
authr : <a href="https://example.com"> 한국저작권위원회</a>by
</span> <br>
is licensed under
<img alt="OFL" class="img_cc">
</p>
''';

      final text = FontLicenseText.plainText(raw);

      expect(text, contains('KCC도담도담체'));
      expect(text, contains('한국저작권위원회'));
      expect(text, contains('is licensed under'));
      // 태그와 속성은 남지 않는다
      expect(text, isNot(contains('<')));
      expect(text, isNot(contains('font-size')));
      expect(text, isNot(contains('img_cc')));
      // 빈 줄이 뭉치지 않는다
      expect(text, isNot(contains('\n\n')));
    });

    test('빈 입력에도 깨지지 않는다', () {
      expect(FontLicenseText.plainText(''), '');
      expect(FontLicenseText.plainText('<p></p>'), '');
    });
  });
}
