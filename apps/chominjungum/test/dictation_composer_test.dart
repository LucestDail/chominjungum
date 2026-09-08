import 'dart:convert';
import 'dart:io';

import 'package:chominjungum/services/dictation_composer.dart';
import 'package:flutter_test/flutter_test.dart';

/// 교사 출제는 **기기에서** 자모를 분해한다 — 교실에 인터넷이 없어도 출제되어야 한다.
///
/// 2026-09-07 시뮬레이터 검증에서, 출제가 매번 원격 jammin 서버(`POST /addWord`)를
/// 호출하고 TLS 검증 실패로 통째로 실패하는 것을 발견했다. 중앙 서버 없이 같은 Wi-Fi만으로
/// 동작한다는 이 프로젝트의 전제를 정면으로 위반하는 버그였다.
/// 아래 테스트가 그 회귀를 막는다.
void main() {
  group('DictationComposer — 기기 내 분해', () {
    test('한글 문장을 문항으로 만든다', () {
      final item = DictationComposer.compose('안녕하세요');
      expect(item.expectedText, '안녕하세요');
      final glyphs = jsonDecode(item.expectedGlyphsJson) as List<dynamic>;
      expect(glyphs.length, 5);
      expect(item.contentHash, isNotEmpty);
    });

    test('앞뒤 공백을 다듬는다', () {
      expect(DictationComposer.compose('  안녕하세요  ').expectedText, '안녕하세요');
    });

    test('숫자·공백·구두점을 허용한다', () {
      expect(() => DictationComposer.compose('안녕 하세요.'), returnsNormally);
      expect(() => DictationComposer.compose('사과 3개?'), returnsNormally);
      expect(() => DictationComposer.compose('와, 좋다!'), returnsNormally);
    });

    test('빈 문장은 거부한다', () {
      expect(() => DictationComposer.compose(''), throwsFormatException);
      expect(() => DictationComposer.compose('   '), throwsFormatException);
    });

    test('허용 문자 집합 밖이면 거부한다', () {
      expect(() => DictationComposer.compose('hello'), throwsFormatException);
      expect(() => DictationComposer.compose('안녕abc'), throwsFormatException);
      expect(() => DictationComposer.compose('안녕@'), throwsFormatException);
      // 조합되지 않은 낱자(jammin `isHangul`은 음절만 허용)
      expect(() => DictationComposer.compose('ㄱㄴㄷ'), throwsFormatException);
    });

    test('isComposable이 compose 성공 여부와 일치한다', () {
      for (final s in ['안녕하세요', '사과 3개?', '', '  ', 'hello', '안녕abc', 'ㄱ']) {
        final ok = DictationComposer.isComposable(s);
        var composed = true;
        try {
          DictationComposer.compose(s);
        } on FormatException {
          composed = false;
        }
        expect(ok, composed, reason: '불일치: ${jsonEncode(s)}');
      }
    });
  });

  group('골든 벡터 동치 — 기기 분해가 jammin 원본과 같은 결과를 낸다', () {
    // 골든은 chominjungum-web 저장소에 있다(같은 워크스페이스에 체크아웃된 경우에만 검증).
    final goldenFile = File('../../../chominjungum-web/golden/hangul-split.json');

    test('출제 결과가 골든과 일치한다', () {
      if (!goldenFile.existsSync()) {
        markTestSkipped('golden 없음: ${goldenFile.path}');
        return;
      }
      final doc = jsonDecode(goldenFile.readAsStringSync()) as Map<String, Object?>;
      final cases = (doc['cases'] as List<dynamic>).cast<Map<String, Object?>>();
      expect(cases, isNotEmpty);

      var checked = 0;
      for (final c in cases) {
        final input = c['input'] as String;
        if (!DictationComposer.isComposable(input)) continue;
        final expected = (c['expected'] as List<dynamic>)
            .map((e) => Map<String, Object?>.from(e as Map))
            .toList();
        final actual =
            (jsonDecode(DictationComposer.compose(input).expectedGlyphsJson) as List<dynamic>)
                .map((e) => Map<String, Object?>.from(e as Map))
                .toList();
        expect(actual, equals(expected), reason: '골든 불일치: ${jsonEncode(input)}');
        checked++;
      }
      expect(checked, greaterThan(0), reason: '검증된 골든 케이스가 없다');
    });
  });

  group('여러 문항을 한 번에 — 한 줄이 한 문항', () {
    test('줄 수만큼 문항이 나온다', () {
      final items = DictationComposer.composeAll('안녕하세요\n학교에 갔다.\n꽃이 피었습니다');
      expect(items, hasLength(3));
      expect(items.map((i) => i.expectedText),
          ['안녕하세요', '학교에 갔다.', '꽃이 피었습니다']);
    });

    test('빈 줄과 앞뒤 공백은 무시한다 — 붙여넣기가 흔하다', () {
      final items = DictationComposer.composeAll('\n  안녕하세요  \n\n\n학교에 갔다.\n  \n');
      expect(items, hasLength(2));
      expect(items.first.expectedText, '안녕하세요');
    });

    test('한 줄만 있어도 된다', () {
      expect(DictationComposer.composeAll('안녕하세요'), hasLength(1));
    });

    test('전부 비면 거부한다', () {
      expect(() => DictationComposer.composeAll('  \n\n '), throwsFormatException);
    });

    test('★잘못된 줄은 몇 번째인지 알려준다', () {
      // 10줄을 붙여넣었는데 "출제 실패"만 뜨면 어디를 고칠지 알 수 없다.
      try {
        DictationComposer.composeAll('안녕하세요\n학교에 갔다.\nhello\n꽃이 피었습니다');
        fail('거부되어야 한다');
      } on FormatException catch (e) {
        expect(e.message, contains('3번 문장'));
      }
    });

    test('jammin 제약 — 한 문장 16글자', () {
      final ok = '가' * DictationComposer.maxGlyphsPerItem;
      expect(() => DictationComposer.composeAll(ok), returnsNormally);
      expect(DictationComposer.isComposable('가' * 17), isFalse);
      try {
        DictationComposer.composeAll('안녕하세요\n${'가' * 17}');
        fail('거부되어야 한다');
      } on FormatException catch (e) {
        expect(e.message, contains('2번 문장'));
        expect(e.message, contains('16글자'));
      }
    });

    test('jammin 제약 — 학습지 전체 20줄', () {
      // 8글자 = 1줄. 20줄 = 8글자 문장 20개까지.
      final twenty = List.filled(20, '가' * 8).join('\n');
      expect(DictationComposer.composeAll(twenty), hasLength(20));
      final twentyOne = List.filled(21, '가' * 8).join('\n');
      try {
        DictationComposer.composeAll(twentyOne);
        fail('거부되어야 한다');
      } on FormatException catch (e) {
        expect(e.message, contains('20줄'));
      }
    });

    test('rowsFor — 8칸이 한 줄', () {
      expect(DictationComposer.rowsFor(''), 0);
      expect(DictationComposer.rowsFor('가'), 1);
      expect(DictationComposer.rowsFor('가' * 8), 1);
      expect(DictationComposer.rowsFor('가' * 9), 2);
      expect(DictationComposer.rowsFor('가' * 16), 2);
    });
  });

  group('오프라인 출제 전제 가드', () {
    test('교사 화면이 원격 분해 서비스를 쓰지 않는다', () {
      final src = File('lib/features/teacher/teacher_home_screen.dart');
      expect(src.existsSync(), isTrue, reason: '경로가 바뀌었으면 이 테스트를 갱신할 것');
      final code = src.readAsStringSync();
      expect(
        code.contains('JamminAddWordService'),
        isFalse,
        reason: '출제는 기기에서 분해해야 한다 — 원격 호출을 되돌리지 말 것 '
            '(교실에 인터넷이 없으면 출제가 통째로 실패한다)',
      );
      expect(
        code.contains("package:http/"),
        isFalse,
        reason: '교사 화면에 직접 HTTP 호출을 넣지 말 것 (업싱크는 UpsyncService 경유)',
      );
    });
  });
}
