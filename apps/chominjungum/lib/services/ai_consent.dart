import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// AI 기능의 **동의와 열쇠** — 켜기 전에 무엇이 나가는지 밝힌다.
///
/// ## 왜 기능보다 이걸 먼저 만드나
///
/// AI 출제·글씨 교정은 어느 모델을 쓸지 아직 정하지 않았다. 그런데 **정하고
/// 나서 동의·키 보관을 붙이면 늦다** — 그때는 "일단 되게" 하려고 키를
/// 평문에 두거나 동의 없이 보내기 쉽다. 초등학생 손글씨 이미지가 오갈 수 있는
/// 기능이라 그 순서를 뒤집으면 안 된다.
///
/// ## 규칙 (코드로 강제한다)
///
///  1. **학생 기기에서는 못 켠다.** 교사 기기에서만.
///  2. **기본은 꺼짐.** 켜는 것은 언제나 사람의 명시적 행위다.
///  3. 키는 **Secure Storage** 에만 — 설정 파일·로그·업싱크 어디에도 안 남는다.
///  4. 끄면 **키도 함께 지운다.** "꺼 뒀으니 괜찮다"가 아니라 없애는 것이 맞다.
class AiConsent {
  AiConsent({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _kEnabled = 'ai_enabled_v1';
  static const _kApiKey = 'ai_api_key_v1';

  /// 동의 화면에 **그대로 보여 줄** 문구.
  ///
  /// 두루뭉술하게 "AI 기능을 사용합니다"라고 하면 동의가 아니다.
  /// 무엇이 어디로 가는지 적는다.
  static const consentPoints = <String>[
    '문장·손글씨 이미지가 외부 AI 서비스로 전송됩니다.',
    '학생 이름·기기 정보는 보내지 않습니다.',
    '학생 기기에서는 이 기능이 동작하지 않습니다 (교사 기기 전용).',
    'API 키는 이 기기에만 암호화 저장되고, 수업 기록·서버 업로드에는 포함되지 않습니다.',
    '끄면 저장된 키도 함께 삭제됩니다.',
  ];

  /// 켜져 있는가. 실패하면 **꺼짐으로 본다** — 모르면 안 보내는 쪽이 안전하다.
  Future<bool> isEnabled() async {
    try {
      return await _storage.read(key: _kEnabled) == 'true';
    } catch (_) {
      return false;
    }
  }

  /// 저장된 키. 꺼져 있으면 **키가 있어도 주지 않는다**.
  Future<String?> apiKey() async {
    if (!await isEnabled()) return null;
    try {
      final v = await _storage.read(key: _kApiKey);
      return (v == null || v.isEmpty) ? null : v;
    } catch (_) {
      return null;
    }
  }

  /// 동의하고 키를 저장한다. **교사 기기에서만** 부를 것
  /// ([AiConsentGuard.assertTeacher] 로 강제).
  Future<void> enable(String apiKey) async {
    final key = apiKey.trim();
    if (key.isEmpty) {
      throw ArgumentError('API 키가 비어 있습니다.');
    }
    await _storage.write(key: _kApiKey, value: key);
    await _storage.write(key: _kEnabled, value: 'true');
  }

  /// 끄면서 **키도 지운다.**
  Future<void> disable() async {
    // 키를 먼저 지운다 — 중간에 실패해도 "켜져 있는데 키 없음"이 낫다
    // (그 상태는 아무것도 못 보낸다). 반대면 "꺼진 줄 알았는데 키가 남는다".
    await _storage.delete(key: _kApiKey);
    await _storage.write(key: _kEnabled, value: 'false');
  }

  /// 키가 저장돼 있는가(값은 안 돌려준다). 설정 화면 표시용.
  Future<bool> hasKey() async {
    try {
      final v = await _storage.read(key: _kApiKey);
      return v != null && v.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}

/// 역할 규칙을 **호출 지점에서** 강제한다.
///
/// UI 로만 가리면 다른 경로가 생겼을 때 새어 나간다. 실제로 09-10 에
/// 학생 화면에 남아 있던 jammin 호출 버튼이 그런 경우였다.
class AiConsentGuard {
  const AiConsentGuard._();

  static void assertTeacher({required bool isTeacher}) {
    if (!isTeacher) {
      throw StateError(
        'AI 기능은 교사 기기에서만 켤 수 있습니다. '
        '학생 단말은 외부로 아무것도 보내지 않습니다.',
      );
    }
  }
}
