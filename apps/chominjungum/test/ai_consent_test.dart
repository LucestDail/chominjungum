import 'package:chominjungum/services/ai_consent.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// AI 기능의 동의·열쇠 규칙.
///
/// 기능(어느 모델을 쓸지)보다 이걸 먼저 만든 이유는, 정하고 나서 붙이면
/// "일단 되게" 하려고 키를 평문에 두거나 동의 없이 보내기 쉽기 때문이다.
/// 초등학생 손글씨 이미지가 오갈 수 있는 기능이라 순서를 뒤집으면 안 된다.
void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('기본은 꺼짐 — 켜는 것은 언제나 사람의 명시적 행위다', () async {
    final c = AiConsent();
    expect(await c.isEnabled(), isFalse);
    expect(await c.apiKey(), isNull);
  });

  test('켜면 키를 준다', () async {
    final c = AiConsent();
    await c.enable('sk-test-123');
    expect(await c.isEnabled(), isTrue);
    expect(await c.apiKey(), 'sk-test-123');
  });

  test('🔴꺼져 있으면 키가 있어도 주지 않는다', () async {
    final c = AiConsent();
    await c.enable('sk-test-123');
    // 저장소에는 남아 있지만 동의가 꺼진 상태를 흉내낸다.
    await const FlutterSecureStorage()
        .write(key: 'ai_enabled_v1', value: 'false');
    expect(await c.apiKey(), isNull, reason: '동의 없이 나가면 안 된다');
  });

  test('🔴끄면 키도 함께 지운다', () async {
    final c = AiConsent();
    await c.enable('sk-test-123');
    await c.disable();
    expect(await c.isEnabled(), isFalse);
    expect(await c.hasKey(), isFalse, reason: '"꺼 뒀으니 괜찮다"가 아니라 없애는 것이 맞다');
  });

  test('빈 키는 거부한다', () async {
    expect(() => AiConsent().enable('   '), throwsArgumentError);
  });

  group('역할 규칙은 호출 지점에서 강제한다', () {
    test('학생 기기에서는 켤 수 없다', () {
      expect(
        () => AiConsentGuard.assertTeacher(isTeacher: false),
        throwsA(isA<StateError>()),
      );
    });

    test('교사 기기에서는 통과', () {
      AiConsentGuard.assertTeacher(isTeacher: true);
    });
  });

  test('동의 문구가 무엇이 나가는지 구체적으로 적는다', () {
    final all = AiConsent.consentPoints.join(' ');
    // 두루뭉술하게 "AI 기능을 사용합니다"면 동의가 아니다.
    expect(all, contains('전송'));
    expect(all, contains('학생 이름'));
    expect(all, contains('교사 기기'));
    expect(AiConsent.consentPoints.length, greaterThanOrEqualTo(4));
  });
}
