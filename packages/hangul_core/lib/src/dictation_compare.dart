import 'hangul_glyph.dart';
import 'hangul_util.dart';

/// 한 글자(또는 특수/숫자) 단위 비교 결과.
class GlyphMatch {
  const GlyphMatch({
    required this.index,
    required this.expected,
    required this.actual,
    required this.isCorrect,
    this.mismatchReason,
  });

  final int index;
  final HangulGlyph? expected;
  final HangulGlyph? actual;
  final bool isCorrect;
  final String? mismatchReason;
}

/// 받아쓰기 문자열 비교 — jammin 분해 스키마 기준.
class DictationCompare {
  DictationCompare._();

  /// [expected] 정답, [actual] 학생 답 (키보드 또는 OCR 정규화 텍스트).
  static DictationScoreResult score({
    required String expected,
    required String actual,
  }) {
    if (!HangulUtil.isHangul(expected)) {
      return const DictationScoreResult(
        correctCount: 0,
        totalCount: 0,
        ratio: 0,
        matches: const [],
        error: '정답이 jammin 허용 문자 집합이 아닙니다.',
      );
    }
    if (!HangulUtil.isHangul(actual)) {
      return DictationScoreResult(
        correctCount: 0,
        totalCount: HangulUtil.hangulSplit(expected).length,
        ratio: 0,
        matches: const [],
        error: '답안이 jammin 허용 문자 집합이 아닙니다.',
      );
    }

    final eGlyphs = HangulUtil.hangulSplit(expected);
    final aGlyphs = HangulUtil.hangulSplit(actual);
    final matches = <GlyphMatch>[];
    var correct = 0;

    for (var i = 0; i < eGlyphs.length; i++) {
      final e = eGlyphs[i];
      final a = i < aGlyphs.length ? aGlyphs[i] : null;
      final ok = _glyphEquals(e, a);
      if (ok) correct++;
      matches.add(
        GlyphMatch(
          index: i,
          expected: e,
          actual: a,
          isCorrect: ok,
          mismatchReason: ok ? null : _reason(e, a),
        ),
      );
    }

    for (var i = eGlyphs.length; i < aGlyphs.length; i++) {
      matches.add(
        GlyphMatch(
          index: i,
          expected: null,
          actual: aGlyphs[i],
          isCorrect: false,
          mismatchReason: '불필요한 글자',
        ),
      );
    }

    final total = eGlyphs.length;
    final ratio = total == 0 ? 1.0 : correct / total;
    return DictationScoreResult(
      correctCount: correct,
      totalCount: total,
      ratio: ratio,
      matches: matches,
      hasExtraInput: aGlyphs.length > eGlyphs.length,
    );
  }

  static bool _glyphEquals(HangulGlyph e, HangulGlyph? a) {
    if (a == null) return false;
    if (e.specialFlag != a.specialFlag) return false;
    if (e.specialFlag) {
      return e.specialType == a.specialType;
    }
    if (e.errorFlag != a.errorFlag) return false;
    return e.word == a.word &&
        e.choCode == a.choCode &&
        e.jungCode == a.jungCode &&
        e.jongCode == a.jongCode;
  }

  static String _reason(HangulGlyph e, HangulGlyph? a) {
    if (a == null) return '글자 누락';
    if (e.specialFlag != a.specialFlag) {
      return '문자 종류 불일치(한글/특수·숫자)';
    }
    if (e.specialFlag) {
      return '기호·숫자 불일치: "${e.specialType}" vs "${a.specialType}"';
    }
    if (e.word != a.word) {
      return '글자 불일치: "${e.word}" vs "${a.word}"';
    }
    return '자모 불일치';
  }
}

class DictationScoreResult {
  const DictationScoreResult({
    required this.correctCount,
    required this.totalCount,
    required this.ratio,
    required this.matches,
    this.error,
    this.hasExtraInput = false,
  });

  final int correctCount;
  final int totalCount;
  final double ratio;
  final List<GlyphMatch> matches;
  final String? error;
  final bool hasExtraInput;

  int get scorePercent => (ratio * 100).round();
}
