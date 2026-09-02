import 'dart:convert';
import 'dart:io';

import 'package:hangul_core/hangul_core.dart';
import 'package:test/test.dart';

/// jammin 원본 응답으로 채집한 골든 벡터와의 동치성 검증.
///
/// 같은 분해 로직이 Java(jammin·참조) / Dart(이 패키지) / TS(chominjungum-web)에
/// 존재한다. 하나라도 어긋나면 교실 모드와 온라인 모드의 채점이 달라진다.
///
/// 골든 파일: `chominjungum-web/golden/hangul-split.json`
/// 채집 방법: 같은 디렉토리의 `README.md` / `collect.mjs`
void main() {
  final goldenFile = File('../../../chominjungum-web/golden/hangul-split.json');

  group('jammin 골든 벡터 동치성', () {
    if (!goldenFile.existsSync()) {
      // chominjungum-web 저장소가 함께 체크아웃되지 않은 환경에서는 건너뛴다.
      test('골든 파일 없음 — 검증 생략', () {
        printOnFailure('golden not found at ${goldenFile.path}');
      }, skip: 'chominjungum-web/golden/hangul-split.json 없음');
      return;
    }

    final doc = jsonDecode(goldenFile.readAsStringSync()) as Map<String, Object?>;
    final cases = (doc['cases'] as List<dynamic>).cast<Map<String, Object?>>();

    test('골든 파일이 비어 있지 않다', () {
      expect(cases, isNotEmpty);
    });

    for (final c in cases) {
      final input = c['input'] as String;
      final expected = (c['expected'] as List<dynamic>)
          .map((e) => Map<String, Object?>.from(e as Map))
          .toList();

      test('addWordJson(${jsonEncode(input)}) — ${expected.length}글자', () {
        final actual = (jsonDecode(HangulUtil.addWordJson(input)) as List<dynamic>)
            .map((e) => Map<String, Object?>.from(e as Map))
            .toList();
        expect(actual, equals(expected));
      });
    }
  });
}
