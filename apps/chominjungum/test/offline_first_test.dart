import 'dart:io';

import 'package:chominjungum/domain/app_role.dart';
import 'package:chominjungum/services/dictation_composer.dart';
import 'package:chominjungum/providers/app_role_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hangul_core/hangul_core.dart';

/// **오프라인 우선**이 코드로 지켜지는지.
///
/// 이 앱의 전제는 "중앙 서버 없이 교실에서 돈다"이다. 그런데 09-07 에
/// **출제가 원격 jammin 서버에 묶여** 인터넷이 없으면 출제조차 못 하는 상태였다.
/// 전제는 주석으로 지켜지지 않으므로 여기서 강제한다.
void main() {
  group('핵심 경로가 네트워크를 타지 않는다', () {
    test('출제·채점이 자산과 계산만으로 끝난다', () {
      // 네트워크가 없어도 되는 것: 분해 → 문항 → 채점.
      final items = DictationComposer.composeAll('나비\n구름');
      expect(items, hasLength(2));
      final r = DictationCompare.score(
        expected: items.first.expectedText,
        actual: '나비',
      );
      expect(r.ratio, 1.0);
    });

    test('🔴HTTP 를 쓰는 파일은 둘뿐이고, 둘 다 교사 기능이다', () {
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final src = f.readAsStringSync();
        if (src.contains('package:http/') || src.contains('HttpClient(')) {
          offenders.add(f.path.replaceFirst('lib/', ''));
        }
      }
      offenders.sort();
      expect(
        offenders,
        [
          // 서버 업싱크 — 교사 화면에서만, 옵트인.
          'services/upsync_service.dart',
          // jammin 콘텐츠 갱신 — 교사 빌드에서만 버튼이 뜬다.
          'services/jammin_add_word_service.dart',
        ]..sort(),
        reason: '학생 경로에 외부 전송이 새로 생겼다. 정말 필요한지 다시 볼 것',
      );
    });

    test('🔴역할 기본값은 학생 — 잊으면 닫히는 쪽으로 떨어진다', () {
      // override 를 잊었을 때 교사 권한이 조용히 열리면 안 된다.
      // 학생 쪽이 더 제한적이다(외부 전송 없음).
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(appRoleProvider), AppRole.student);
    });
  });

  group('오프라인에 필요한 자산이 번들에 선언돼 있다', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    test('자모·글꼴·기본 단어장', () {
      for (final decl in const [
        'assets/hangul/',
        'assets/fonts/KCCDodamdodam-LICENSE.txt',
        'assets/data/default_dictation.json',
      ]) {
        expect(pubspec, contains(decl), reason: '$decl 선언이 빠졌다');
      }
    });

    test('자모 자산 83개가 실제로 있다', () {
      final n = Directory('assets/hangul')
          .listSync()
          .where((f) => f.path.endsWith('.svg'))
          .length;
      expect(n, 83);
    });

    test('기본 단어장이 네트워크 없이 읽힌다', () {
      final json = File('assets/data/default_dictation.json').readAsStringSync();
      expect(json, isNotEmpty);
    });
  });
}
