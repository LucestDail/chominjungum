# 초민정음 MK2 (chominjungum) — 구현 계획

> 최종 갱신: 현재 코드베이스 기준. 개요·실행 방법은 [README.md](README.md).

---

## 1. 프로젝트 비전

[jammin](../jammin) 웹의 **모바일 특화** 앱. 초등 **받아쓰기**를 중심으로, **중앙 서버 없이** 교사·학생 기기가 같은 Wi‑Fi에서 직접 동기화한다.

- jammin `POST /addWord`와 동일한 **음절·자모 JSON**으로 출제·채점
- 학습 데이터는 **기기 로컬** + 교실 LAN 허브 (클라우드 백엔드 기본 없음)
- AI·외부 API는 **기본 off**, 필요 시 교사 기기에서만 옵션

---

## 2. 현재 구현된 기능 (As-Is)

### 2.1 모노레포

| 패키지/앱 | 역할 | 상태 |
|-----------|------|------|
| `packages/hangul_core` | jammin `HangulUtil`/`Hangul` JSON 호환 분해, `DictationCompare` 채점 | ✅ |
| `packages/sync_protocol` | `SyncDefaults`(포트 30020), `SessionPairingPayload`, `SyncEnvelope`, AES-GCM | ✅ |
| `apps/chominjungum` | Flutter UI·허브·받아쓰기 | ✅ MVP |

### 2.2 `hangul_core`

- `HangulUtil.hangulSplit` / `isHangul` / `addWordJson` — jammin 서버 응답 형식과 호환
- `DictationCompare.score` — 음절 단위 정답률, 글자별 ✓/✗, 누락·초과 입력 사유
- 단위 테스트: `packages/hangul_core/test/hangul_util_test.dart`

### 2.3 `sync_protocol`

- **페어링**: `SessionPairingPayload` (QR/JSON) — `sessionId`, `hubHost`, `hubPort`, `publicKeyB64`(실제로는 **대칭 세션 키**)
- **전송**: `SyncEnvelope` + `SyncCrypto` (AES-GCM)
- **메시지**: `dictation.package`(교사→학생 브로드캐스트), `attempt.submit`(학생→교사, `AttemptSubmitPayload`) 앱 연동 완료. `ack`는 타입만 정의

### 2.4 Flutter 앱 — 공통

| 항목 | 구현 |
|------|------|
| jammin 디자인 토큰·KCC 도담도담체·레이아웃 | `lib/theme/jammin_tokens.dart`, `app_theme.dart`, `widgets/jammin/*` |
| Riverpod | `ProviderScope`, `dictationPackageProvider` |
| go_router | `/`, `/practice` |
| Hive | `initFlutter()`만 — **Box·영속 저장 미사용** |
| 기기 ID | `DeviceBindingId` → Secure Storage UUID |
| 엔트리 | 학생 `main.dart`, 교사 `main_teacher.dart` |

### 2.5 교사 앱 (`TeacherHomeScreen`)

- LAN WebSocket 허브 (`LocalHubService`, `0.0.0.0:30020`)
- Wi‑Fi IP 자동 조회 + 수동 IP 입력
- QR + 페이로드 JSON 화면 표시
- 받아쓰기 문장 입력 → `DictationPackage` 암호화 브로드캐스트
- 학습 화면 미리보기 (`/practice`)
- **제출 현황판**: 접속 학생 수·제출 건수·평균 점수 + 제출 목록(기기ID 축약·답안·정답·점수·시각). 같은 기기+같은 문항 재제출은 최신 것으로 대체

### 2.6 학생 앱 (`StudentHomeScreen`)

- QR 스캔 (`mobile_scanner` 7.x) 또는 JSON 붙여넣기 → `StudentHubClient`
- `dictation.package` 수신 시 Provider 갱신 + `/practice` 이동
- 허브 없이 로컬 샘플 받아쓰기

### 2.7 받아쓰기 (`DictationPracticeScreen`)

- jammin `static/hangul/*.svg` → `assets/hangul/` + `HangulWorksheet` / `HangulGlyphCell` (editor 프로필)
- 지험지 위 손글씨 워크시트 (받아쓰기 모드·획순 가이드 토글, 펜/지우개) — 학생·교사 공용 화면
- **채점·제출 시트** (`AttemptSubmitSheet`, 앱바 ✅ 버튼): 문항별 답안 입력 → `DictationCompare` 온디바이스 채점 → 점수%·글자별 ✓/✗·정답 표시 → 허브 연결 시 `attempt.submit` 암호화 제출
- ⚠️ **OCR UI 없음** (`OcrService`는 존재하나 화면 미연결), 손글씨 자동 채점 없음 (키보드 입력만 채점)

### 2.8 플랫폼

| 플랫폼 | 상태 |
|--------|------|
| Android | `student` / `teacher` productFlavors, `usesCleartextTraffic` (ws용) |
| iOS | Podfile, iOS 15.5+, `pod install` — flavor 없음, 엔트리로 역할 구분 |
| macOS / Web | 타깃 없음 |

### 2.9 미구현 (코드 없음)

- 학습 이력 **Hive/DB 저장** (제출 목록은 교사 앱 메모리에만 — 앱 종료 시 소멸)
- 손글씨 → OCR 자동 채점 (`OcrService` 화면 미연결)
- 하단 내비·홈·시험·자료·마이페이지
- TTS, 획순, AI 출제/교정, 부모 모드, 학급 관리
- jammin SVG·도담도담체 폰트 번들
- jammin 서버 HTTP 클라이언트
- Release 서명·스토어 배포

---

## 3. 알려진 제한·기술 부채

우선순위 높음 (교실 파일럿 전):

| 이슈 | 설명 | 권장 조치 |
|------|------|----------|
| 세션 키 QR 평문 | `publicKeyB64`에 대칭 키가 QR/화면에 노출 | 키 교환 분리 또는 QR에는 일회용 토큰만 |
| `ws://` 평문 | Android cleartext, LAN 스니핑 가능 | 교실망 한정 문서화 또는 `wss` 검토 |
| 페이로드 화면 노출 | 교사 화면 `SelectableText`에 전체 JSON | QR만 표시, JSON은 개발자 메뉴로 |
| 기기 ID UI 노출 | 받아쓰기 화면에 UUID 표시 | 설정/디버그로 이동 또는 제거 |
| Hive 미사용 | init만 됨 (제출 목록도 메모리 휘발) | Box 설계 후 시도·이력 저장 |

기타:

- iOS 시뮬레이터: ML Kit / arm64 제약 — 실기기 테스트 권장
- Android release: debug 서명 사용 중
- 루트 `.gitignore`에 `.env*` 없음 — API 키 도입 시 추가

---

## 4. 아키텍처 (유지)

```
packages/hangul_core     ← jammin 호환 분해·채점
packages/sync_protocol   ← 페어링·암호화 envelope
apps/chominjungum        ← UI·허브·OCR

교사 ── QR(SessionPairingPayload) ──► 학생
     └── ws://<IP>:30020/ (SyncEnvelope + AES-GCM) ──┘
```

- 채점: 항상 **온디바이스** `hangul_core`
- jammin 서버: **선택** (콘텐츠 제작·스키마 검증용)

---

## 5. 디자인 시스템 (참고)

M3 + jammin 톤. 상세 토큰은 기존 설계 유지.

| 토큰 | Light | 용도 |
|------|-------|------|
| Primary | `#6D5E00` / Container `#FBE365` | 학생·주요 액션 |
| Secondary | `#006D3D` / Container `#93F7B9` | 정답·교사 CTA |
| Tertiary | `#9C4234` | 오답·교정 |

- 폰트: UI 기본 + **(미연동)** KCC 도담도담체
- 채점 UI: Secondary ✓ / Tertiary ✗ (연습 화면에 부분 적용, 전용 결과 화면 없음)

---

## 6. 앞으로 할 일 (로드맵)

### Phase 1 — MVP 마무리 (교실 파일럿 가능 수준)

**1.1 동기화·보안**

- [x] 학생 채점 완료 → `SyncMessageTypes.attemptSubmit`으로 교사 허브 전송 (2026-09-02)
- [x] 교사 화면: 접속 학생 수·최근 제출·점수 요약 (최소 리스트) (2026-09-02)
- [ ] QR 페이로드에서 세션 키 노출 방식 개선 (일회용 페어링 코드 + 키는 WS 핸드셰이크)
- [ ] 교사 화면 JSON 전체 노출 제거 또는 개발 모드로 분리
- [ ] (선택) 허브 바인딩 IP·포트 설정 UI

**1.2 데이터 영속화**

- [ ] Hive Box 설계: `DictationItem`, `DictationAttempt`, `deviceBindingId` 네임스페이스
- [ ] 학생: 수신 문제·본인 시도 이력 로컬 저장
- [ ] 교사: 출제 이력·학생 제출 스냅샷 저장 (허브 세션 단위)

**1.3 UX·앱 골격**

- [ ] 하단 Navigation Bar: 홈 / 받아쓰기 / (시험·자료 placeholder) / 설정
- [ ] 받아쓰기 전용 **결과 화면** (M3 Secondary/Tertiary, 오답 글자 하이라이트)
- [ ] KCC 도담도담체 assets 등록
- [ ] 기기 ID 화면 표시 제거 또는 설정으로 이동
- [ ] iOS productFlavors 또는 스킴 정리 (교사/학생 앱 아이콘·이름)

**1.4 품질·배포 준비**

- [ ] `hangul_core` ↔ jammin `addWord` 골든 테스트 (동일 입력 JSON diff)
- [x] 통합 테스트: 허브 → 수신 → 채점 → 제출 E2E (2026-09-02, `test/hub_attempt_flow_test.dart`·`test/attempt_submit_e2e_test.dart`. ⚠️실제 소켓 I/O는 `tester.runAsync` 안에서만 진행됨)
- [ ] Android release keystore·서명 분리
- [ ] README/PLAN과 실제 동작 정기 동기화

**Phase 1 완료 기준:** 교사 1대 + 학생 N대, 같은 Wi‑Fi에서 출제 → 응시 → 채점 → **교사가 제출·점수 확인**까지 한 사이클.

> **2026-09-02 진행**: 출제 → 수신 → 채점 → 제출 → 교사 수신 경로를 구현하고 자동 테스트로 증명(앱 9 + 패키지 11 GREEN). **남은 확인 = 실기기 2대 교실 리허설** — 교사 현황판 렌더는 위젯 테스트가 아니라 실기기로 봐야 한다(`NetworkInfo`·실허브 의존).

---

### Phase 2 — 받아쓰기·학습 기능 강화

**2.1 받아쓰기**

- [ ] 다문항 `DictationPackage` (현재는 첫 항목 위주)
- [ ] TTS 문제 읽기 (`flutter_tts`, 속도 조절)
- [ ] 오답 노트 (로컬, 자모/음절별 취약 분석)
- [ ] 교사: jammin 스타일 **자모 가리기 옵션** 출제 (hidebox 개념 포팅)

**2.2 OCR·입력**

- [ ] 카메라 직접 촬영 → OCR (현재 갤러리·캔버스만)
- [ ] OCR 후처리 (공백·자모 정규화) 공통 유틸
- [ ] 손글씨 인식 품질 개선 (해상도·전처리)

**2.3 획순 연습**

- [ ] jammin SVG 자산 번들
- [ ] 획순 가이드·따라쓰기 캔버스
- [ ] 경로 vs SVG 획순 비교 (규칙 기반)

**2.4 (선택) AI**

- [ ] 교사 기기만: Gemini 등 API 키 **Secure Storage**, 명시적 동의 UI
- [ ] AI 출제·글씨 교정 (이미지는 교사 기기에서만 전송)
- [ ] 학생 단말 기본 **외부 전송 없음** 유지

---

### Phase 3 — 교사·학급·실시간

**3.1 교사**

- [ ] 학급/세션 개념 (서버 없이 **세션 ID + 교사 기기** 기준)
- [ ] 학생 목록 (deviceBindingId + 표시명, QR 가입 시 등록)
- [ ] 실시간 응시 현황·진행률
- [ ] 학급 통계: 평균 정답률, 취약 자모

**3.2 동기화 확장**

- [ ] 오프라인: 암호화 문제 번들 파일/QR (허브 없이 배포)
- [ ] 재연결·ACK·재전송
- [ ] (장기) Nearby / Multipeer 어댑터

**3.3 부모 모드**

- [ ] 자녀 기기 연결 (초대 코드, 로컬 또는 교사 중계)
- [ ] 학습 요약·리포트 (로컬 이력 기반)

---

### Phase 4 — 운영·확장

- [ ] 오프라인 핵심 자산 캐시 (SVG, 단어장)
- [ ] PDF 학습지 출력 (jammin 연계 또는 앱 내 생성)
- [ ] Play Store / App Store 제출
- [ ] 교육용 태블릿 MDM·웨일북 대응 검증
- [ ] (선택) jammin 웹 API — 개발·검증·콘텐츠 가져오기 전용

---

## 7. jammin 연동 (선택)

| jammin | chominjungum |
|--------|----------------|
| `POST /addWord` | `hangul_core` (온디바이스) |
| 받아쓰기 워크시트 JS | Flutter 받아쓰기 UI |
| SVG·폰트 | Phase 2에서 번들 |
| 중앙 DB·WebSocket | **도입 안 함** (학교 클라우드 정책 시만 재검토) |

- [ ] jammin `addWord` 응답과 `HangulUtil.addWordJson` CI 비교 테스트

---

## 8. 기술 스택

| 구분 | 기술 |
|------|------|
| 앱 | Flutter 3.x, Dart 3.5+ (workspace) |
| 상태·라우팅 | Riverpod, go_router |
| 로컬 | Hive (init), flutter_secure_storage |
| 동기화 | shelf, web_socket_channel, sync_protocol, cryptography |
| QR | mobile_scanner 7, qr_flutter |
| 백엔드 | 없음 (기본) |

> **2026-09-07**: ML Kit(`google_mlkit_text_recognition`)과 `image_picker` 를 뺐다.
> ML Kit 은 arm64 시뮬레이터 슬라이스가 없어 빌드가 x86_64 전용으로 떨어지고,
> Apple Silicon + iOS 26 시뮬레이터에서 실행 자체가 안 됐다. `OcrService` 는
> 사용처가 0이었다(손글씨는 캔버스로 받고 채점은 `DictationCompare` 가 한다).
> Phase 2 의 "OCR 강화"를 다시 할 때는 시뮬레이터 검증을 포기하지 않는 대안
> (Apple Vision / on-device Tesseract / 서버 OCR)을 먼저 따질 것.

---

## 9. 마일스톤 요약

| 단계 | 목표 | 핵심 산출 |
|------|------|-----------|
| **Phase 1** | 교실 파일럿 | 답안 제출·교사 확인, 이력 저장, 보안·UX 정리 |
| **Phase 2** | 학습 품질 | TTS, 다문항, 획순, OCR 강화, (선택) AI |
| **Phase 3** | 교사·학급 | 통계, 오프라인 번들, 부모 |
| **Phase 4** | 배포·운영 | 스토어, MDM, jammin 자산·PDF |

---

## 10. 참고 문서

- [README.md](README.md) — 실행 방법·포트·저장소 구조
- [jammin](../jammin) — 웹 원본·`HangulUtil`·받아쓰기 워크시트

---

## 11. 2026-09-07 — 시뮬레이터 검증에서 드러난 것 (리허설 전 조치)

시뮬레이터 2대(교사 iPhone 17 Pro Max / 학생 iPhone 17 Pro)를 띄워 왕복을 시도하다
**자동 테스트 107개가 전부 통과하는데도 살아 있던 버그 3건**을 찾았다.
공통점: 셋 다 "코드는 맞고 환경에서만 터지는" 종류여서 단위·위젯 테스트로는 잡히지 않았다.

### 🔴 A. 출제가 원격 jammin 서버에 의존하고 있었다 — 전제 위반

교사가 문제를 낼 때마다 `POST https://초민정음.com/addWord` 로 자모 분해를 요청했다.
시뮬레이터에서 `CERTIFICATE_VERIFY_FAILED` 로 출제가 통째로 실패하면서 드러났다.

**이건 단순 오류가 아니라 이 앱의 존재 이유를 부정한다.** "중앙 서버 없이 같은 Wi-Fi
안에서 교사·학생 기기가 직접 동기화"가 설계 전제인데, 정작 첫 단계인 출제가 인터넷
없이는 불가능했다. 교실 Wi-Fi 가 외부로 안 나가거나 사설망이면 수업을 시작조차 못 한다.

- 로컬 분해 경로는 **처음부터 있었다**(`DictationItem.fromExpectedText`). 쓰지 않았을 뿐이다.
- `HangulUtil` 이 jammin 원본과 같은 결과를 낸다는 것은 골든 벡터가 이미 강제하므로,
  정확성을 잃지 않고 원격을 뗄 수 있었다.
- ⇒ `DictationComposer.compose()` (순수 함수, 네트워크 없음) + 회귀 가드 테스트.
- 왜 기존 왕복 테스트가 못 잡았나: `hub_attempt_flow_test` 가 `broadcastEncrypted` 를
  **직접** 불러서 출제 앞단(분해)을 지나가지 않았다.

학생 연습 화면의 "서버에서 갱신"은 그대로 둔다 — 사용자가 직접 누르는 선택 기능이고
실패해도 번들 스냅샷으로 계속 동작한다.

### 🔴 B. iOS 로컬 네트워크 권한 선언이 없었다 — 실기기에서만 터진다

`NSLocalNetworkUsageDescription` 이 `Info.plist` 에 없었다. iOS 14+ 는 이 문구가 없으면
로컬 네트워크 접속을 **아예 허용하지 않는다** → 학생 기기가 교사 허브에 붙지 못한다.

⚠️**시뮬레이터에는 이 제약이 없다.** 그래서 지금까지의 모든 검증을 통과했고,
실기기 리허설 첫 연결부터 막혔을 것이다. 리허설 당일 원인을 찾느라 시간을 다 썼을 자리다.

Android 는 `usesCleartextTraffic="true"` 가 이미 있어 평문 `ws://` 가 동작한다
(교사 기기에 TLS 인증서가 없으니 허브는 평문일 수밖에 없다).

⇒ 이런 선언은 **실기기에서만 실패가 드러나 테스트가 유일한 방어선**이므로
`test/platform_manifest_test.dart` 로 존재를 강제한다.

### 🔴 C. 업싱크 토큰이 게이트웨이 Basic 을 덮어쓰고 있었다

앱이 `Authorization: Bearer <앱 JWT>` 로 보냈다. 서버가 nginx 뒤에 있고 외부 요청에는
HTTP Basic 을 요구하므로, 같은 헤더에 Bearer 를 실으면 Basic 이 덮여 **게이트웨이에서
401** 이 되고 토큰이 서버에 닿지도 못한다. ⇒ `X-Auth-Token` 으로 변경.

외부 경로 실측으로 가른 것:

| 보낸 방식 | 결과 |
|---|---|
| Basic + `Authorization: Bearer` | nginx 401 (`WWW-Authenticate: Basic`) — 서버 미도달 |
| Basic + `X-Auth-Token` | 서버 도달 |

진짜 교사 토큰으로 왕복까지 실측: 1차 `accepted:1 duplicated:0` /
2차(같은 배치) `accepted:0 duplicated:1` — 09-05 에 고친 업싱크 멱등성이
라이브에서 의도대로 동작하는 것도 함께 확인됐다.

### ⚠️ 남은 결정 — 앱은 게이트웨이 Basic 자격을 보낼 수 없다

헤더를 고쳤어도 **외부 도메인으로는 여전히 못 올린다.** 게이트웨이가 Basic 을 요구하는데
`UpsyncConfig` 에는 `baseUrl`·`token`·`classroomId` 만 있고 Basic 자격을 넣을 자리가 없다.
설정 화면 힌트가 `http://192.168.0.10:8100` 인 것에서 보이듯 **원래 LAN 직결을 전제**한
설계다. 교실에서 바로 올리려면 셋 중 하나를 골라야 한다:

1. `UpsyncConfig` 에 게이트웨이 자격(id/pw) 필드 추가 — 앱에 게이트 비번을 두는 셈
2. nginx 에서 `/chominjungum/api/sync/` 만 gwauth 예외 — 서버 JWT 가 이미 인증이므로
   이중 인증이 불필요하다는 판단. `/haru/`(자체 api-key)가 같은 선례
3. 교실에서는 올리지 않고 교사가 나중에 서버가 있는 망에서 올린다 — **현재 설계**.
   Hive 큐가 보존하므로 그대로 동작하고, 코드 변경이 없다

⇒ 보안·운영 판단이 섞여 있어 사람 결정으로 남긴다.

### 검증 현황

**123 GREEN** (앱 82 / hangul_core 30 / sync_protocol 11) · `flutter analyze` 0
시뮬레이터 빌드 아키텍처 `x86_64 arm64` 회복 · 빌드 156초 → 25초

### 실기기에서만 남는 것

- QR **카메라** 스캔 (시뮬레이터에 카메라가 없다 — 이번엔 페이로드 붙여넣기로 우회했다)
- 서로 다른 기기 간 LAN 도달성 (`NetworkInfo` 가 준 IP 가 학생 기기에서 실제로 열리는가)
- iOS 로컬 네트워크 권한 **프롬프트 수락** 흐름 (B 를 고쳐 이제 프롬프트가 뜬다)
- 손글씨 터치 입력 품질
