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

  /// 한 문항의 최대 글자 수 — jammin `HangulWorksheetApp.js` 와 같은 값
  /// ("16글자 이상의 문장은 추가할 수 없습니다").
  static const maxGlyphsPerItem = 16;

  /// 학습지 전체 줄 수 상한 — jammin 과 같은 값
  /// ("학습지 전체 줄수는 20줄을 넘을 수 없습니다").
  static const maxTotalRows = 20;

  /// 한 줄에 들어가는 칸 수(`HangulWorksheetProfile.editor.lineBreakCount`).
  static const glyphsPerRow = 8;

  /// 출제 가능한 문장인지. jammin 허용 문자 집합(한글 음절·숫자·공백·`. , ? !`) 기준.
  static bool isComposable(String text) {
    final t = text.trim();
    return t.isNotEmpty && HangulUtil.isHangul(t) && t.length <= maxGlyphsPerItem;
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
    if (t.length > maxGlyphsPerItem) {
      throw FormatException('한 문장은 $maxGlyphsPerItem글자까지입니다 (${t.length}글자).');
    }
    final glyphs = HangulUtil.hangulSplit(t);
    if (glyphs.isEmpty) {
      throw const FormatException('분해 결과가 비었습니다.');
    }
    return DictationItem.fromGlyphs(t, glyphs);
  }

  /// 한 문장이 학습지에서 차지하는 줄 수.
  static int rowsFor(String text) {
    final n = text.trim().length;
    if (n == 0) return 0;
    return (n + glyphsPerRow - 1) ~/ glyphsPerRow;
  }

  /// **여러 문항을 한 번에** 만든다 — 줄 하나가 문항 하나다.
  ///
  /// 받아쓰기 수업은 보통 10문항쯤을 한 번에 낸다. 그래서 교사가 문장 목록을
  /// (한글 파일 등에서) 그대로 붙여넣을 수 있게 **여러 줄 입력**을 받는다.
  /// 빈 줄은 건너뛴다.
  ///
  /// 잘못된 줄이 있으면 **몇 번째 줄인지 알려주는** [FormatException] 을 던진다 —
  /// 10줄을 붙여넣었는데 "출제 실패"만 뜨면 어디를 고쳐야 할지 알 수 없다.
  static List<DictationItem> composeAll(String multiline) {
    final lines = multiline
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (lines.isEmpty) {
      throw const FormatException('정답 문장이 비어 있습니다.');
    }

    final items = <DictationItem>[];
    var rows = 0;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      try {
        items.add(compose(line));
      } on FormatException catch (e) {
        throw FormatException('${i + 1}번 문장: ${e.message}');
      }
      rows += rowsFor(line);
      if (rows > maxTotalRows) {
        throw FormatException(
          '학습지가 $maxTotalRows줄을 넘습니다 (${i + 1}번 문장까지 $rows줄). '
          '문항을 줄이거나 짧게 만드세요.',
        );
      }
    }
    return items;
  }
}
