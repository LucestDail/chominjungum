# chominjungum (Flutter 앱)

모노레포의 메인 앱 패키지입니다. 프로젝트 개요·아키텍처·실행 방법은 **[루트 README](../../README.md)** 를 참고하세요. 받아쓰기 손글씨 캔버스 구조·성능 최적화·다음 할 일은 루트 README의 **「작업 로그」**, **「다음 작업」** 섹션을 참고하세요.

```bash
# 학생 (Android, USB 연결 태블릿)
./scripts/android_run.sh
# 또는
flutter run --flavor student -d <기기ID>

# 교사 (Android)
flutter run --flavor teacher -t lib/main_teacher.dart

# iOS
./scripts/ios_run.sh
```

Android 빌드는 `android/pubspec.yaml`·`android/lib`·`android/assets` 심볼릭 링크가 필요합니다. `android_run.sh`가 자동으로 만듭니다.

## 배포 (학생 APK)

```bash
cd apps/chominjungum
./scripts/android_run.sh   # 링크 생성 (최초 1회)
flutter build apk --flavor student --debug
adb install -r build/app/outputs/flutter-apk/app-student-debug.apk
adb shell am start -n com.chominjungum.chominjungum.student/com.chominjungum.chominjungum.MainActivity
```

지험지 SVG는 [jammin](../../jammin) `static/hangul/` 과 동일 자산을 `assets/hangul/` 에 둡니다.

jammin에서 SVG를 다시 복사한 뒤 **반드시** CSS 인라인 스크립트를 실행하세요 (Flutter `flutter_svg`는 `<style>` 미지원):

```bash
cp ../../jammin/src/main/resources/static/hangul/*.svg assets/hangul/
python3 scripts/inline_svg_styles.py assets/hangul
```

## jammin 서버 연동

기본 연습 문장: **안녕하세요**, **강아지와고양이**

```
POST https://xn--lg3by0shrak2n.com/addWord
{"requestWord":"안녕하세요"}
```

응답 JSON(자모 코드)을 지험지 셀에 사용합니다. `lib/services/jammin_add_word_service.dart`

## 디자인 (jammin 웹과 동일)

- 색: `#296429` 브랜드 초록 (`lib/theme/jammin_tokens.dart` ← `jammin-tokens.css`)
- 폰트: KCC 도담도담체 (`assets/fonts/KCCDodamdodamR.ttf`)
- 레이아웃: `widgets/jammin/` — 내비·섹션 제목·시험지 헤더·`#box2` 스타일
