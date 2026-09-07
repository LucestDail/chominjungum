import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 플랫폼 선언 가드 — **실기기에서만 드러나는** 전제를 코드로 잠근다.
///
/// 이 앱은 교사 기기가 LAN WebSocket 허브를 띄우고 학생 기기가 평문 `ws://` 로
/// 직접 붙는 구조다. 그래서 OS 두 곳의 선언에 의존하는데, 둘 다
/// **시뮬레이터·에뮬레이터에서는 없어도 통과**하고 실제 교실에서만 실패한다.
/// Info.plist / AndroidManifest 가 재생성되거나 Flutter 업그레이드로 덮어써지면
/// 조용히 사라지므로, 여기서 존재를 강제한다.
void main() {
  group('iOS Info.plist', () {
    final plist = File('ios/Runner/Info.plist');

    test('파일이 있다', () {
      expect(plist.existsSync(), isTrue, reason: '경로가 바뀌었으면 이 테스트를 갱신할 것');
    });

    test('NSLocalNetworkUsageDescription 이 있다 — 없으면 학생이 허브에 못 붙는다', () {
      final xml = plist.readAsStringSync();
      expect(
        xml.contains('<key>NSLocalNetworkUsageDescription</key>'),
        isTrue,
        reason: 'iOS 14+ 는 이 문구가 없으면 로컬 네트워크 접속을 아예 허용하지 않는다. '
            '시뮬레이터에는 이 제약이 없어 빠져도 통과하지만 실기기 교실 왕복이 막힌다.',
      );
      // 키만 있고 문구가 비면 iOS 가 거부한다.
      final m = RegExp(
        r'<key>NSLocalNetworkUsageDescription</key>\s*<string>([^<]*)</string>',
      ).firstMatch(xml);
      expect(m, isNotNull, reason: '문구(<string>)가 뒤따라야 한다');
      expect(m!.group(1)!.trim(), isNotEmpty, reason: '설명 문구가 비어 있으면 안 된다');
    });

    test('NSCameraUsageDescription 이 있다 — QR 스캔', () {
      expect(
        plist.readAsStringSync().contains('<key>NSCameraUsageDescription</key>'),
        isTrue,
      );
    });

    test('쓰지 않는 권한을 요구하지 않는다', () {
      // image_picker 제거(2026-09-07)로 갤러리 접근이 없다.
      expect(
        plist.readAsStringSync().contains('NSPhotoLibraryUsageDescription'),
        isFalse,
        reason: '쓰지 않는 권한 선언은 심사 리젝 사유이고 사용자에게도 오해를 준다',
      );
    });
  });

  group('AndroidManifest', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml');

    test('파일이 있다', () {
      expect(manifest.existsSync(), isTrue);
    });

    test('평문 트래픽이 허용된다 — 교실 허브는 ws:// 다', () {
      expect(
        manifest.readAsStringSync().contains('android:usesCleartextTraffic="true"'),
        isTrue,
        reason: 'Android 9+ 는 평문을 기본 차단한다. 교사 기기에 TLS 인증서가 없으므로 '
            '허브는 평문 ws:// 이고, 이 플래그가 없으면 학생이 연결하지 못한다.',
      );
    });

    test('INTERNET·CAMERA 권한이 있다', () {
      final xml = manifest.readAsStringSync();
      expect(xml.contains('android.permission.INTERNET'), isTrue);
      expect(xml.contains('android.permission.CAMERA'), isTrue);
    });

    test('쓰지 않는 권한을 요구하지 않는다', () {
      final xml = manifest.readAsStringSync();
      expect(xml.contains('READ_MEDIA_IMAGES'), isFalse);
      expect(xml.contains('READ_EXTERNAL_STORAGE'), isFalse);
    });
  });
}
