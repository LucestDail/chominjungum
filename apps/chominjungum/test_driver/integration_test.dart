import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

/// 실기기 통합 테스트가 넘긴 측정값을 **호스트 파일로** 떨군다.
///
/// 기기 안에서만 재고 로그로 흘려보내면 대조를 눈으로 하게 된다. `reportData`
/// 로 받아 파일에 적으면 `tool/compare_glyph_ink.py` 가 기계적으로 비교한다.
Future<void> main() => integrationDriver(
      responseDataCallback: (Map<String, dynamic>? data) async {
        if (data == null) return;
        for (final entry in data.entries) {
          final file = File('build/${entry.key}.json');
          file.parent.createSync(recursive: true);
          file.writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(entry.value),
          );
          stdout.writeln('기록: ${file.path}');
        }
      },
    );
