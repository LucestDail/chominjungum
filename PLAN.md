# 초민정음 MK2 (chominjungum) — 상세 구현 계획

## 1. 프로젝트 비전

jammin 웹 프로젝트의 개선된 모바일 특화 애플리케이션. **중앙 서버 없이** 교사 기기와 근거리 연동하여 받아쓰기·국어 학습을 지원하고, jammin과 호환되는 한글 분해 스키마로 출제·채점한다. (선택적으로 jammin 웹·API를 콘텐츠 제작용으로 활용)

## 2. 현재 상태

- **Dart/Flutter 모노레포** ([`pubspec.yaml`](pubspec.yaml) 워크스페이스): `packages/hangul_core`, `packages/sync_protocol`, `apps/chominjungum`
- **jammin 호환 한글 분해**: `hangul_core`에 `HangulUtil` / `HangulGlyph` 포팅 및 `DictationCompare` 채점
- **로컬 동기화 프로토콜**: `sync_protocol` — `SessionPairingPayload`(QR), `SyncEnvelope` + AES-GCM(`SyncCrypto`)
- **앱 MVP**: Material 3 테마, Riverpod, go_router, Hive 초기화, 교사 LAN WebSocket 허브 + 학생 QR 연결, 받아쓰기 화면(키보드 + ML Kit OCR), Android `student`/`teacher` productFlavors
- **기기 바인딩**: `flutter_secure_storage`에 UUID 기반 ID 저장 (`DeviceBindingId`)
- jammin **SVG·폰트** 자산은 아직 미연동 (경로만 계획에 유지)

## 3. 디자인 시스템

**Google Material Design 3 (M3) 준용 + jammin 색상/톤/패턴 계승**

### M3 + jammin 디자인 연계

jammin의 디자인 아이덴티티를 M3 프레임워크에 매핑:

### 컬러 시스템

jammin에서 계승하는 핵심 색상:
- **Primary**: `#ffc800` (골든 옐로우) — jammin의 `--bs-primary`
- **Success/CTA**: `#198754` (그린) — jammin의 CTA 버튼
- **Highlight**: `#fff4cc` — jammin의 하이라이트 배경

M3 토큰으로 확장:

| 토큰 | Light | Dark | 용도 |
|------|-------|------|------|
| Primary | `#6D5E00` | `#DBC66C` | 주요 액션 (jammin 골든 옐로우 M3 변환) |
| On Primary | `#FFFFFF` | `#383000` | Primary 위 텍스트 |
| Primary Container | `#FBE365` | `#514600` | 버튼, 선택 상태 |
| Secondary | `#006D3D` | `#6FDB9E` | CTA, 성공 (jammin 그린 M3 변환) |
| Secondary Container | `#93F7B9` | `#005229` | 정답, 완료 표시 |
| Tertiary | `#9C4234` | `#FFB4A6` | 오답, 교정 피드백 |
| Surface | `#FFFBFF` | `#1D1B16` | 카드/배경 |
| Error | `#BA1A1A` | `#FFB4AB` | 오류 |

> 교육 테마: jammin의 따뜻한 골든 옐로우를 M3 Dynamic Color 체계로 변환하여 밝고 친근한 학습 환경

### 타이포그래피
- **본문/학습 콘텐츠**: KCC-DodamdodamR (도담도담체) — jammin에서 계승
- **UI/네비게이션**: Pretendard (M3 권장)
- **한글 학습**: 교육용 큰 사이즈 (24sp+)
- M3 Type Scale 적용하되 교육 맥락에서 더 큰 폰트 사용

### 핵심 컴포넌트
- 학습 카드: M3 Elevated Card + 골든 옐로우 강조
- 받아쓰기: 풀스크린 학습 모드, 큰 입력 필드
- 획순 연습: 터치 캔버스 + SVG 가이드
- 성적표: M3 리스트 + 진행률 바
- 하단 내비: M3 Navigation Bar (학습/시험/자료/마이페이지)
- 채점 결과: ✓ (Secondary) / ✗ (Tertiary) 색상 구분
- `border-radius: 16px` (M3 Large — 아동 친화적 둥근 모서리)

### 학생/교사/부모 테마 분기
| 역할 | 강조 색상 | 분위기 |
|------|----------|--------|
| 학생 | Primary (골든 옐로우) | 밝고 즐거운 학습 |
| 교사 | Secondary (그린) | 차분하고 전문적인 관리 |
| 부모 | Tertiary (소프트 코랄) | 따뜻한 보호자 느낌 |

---

## 4. 아키텍처

**원칙**: 인터넷 상 **중앙 백엔드 없음**. 교실 단위 데이터는 각 기기에 저장하고, 동기화는 **교사 기기의 로컬 WebSocket 허브**(짧은 수명) 또는 **QR/파일**로만 수행한다.

```
┌──────────────────────────────────────────────────────────────┐
│                    chominjungum 모노레포                       │
│  packages/hangul_core   — jammin JSON 호환 분해·채점 (순수 Dart) │
│  packages/sync_protocol — 페어링·SyncEnvelope·AES-GCM          │
│  apps/chominjungum      — Flutter (교사/학생 엔트리 분리)        │
└──────────────────────────────────────────────────────────────┘
         │ QR(SessionPairingPayload)              │ 암호화 WS
         ▼                                        ▼
   ┌─────────────┐   LAN (동일 Wi-Fi)    ┌──────────────┐
   │ 교사 태블릿   │ ◄──── WebSocket ───► │ 학생 태블릿들  │
   │ LocalHub    │    (SyncEnvelope)     │ StudentHub   │
   └─────────────┘                       └──────────────┘
```

- **운영 동기화**: `LocalHubService` + `StudentHubClient` (`shelf` + `web_socket_channel`). 페이로드는 `SyncCrypto.seal` / `open`.
- **jammin 서버**(`POST /addWord` 등): 개발·콘텐츠 제작 시 **선택적** 호출만 고려. 앱 런타임 채점은 **`hangul_core` 온디바이스**로 수행.
- **멀티모달 AI / 외부 OCR**: 기본 off. 필요 시 **교사 기기**에서만 API 키를 두는 방식으로 확장 (학생 단말 외부 전송 최소화).

---

## 5. 단계별 구현 계획

### Phase 1 — Flutter 앱 기초 + 로컬 동기화 (진행 중)

**1.1 Flutter 프로젝트 초기화** (일부 완료)
- [x] Flutter 모노레포 워크스페이스 (`hangul_core`, `sync_protocol`, 앱)
- [x] M3 테마 (`lib/theme/app_theme.dart`)
- [ ] KCC-DodamdodamR 폰트 번들
- [x] Riverpod + `ProviderScope`
- [x] go_router
- [x] Hive 초기화 (`bootstrap.dart`)
- [x] Android productFlavors `student` / `teacher` (역할별 앱 ID)
- [x] 교사 엔트리: `lib/main_teacher.dart`, 학생: `lib/main.dart`

**실행 예** (역할은 엔트리 포인트로 구분, 빌드 변형은 flavor):
```bash
cd apps/chominjungum
flutter run --flavor student
flutter run --flavor teacher -t lib/main_teacher.dart
```

**1.2 인증 및 역할**
- [ ] 로그인/회원가입 (중앙 서버 없을 때는 **기기 바인딩 + 교실 페어링**만으로 충분한지 정책 확정)
- [x] 역할 분기: 교사(`AppRole.teacher`) / 학생(`AppRole.student`)
- [ ] (선택) jammin JWT — **로컬 우선 정책과 충돌 시 비활성 또는 개발 전용**

**1.3 한글·동기화 패키지**
- [x] `hangul_core` — jammin `addWord` JSON 호환 `HangulUtil.addWordJson`, `DictationCompare`
- [x] `sync_protocol` — `SessionPairingPayload`, `SyncEnvelope`, `SyncCrypto`
- [x] 교사 허브 MVP + 학생 WebSocket 클라이언트 (`LocalHubService`, `StudentHubClient`)

**1.4 기본 학습 화면 (학생 모드)**
- [x] 받아쓰기 연습 화면 — 키보드 채점 + 캔버스/갤러리 → ML Kit OCR → `hangul_core` 채점
- [ ] 하단 내비바 전체 탭 (학습 / 시험 / 자료 / 마이페이지)

### Phase 2 — 핵심 학습 기능 (5주)

**2.1 받아쓰기**
- [ ] 받아쓰기 모드 선택: 수동(교사 출제) / AI(자동 출제)
- [ ] AI 자동 출제 — 학년/단원/난이도별 Gemini 연동
- [ ] 음성 기반 받아쓰기:
  - TTS (`flutter_tts`) — 문제 읽어주기 (속도 조절 가능)
  - 학생 타이핑 입력
  - 자동 채점 (`hangul_core` 음절·자모 비교, OCR 후처리)
- [ ] 결과 화면: 정답(Secondary)/오답(Tertiary) 색상 구분
- [ ] 오답 노트 자동 생성

**2.2 획순 연습**
- [ ] jammin SVG 자산 활용
- [ ] 인터랙티브 SVG — 획순 애니메이션 재생
- [ ] 터치 따라쓰기 — `CustomPaint` 기반 드로잉 캔버스
- [ ] 획순 정확도 평가 (드로잉 경로 vs SVG 경로 비교)
- [ ] 피드백: "획이 조금 길어요", "순서가 달라요"

**2.3 AI 글씨체 교정**
- [ ] 터치/스타일러스 손글씨 입력
- [ ] AI 분석 (Gemini Vision API):
  - 비율, 균형, 크기 일관성
  - 정자체 대비 편차 분석
- [ ] 시각적 교정 피드백:
  - 잘못된 부분 빨간색 하이라이트
  - 모범 답안 오버레이
  - 개선 포인트 텍스트 설명

**2.4 긴글 연습**
- [ ] 단계별 문장 쓰기
- [ ] 알림장 쓰기 연습
- [ ] 맞춤법/띄어쓰기 AI 검사

### Phase 3 — 교사/부모 기능 + 실시간 (5주)

**3.1 교사 모드**
- [ ] 학급 생성/관리 — 학생 초대 (초대 코드)
- [ ] 받아쓰기 출제:
  - 수동 단어 입력
  - AI 추천 단어에서 선택
  - 학급 전체에 실시간 전송 (WebSocket)
- [ ] 실시간 시험 모니터링 — 응시 현황, 진행률
- [ ] 자동 채점 결과 확인
- [ ] 학급 통계 대시보드: 평균 정답률, 취약 자모 분석

**3.2 실시간 시험**
- [ ] WebSocket 기반 실시간 통신 (**교사 로컬 허브** 또는 동일 프로토콜의 향상된 전송 계층)
- [ ] 교사 출제 → 학생 기기에 즉시 표시
- [ ] 실시간 타이머 동기화
- [ ] 응시 완료 → 즉시 채점 → 결과 전송
- [ ] 재시험 기능

**3.3 부모 모드**
- [ ] 자녀 연결 (초대 코드)
- [ ] 학습 현황 대시보드: 주간 학습량, 정답률 추이
- [ ] 주간/월간 리포트 (AI 자동 생성)
- [ ] 교사 메시지 확인
- [ ] 가정 학습 과제 확인

**3.4 학습 이력 + 통계**
- [ ] 학생별 일별/주별/월별 학습 기록
- [ ] 취약 영역 분석 (어떤 자모, 어떤 유형에서 실수가 많은지)
- [ ] 진도 차트 (M3 Progress Indicator)
- [ ] 뱃지/레벨 시스템 (게이미피케이션)

### Phase 4 — 오프라인 + 카메라 + 안정화 (4주)

**4.1 오프라인 학습**
- [ ] 핵심 학습 데이터 로컬 캐시 (SVG, 단어 목록, 학습 자료)
- [ ] 오프라인 받아쓰기 (로컬 단어장 기반)
- [ ] 오프라인 획순 연습
- [ ] 재연결 시 **교사 기기와의 페어링**으로 이력 전달 (또는 로컬 백업 파일)

**4.2 카메라 OCR**
- [ ] 종이 학습지 촬영 → OCR 텍스트 추출
- [ ] AI 자동 채점 (촬영한 답안 vs 정답)
- [ ] 손글씨 인식 + 교정 피드백

**4.3 교안/학습지 자동 생성**
- [ ] AI가 단원별 학습 목표에 맞는 학습지 생성
- [ ] PDF 출력 기능
- [ ] 교사용 교안 템플릿

**4.4 앱 배포**
- [ ] iOS App Store 제출
- [ ] Google Play Store 제출
- [ ] 학교/교육청 배포용 MDM 대응

---

## 6. jammin 연동 (선택)

중앙 서버 없이 운영할 때 jammin은 **콘텐츠 제작 파이프라인**(웹에서 학습지 생성) 등 **오프라인·옵션**으로 둔다.

선택적으로 활용 가능한 jammin 측 기능:
- [ ] 웹 `POST /addWord`와 동일 스키마 검증용 통합 테스트
- [ ] DB·인증·WebSocket — **학교 단위 클라우드 배포를 도입할 때만** 검토

---

## 7. 기술 스택

| 구분 | 기술 |
|------|------|
| 프레임워크 | Flutter (iOS/Android) |
| 언어 | Dart |
| 상태 관리 | Riverpod |
| 라우팅 | go_router |
| HTTP (선택) | dio — jammin 등 외부 호출이 필요해질 때 |
| 실시간 | `web_socket_channel` + `shelf` — 교사 **로컬** 허브 |
| 로컬 저장소 | Hive + `flutter_secure_storage` (기기 바인딩 ID) |
| TTS | flutter_tts (예정) |
| 카메라/OCR | `google_mlkit_text_recognition`, `image_picker`, `mobile_scanner` |
| 동기화·암호화 | `sync_protocol`, `cryptography` — QR 페어링 + AES-GCM |
| 백엔드 | **없음** (기본). jammin 서버는 선택·개발용 |
