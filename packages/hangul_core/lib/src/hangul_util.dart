import 'hangul_glyph.dart';

/// jammin [HangulUtil] 포팅.
class HangulUtil {
  static const _special = {' ', '.', ',', '?', '!'};
  static const _numbers = '1234567890';

  /// jammin `isHangul` — 한글 음절·공백·구두·숫자만 허용.
  static bool isHangul(String str) {
    for (var i = 0; i < str.length; i++) {
      final unit = str.codeUnitAt(i);
      final c = String.fromCharCode(unit);
      if (_isHangulSyllable(unit) ||
          _special.contains(c) ||
          _numbers.contains(c)) {
        continue;
      }
      return false;
    }
    return true;
  }

  static bool _isHangulSyllable(int codeUnit) =>
      codeUnit >= 0xAC00 && codeUnit <= 0xD7A3;

  /// jammin `hangulSplit`과 동일 로직.
  static List<HangulGlyph> hangulSplit(String s) {
    final list = <HangulGlyph>[];
    const noJongChar = 4519; // (char)0x11A7 — 받침 없음 표기와 동일 비교

    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (_isSpecialType(c) || _isNumberType(c)) {
        list.add(
          HangulGlyph(
            specialFlag: true,
            specialType: String.fromCharCode(c),
            specialTypeCode: c,
            emptyJongsung: true,
            errorFlag: false,
          ),
        );
        continue;
      }

      final ch = String.fromCharCode(c);
      String? chosung;
      int? choCode;
      String? jungsung;
      int? jungCode;
      String? jongsung;
      int? jongCode;
      var emptyJongsung = true;
      var errorFlag = false;

      final comVal = c - 0xAC00;
      if (comVal >= 0 && comVal <= 11172) {
        final uniVal = comVal;
        final cho = ((((uniVal - (uniVal % 28)) ~/ 28) ~/ 21) + 0x1100);
        final jung = ((((uniVal - (uniVal % 28)) ~/ 28) % 21) + 0x1161);
        final jong = ((uniVal % 28) + 0x11A7);

        if (cho != noJongChar) {
          chosung = String.fromCharCode(cho);
          choCode = cho;
        }
        if (jung != noJongChar) {
          jungsung = String.fromCharCode(jung);
          jungCode = jung;
        }
        if (jong != noJongChar) {
          jongsung = String.fromCharCode(jong);
          jongCode = jong;
          emptyJongsung = false;
        } else {
          emptyJongsung = true;
        }
        errorFlag = false;
      } else {
        errorFlag = true;
      }

      list.add(
        HangulGlyph(
          word: ch,
          chosung: chosung,
          choCode: choCode,
          jungsung: jungsung,
          jungCode: jungCode,
          jongsung: jongsung,
          jongCode: jongCode,
          specialFlag: false,
          emptyJongsung: emptyJongsung,
          errorFlag: errorFlag,
        ),
      );
    }
    return list;
  }

  /// jammin `addWord` 응답과 동일한 JSON 배열 문자열.
  static String addWordJson(String requestWord) {
    if (!isHangul(requestWord)) {
      return '[]';
    }
    final glyphs = hangulSplit(requestWord);
    final parts = glyphs.map((g) => g.toJsonString()).join(',');
    return '[$parts]';
  }

  static bool _isSpecialType(int c) => _special.contains(String.fromCharCode(c));

  static bool _isNumberType(int c) {
    for (final r in _numbers.runes) {
      if (r == c) return true;
    }
    return false;
  }
}
