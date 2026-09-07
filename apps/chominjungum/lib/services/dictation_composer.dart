import 'package:hangul_core/hangul_core.dart';

import '../domain/dictation_models.dart';

/// 교사 출제: 정답 문장 → 받아쓰기 문항.
///
/// ★**네트워크를 타지 않는다.** 교실에 인터넷이 없어도 출제가 되어야 하고,
/// 그것이 이 프로젝트의 전제(중앙 서버 없이 같은 Wi-Fi만으로 동작)다.
/// 자모 분해는 [HangulUtil]로 기기에서 하며, 이 구현이 jammin 원본과 같은 결과를
/// 낸다는 것은 골든 벡터가 강제한다(`packages/hangul_core/test/golden_test.dart`).
///
/// 2026-09-07 이전에는 매 출제마다 원격 jammin 서버(`POST /addWord`)를 호출했고,
/// 그래서 인터넷이 없거나 TLS 검증이 실패하는 환경에서는 출제가 통째로 실패했다.
class DictationComposer {
  const DictationComposer._();

  /// 출제 가능한 문장인지. jammin 허용 문자 집합(한글 음절·숫자·공백·`. , ? !`) 기준.
  static bool isComposable(String text) {
    final t = text.trim();
    return t.isNotEmpty && HangulUtil.isHangul(t);
  }

  /// [text]를 문항으로 만든다. 출제할 수 없으면 [FormatException].
  static DictationItem compose(String text) {
    final t = text.trim();
    if (t.isEmpty) {
      throw const FormatException('정답 문장이 비어 있습니다.');
    }
    if (!HangulUtil.isHangul(t)) {
      throw const FormatException('한글·숫자·공백·구두점(. , ? !)만 출제할 수 있습니다.');
    }
    final glyphs = HangulUtil.hangulSplit(t);
    if (glyphs.isEmpty) {
      throw const FormatException('분해 결과가 비었습니다.');
    }
    return DictationItem.fromGlyphs(t, glyphs);
  }
}
