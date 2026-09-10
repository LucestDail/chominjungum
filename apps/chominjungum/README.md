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

## 지험지 자산 (`assets/hangul/` — 자모 SVG 83개)

[jammin](../../jammin) `static/hangul/` 이 **정본**이고, 앱 자산은 거기서 **변환해서** 만듭니다.

```bash
python3 tool/build_hangul_assets.py          # 원본 → 자산 갱신
python3 tool/build_hangul_assets.py --check  # 갱신 없이 어긋난 것만 보고
```

원본이 바뀌면 다시 돌리고 결과를 커밋합니다. 갱신 후에는 **골든 3장**(`test/goldens/`)을
눈으로 확인하세요. 원본 위치는 `JAMMIN_DIR` 로 지정할 수 있고, 없으면 워크스페이스
형제 저장소에서 찾습니다.

> 🔴 **`cp` 로 복사하면 안 됩니다.** 원본은 부위별로 크롭돼 viewBox 가 제각각이고
> (초성 419.5×218.3 · 중성 623.6×400.9 · 종성 623.6×221.1), 한 파일에 자모가 여러 개
> 들어 있어 CSS 로 하나만 보입니다. `flutter_svg` 는 그 CSS 를 못 읽습니다.
> 변환기가 **보이는 요소만 남기고 좌표는 손대지 않은 채** 전체 상자 좌표계로 옮깁니다.
>
> ⚠️ 2026-09-09 이전에는 여기에 `cp` + `scripts/inline_svg_styles.py` 절차가 적혀 있었고,
> 그 결과 **자모 83개가 전부 원본과 다른 그림**이었습니다(ㄱ 기준 좌표 2.5% 오차).
> 같은 문항인데 앱과 웹의 학습지가 달랐습니다. `scripts/` 의 옛 스크립트는 **쓰지 마세요.**

자산이 원본에서 나온 것인지는 `test/hangul_assets_provenance_test.dart` 가 강제합니다.

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
