import 'package:hangul_core/hangul_core.dart';
import 'package:test/test.dart';

void main() {
  test('parses jammin addWord JSON for 안녕하세요', () {
    const json = '''
[{"emptyJongsung":false,"jungsung":"ᅡ","chosung":"ᄋ","jungCode":4449,"choCode":4363,"errorFlag":false,"jongCode":4523,"specialFlag":false,"word":"안","jongsung":"ᆫ"},{"emptyJongsung":false,"jungsung":"ᅧ","chosung":"ᄂ","jungCode":4455,"choCode":4354,"errorFlag":false,"jongCode":4540,"specialFlag":false,"word":"녕","jongsung":"ᆼ"},{"emptyJongsung":true,"jungsung":"ᅡ","chosung":"ᄒ","jungCode":4449,"choCode":4370,"errorFlag":false,"specialFlag":false,"word":"하"},{"emptyJongsung":true,"jungsung":"ᅦ","chosung":"ᄉ","jungCode":4454,"choCode":4361,"errorFlag":false,"specialFlag":false,"word":"세"},{"emptyJongsung":true,"jungsung":"ᅭ","chosung":"ᄋ","jungCode":4461,"choCode":4363,"errorFlag":false,"specialFlag":false,"word":"요"}]
''';
    final glyphs = HangulUtil.glyphsFromAddWordResponse(json);
    expect(glyphs.length, 5);
    expect(glyphs.first.word, '안');
    expect(glyphs.first.choCode, 4363);
    expect(glyphs.first.jungCode, 4449);
    expect(glyphs.first.jongCode, 4523);
    expect(glyphs[2].word, '하');
    expect(glyphs[2].emptyJongsung, isTrue);
  });
}
