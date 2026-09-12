import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'classroom_roundtrip_test.dart' as classroom_roundtrip;
import 'glyph_device_render_test.dart' as glyph_device_render;
import 'late_additions_device_test.dart' as late_additions;
import 'new_features_device_test.dart' as new_features;

/// 실기기 통합 테스트 **전부를 한 번의 설치로** 돌린다.
///
/// ## 왜 이 파일이 있나 (2026-09-12)
///
/// `flutter drive` 는 실행할 때마다 앱을 **지웠다 다시 설치한다**. 그런데 이 앱은
/// 개인 Apple ID 무료 프로비저닝으로 서명되고, 무료 서명은 **그 개발자의 앱이
/// 기기에서 사라지면 신뢰 항목도 같이 날아간다**. 그래서 파일 하나당 한 번씩
/// 돌리면 설치할 때마다
///
///     설정 > 일반 > VPN 및 기기 관리 > 개발자 앱 > 신뢰
///
/// 를 **사람이 눌러 줘야 한다.** 테스트 4개 = 탭 4번이고, 자리를 비우면 거기서 멈춘다.
/// 실제로 09-12 에 그 짓을 하다 중단됐다.
///
/// 하나로 묶으면 **설치 1회 · 신뢰 1회**로 전부 돈다.
/// (유료 개발자 계정이면 인증서가 1년짜리라 이 문제 자체가 없다.)
///
/// ## 쓰는 법
///
/// ```bash
/// flutter drive --driver=test_driver/integration_test.dart \
///   --target=integration_test/all_device_tests.dart -d <기기>
/// python3 tool/compare_glyph_ink.py        # 자모 렌더 대조(호스트 기준선 필요)
/// ```
///
/// ## 왜 `group()` 으로 감싸나
///
/// 네 파일 모두 `main()` 안에서 `setUpAll`/`tearDown` 을 top-level 로 등록한다.
/// 그냥 나란히 부르면 그 훅들이 **전역으로 합쳐져** 서로의 테스트에도 걸린다.
/// `group()` 안에서 부르면 훅이 그 묶음에만 적용된다.
///
/// ## 들어 있지 않은 것
///
/// `live_device_hub_test.dart` 는 **대화형**이다 — 허브를 6분간 띄워 두고 사람이
/// 다른 기기로 QR 을 찍기를 기다린다. 무인 실행에 섞으면 6분을 그냥 태운다.
///
/// ⚠️`glyph_device_render` 는 측정값을 `binding.reportData` 로 넘기고 드라이버가
/// `build/glyph_ink_device.json` 에 적는다. **이 파일을 시뮬레이터로 돌리면 그
/// 측정값이 시뮬레이터 것으로 덮인다** — 실기기 대조용 파일이므로, 합본을
/// 시뮬레이터에서 예행 연습했다면 그 산출물은 지우고 기기로 다시 뜰 것.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('classroom_roundtrip', classroom_roundtrip.main);
  group('new_features', new_features.main);
  group('late_additions', late_additions.main);
  group('glyph_device_render', glyph_device_render.main);
}
