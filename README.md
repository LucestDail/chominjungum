# 초민정음 MK2 (chominjungum)

> [jammin](../jammin)(초민정음) 웹의 **모바일 특화** 버전. 초등 한글 **받아쓰기**를 중심으로, **중앙 서버 없이** 교사·학생 기기가 같은 Wi‑Fi에서 직접 동기화하는 Flutter 앱입니다.

## 배경

[jammin](https://github.com/)은 Spring Boot + Thymeleaf 기반 웹으로 받아쓰기 학습지 생성·한글 분해(`POST /addWord`)를 제공합니다. chominjungum은 그 **데이터 모델(음절·자모 JSON)** 을 공유하면서, 교실 현장에 맞게 다음을 목표로 합니다.

- 태블릿·스타일러스/터치에 맞는 **모바일 UI**
- 학습·출제 데이터는 **각 기기에만** 보관 (물리적 기기 바인딩 ID)
- **교사 기기 로컬 허브**로만 동기화 (클라우드 백엔드 없음)

## 현재 구현 상태 (요약)

| 영역 | 상태 |
|------|------|
| Flutter 모노레포 + M3 테마 | ✅ |
| jammin 호환 한글 분해·채점 (`hangul_core`) | ✅ |
| 로컬 동기화·암호화 (`sync_protocol`) | ✅ |
| 교사 LAN WebSocket 허브 + 학생 QR 연결 | ✅ MVP |
| 받아쓰기 연습 (키보드 + ML Kit OCR) | ✅ MVP |
| 받아쓰기 손글씨 캔버스 (SVG 가이드 + 셀별 펜) | ✅ (성능 최적화 1차) |
| Android `student` / `teacher` flavor | ✅ |
| iOS 빌드 (Podfile, iOS 15.5+) | ✅ (시뮬레이터 런타임은 Xcode에서 별도 설치) |
| jammin SVG (받아쓰기 가이드) | ✅ 번들 (`assets/hangul/*.svg`) |
| jammin 도담도담체 폰트 | ⏳ 미연동 |
| 학생 손글씨 → OCR/채점 연결 | ⏳ 셀별 stroke만 있고 인식·채점 미연동 |
| 학생 답안 → 교사 전송 (`attempt.submit`) | ⏳ 프로토콜만 정의 |
| 로그인·학급 DB·AI 출제·부모 모드 | ⏳ [PLAN.md](PLAN.md) 참고 |

상세 로드맵·디자인 토큰은 [PLAN.md](PLAN.md)를 참고하세요.

## 아키텍처

**원칙:** 인터넷 상 중앙 백엔드 없음. 교실 단위로 교사 태블릿이 **짧은 수명의 WebSocket 허브**를 띄우고, 학생 기기는 QR로 세션 정보를 받아 연결합니다.

```
packages/hangul_core     — jammin Hangul JSON 호환 분해·음절 채점 (순수 Dart)
packages/sync_protocol   — QR 페어링, SyncEnvelope, AES-GCM
apps/chominjungum        — Flutter 앱 (학생 / 교사 엔트리 분리)
```

```
교사 앱 ── QR(SessionPairingPayload) ──► 학생 앱
    │                                      │
    └── LAN WebSocket (암호화 SyncEnvelope) ─┘
         ws://<교사IP>:30020/
```

- 런타임 채점: `hangul_core` (`DictationCompare`) — jammin `addWord`와 동일 스키마
- jammin 서버 API: **선택** (개발·콘텐츠 제작용). 운영 동기화는 로컬 허브만 사용

## 저장소 구조

```
chominjungum/
├── pubspec.yaml              # Dart workspace 루트
├── PLAN.md                   # 상세 설계·로드맵
├── packages/
│   ├── hangul_core/          # HangulUtil, HangulGlyph, DictationCompare
│   └── sync_protocol/        # SyncDefaults, SessionPairingPayload, SyncCrypto
└── apps/
    └── chominjungum/         # Flutter 앱
        ├── lib/
        │   ├── main.dart              # 학생 (AppRole.student)
        │   ├── main_teacher.dart      # 교사 (AppRole.teacher)
        │   ├── features/
        │   │   ├── teacher/           # 허브·QR·문제 전송
        │   │   ├── student/           # QR 스캔·허브 연결
        │   │   └── dictation/         # 받아쓰기 연습·채점
        │   └── services/              # LocalHub, OCR, DeviceBindingId
        └── scripts/ios_run.sh         # pod install + flutter run -d ios
```

## 현재 기능

### 공통 (`hangul_core`)

- jammin `HangulUtil` / `Hangul#toJSON`과 호환되는 **음절·자모 분해**
- `DictationCompare`: 정답 문자열 vs 학생 답안(키보드/OCR 정규화 텍스트) **음절 단위 채점**·오답 사유

### 동기화 (`sync_protocol`)

- `SessionPairingPayload`: QR/붙여넣기로 교환 (세션 ID, 교사 IP, 포트, 세션 키)
- `SyncEnvelope` + `SyncCrypto`: AES-GCM으로 문제 패키지 등 암호화 전송
- 기본 허브 포트: **`SyncDefaults.hubPort` = 30020** (30000번대)

### 교사 앱

- **허브 시작/중지**: 동일 Wi‑Fi에서 `0.0.0.0:30020` WebSocket 수신
- **QR 표시**: 학생이 스캔해 `hubHost`·세션 키 수신
- **받아쓰기 출제**: 문장 입력 → `DictationPackage` 암호화 브로드캐스트
- 로컬에서 학습 화면 미리보기

### 학생 앱

- **QR 스캔** 또는 페이로드 JSON 붙여넣기로 허브 연결
- 교사가 문제 전송 시 **받아쓰기 화면**으로 이동
- **로컬 샘플** 받아쓰기 (허브 없이 `가나다` 등)

### 받아쓰기 연습 화면

- **키보드 입력** → 즉시 `hangul_core` 채점 (정답률·글자별 ✓/✗)
- **손글씨 캔버스** → PNG → ML Kit 한국어 OCR → 채점
- **갤러리 이미지** OCR → 채점
- 기기별 **`DeviceBindingId`** (Secure Storage UUID) 표시

### Android 빌드 변형

| Flavor | applicationId suffix | 앱 이름 |
|--------|----------------------|---------|
| `student` | `.student` | 초민정음 학생 |
| `teacher` | `.teacher` | 초민정음 교사 |

iOS는 flavor 없이 엔트리(`main.dart` / `main_teacher.dart`)로 역할을 구분합니다.

## 기술 스택 (현재)

| 구분 | 기술 |
|------|------|
| 앱 | Flutter 3.x, Dart 3.5+ |
| UI | Material 3 (jammin 골든 옐로우 톤) |
| 상태·라우팅 | Riverpod, go_router |
| 로컬 저장 | Hive (초기화만), flutter_secure_storage (기기 ID) |
| 동기화 | shelf + web_socket_channel, sync_protocol + cryptography |
| OCR | google_mlkit_text_recognition, image_picker |
| QR | qr_flutter, mobile_scanner |
| 플랫폼 | Android, iOS |

## 개발 환경

### 사전 요구

- Flutter SDK (stable)
- **Android**: Android SDK (API 36 권장), `ANDROID_HOME` 설정
- **iOS**: Xcode, CocoaPods, iOS 15.5+ deployment target, 시뮬레이터 런타임(Xcode → Settings → Platforms)

### 의존성

```bash
cd /path/to/chominjungum
dart pub get
# 또는 앱 디렉터리에서
cd apps/chominjungum && flutter pub get
```

### 테스트 (패키지)

```bash
dart test packages/hangul_core packages/sync_protocol
cd apps/chominjungum && flutter analyze && flutter test
```

### 앱 실행

**Android — 학생**

```bash
cd apps/chominjungum
flutter run --flavor student
```

**Android — 교사**

```bash
flutter run --flavor teacher -t lib/main_teacher.dart
```

**iOS** (CocoaPods·UTF-8 로케일 필요)

```bash
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
./scripts/ios_run.sh
# 또는
cd ios && pod install && cd .. && flutter run -d ios
# 교사: flutter run -d ios -t lib/main_teacher.dart
```

### 네트워크·포트

| 용도 | 포트 | 비고 |
|------|------|------|
| 교사 로컬 WebSocket 허브 | **30020** | `packages/sync_protocol` → `SyncDefaults.hubPort` |
| 중앙 API 서버 | 없음 | jammin 서버는 앱 런타임에 필수 아님 |

교사·학생이 **같은 Wi‑Fi**에 있어야 하며, 방화벽에서 **30020/TCP**가 막히지 않아야 합니다.

### 교실에서 사용 흐름 (MVP)

1. 교사 앱: **허브 시작** → QR 표시 (IP가 비어 있으면 수동 IP 입력)
2. 학생 앱: **QR 스캔** 또는 JSON 붙여넣기 → 연결
3. 교사: 받아쓰기 문장 입력 → **문제 전송**
4. 학생: 받아쓰기 화면에서 키보드 또는 캔버스/OCR로 답 → **채점**

## jammin과의 관계

| jammin (웹) | chominjungum (모바일) |
|-------------|------------------------|
| `POST /addWord` 서버 분해 | `hangul_core` 온디바이스 분해 |
| 받아쓰기 워크시트 UI (JS) | Flutter 받아쓰기·캔버스 |
| (향후) 중앙 DB·인증 | 기기 로컬 + LAN 허브 |

jammin의 **SVG 획순·도담도담체** 등 자산은 추후 번들 예정입니다.

## 알려진 제한 (MVP)

- 학생 **채점 결과가 교사 기기로 전송되지 않음** (`attempt.submit` 프로토콜만 정의)
- 학습 이력 **Hive Box 미구현** (init만 됨)
- QR에 **세션 키가 평문**으로 포함 (`ws://` 평문 WebSocket)
- API 키·외부 AI **미연동**

## 향후 계획

단계별 작업 목록·완료 기준은 **[PLAN.md](PLAN.md)** 를 참고하세요.

| 단계 | 요약 |
|------|------|
| Phase 1 | 답안 제출·교사 확인, 이력 저장, 보안·UX 마무리 |
| Phase 2 | TTS, 획순, OCR·다문항, (선택) AI |
| Phase 3 | 학급·통계, 오프라인 번들, 부모 모드 |
| Phase 4 | 스토어 배포, jammin 자산·PDF |

## 작업 로그 — 받아쓰기 캔버스 (2026-05-19)

받아쓰기 화면의 셀별 손글씨 캔버스를 처음으로 실사용 가능 수준으로 만들었습니다.

**원인이 됐던 핵심 버그**: `HangulWritingWorksheet.didUpdateWidget`이 `glyphs` List를 reference(`!=`)로 비교 → `dictationItemGlyphs(item)`이 매번 새 List라 모든 `setState`마다 `_resetGlyphs()` → cell GlobalKey 새로 생성 → cell State(점·strokes) 즉시 reset. cell의 콜백은 호출되는데도 화면에는 항상 빈 캔버스로 보임. `listEquals` 비교로 수정.

**셀(`HangulWritingCell`) 최종 구조**

| 레이어 | 책임 | 비고 |
|--------|------|------|
| `GestureDetector(HitTestBehavior.opaque)` | tap/pan 수신 | parent scroll보다 우선 |
| `Container(border + white)` | 셀 배경 + 선택 강조 | brand 색 굵은 테두리 |
| `RepaintBoundary > IgnorePointer > HangulGlyphCell` | jammin SVG 초·중·종 가이드 | stroke 변경 시 repaint 0 |
| `RepaintBoundary > IgnorePointer > CustomPaint(_StrokePainter, repaint: ChangeNotifier)` | 학생 stroke 페인터 | cell rebuild 없이 paint만 trigger |

**성능 최적화**

- `CustomPainter(repaint: Listenable)` 직접 wiring → `ValueListenableBuilder` 제거, element rebuild 0
- `Paint` 객체 `static final`로 1회 생성
- stroke point sampling (`distanceSquared < 1.0` skip) — paint 부담 절반↓
- `onTapUp`에서 점(dot) 처리 — `PanGestureRecognizer` slop(18px)에 못 미치는 짧은 터치도 점으로 찍힘
- `onSelected` 중복 `setState` 차단 (cell + worksheet 양쪽)

## 다음 작업 (Next Up)

받아쓰기 캔버스 본체는 안정화됐고, 다음 단계는 OCR/제출 파이프라인과 마감 작업입니다.

- [ ] 셀별 stroke를 PNG로 export → 기존 `ml_kit` OCR 파이프라인에 투입 → cell별 인식 결과를 jammin 채점에 합치기
- [ ] 학생 채점 완료 → `SyncMessageTypes.attemptSubmit`으로 교사 허브 전송 (`PLAN.md` 1.1)
- [ ] 교사 화면: 접속 학생 수·최근 제출·점수 요약 카드
- [ ] Hive Box 설계 + 본인 시도 이력 로컬 저장 (`PLAN.md` 1.2)
- [ ] 받아쓰기 전용 결과 화면 (오답 글자 하이라이트)
- [ ] KCC 도담도담체 폰트 등록 + `assets/fonts/KCCDodamdodamR.ttf` 적용
- [ ] 받아쓰기 화면 `_dictationMode` 토글(가이드 on/off) UX 마무리
- [ ] (선택) 완료된 stroke들을 `ui.Picture`로 cache — 현재 그리는 stroke만 새로 그리는 한 단계 더 강한 최적화
- [ ] (선택) Impeller 끄고 Skia로 비교 (Lenovo 태블릿 stutter 검증)
- [ ] 디버그 흔적 점검 (`debugPrint`, 빨간색 페인터 잔여물 등 grep)

## 라이선스

MIT
