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

### 2.9 미구현 (2026-09-09 실측 — 이 절은 오래 stale 했다)

> 여기 있던 목록 중 **Hive 저장 · SVG/폰트 번들 · 하단 내비**는 이미 끝났거나
> 안 하기로 결정됐는데 표시가 남아 있었다. 문서를 근거로 판단하기 전에 코드를 볼 것.

**정말 없는 것**
- 손글씨 → 텍스트 인식 (2026-09-07 에 ML Kit 을 걷어냈다 — §6 Phase 2.2 참고)
- TTS · 획순 가이드 · AI 출제/교정 · 부모 모드
- 앱 안의 학급 관리 (서버 쪽 `chominjungum-web` 교사 콘솔이 담당한다)
- Android release 서명 분리 · 스토어 배포
- iOS 스킴 분리 (Android 는 flavor 로 이미 갈려 있다)

**있는데 없다고 적혀 있던 것**
- 학습 이력 Hive 저장 → ✅ `LocalStore`+`DictationRepository`(2026-09-05)
- jammin SVG(83개)·KCC 도담도담체 → ✅ 번들·렌더됨
- 하단 내비 → ⊘ **안 하기로 종결**(§13)
- jammin 서버 HTTP 클라이언트 → ⊘ **일부러 뗐다**. 출제는 기기에서 분해한다(§11 A).
  학생 연습 화면의 "서버에서 갱신"만 선택 기능으로 남아 있다

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
- [x] QR 페이로드에서 세션 키 노출 방식 개선 (2026-09-09, **B2**: QR=교사 X25519 공개키 + `hello`/`session.key` 핸드셰이크 + 키 래핑. `feat/b2-x25519` — ⚠️**리허설 후 main 병합**)
- [x] 교사 화면 JSON 전체 노출 제거 (2026-09-05, `PairingInfoCard` 기본 숨김 + 명시 토글)
- [~] 허브 바인딩 **IP** 수동 입력은 있다(`TeacherHomeKeys.hostOverride`). 포트는 `SyncDefaults.hubPort`(30020) 고정 — 교실에서 바꿀 일이 없어 UI 를 두지 않았다

**1.2 데이터 영속화**

- [x] Hive Box 설계 (2026-09-05, `LocalStore` — `cjm.items.v1`/`cjm.attempts.v1`/`cjm.sessions.v1`, 값은 JSON 문자열)
- [x] 학생: 수신 문제·본인 시도 이력 로컬 저장 (2026-09-05, `DictationRepository`)
- [x] 교사: 출제 이력·제출 스냅샷 저장 (2026-09-05, `TeacherSession` — **업싱크 큐와 분리**했다. 큐는 업로드하면 비워지는데 화면 목록이 메모리라 올리면 지난 수업이 사라지는 구조였다)

**1.3 UX·앱 골격**

- [–] 하단 Navigation Bar — **하지 않기로 종결**(2026-09-08, §13). 학생은 문제를 받으면 자동으로 넘어가고 교사는 한 흐름이라 탭이 없던 이동을 만든다
- [x] 채점 결과 표시 (2026-09-05, `AttemptSubmitSheet` 안 — 점수·글자별 ✓/✗·오답칩 `갓→갔`. 별도 화면으로 빼지 않은 것은 답 입력 직후 같은 자리에서 보는 편이 낫기 때문)
- [x] KCC 도담도담체 번들 + OFL 고지 (2026-09-05)
- [x] 기기 ID 를 설정 화면으로 이동 (2026-09-05)
- [ ] **iOS 스킴 분리** — Android 는 이미 flavor 로 갈려 있다(`student`/`teacher`, `applicationIdSuffix`). iOS 만 번들 ID 가 같아 **한 기기에 하나만 깔린다**. 교실에서는 기기가 달라 지장이 없고 Xcode 프로젝트 편집은 빌드를 깨뜨리기 쉬워 **미룬다**(개발 편의가 주 이득)

**1.4 품질·배포 준비**

- [x] 골든 테스트 (`packages/hangul_core/test/golden_test.dart` — chominjungum-web `golden/hangul-split.json` 과 대조. Java·Dart·TS 세 이식본을 묶는다)
- [x] **자산 출처 가드** (2026-09-10, `test/hangul_assets_provenance_test.dart`) — 자모 SVG 83개가 jammin 원본에서 재생성한 것과 같은지(`tool/build_hangul_assets.py --check`), 글꼴이 웹과 **같은 윤곽**인지(`tool/check_font_provenance.py`). 자모 *분해* 로직에는 골든 벡터가 있었지만 *자산* 에는 아무 장치가 없어 83개가 조용히 다른 그림이었다(§14)
- [x] 통합 테스트: 허브 → 수신 → 채점 → 제출 E2E (2026-09-02, `test/hub_attempt_flow_test.dart`·`test/attempt_submit_e2e_test.dart`. ⚠️실제 소켓 I/O는 `tester.runAsync` 안에서만 진행됨)
- [ ] Android release keystore·서명 분리
- [x] README/PLAN 실제 동작 동기화 (2026-09-09 — 체크박스 13개가 실제와 어긋나 있었다. 이미 끝난 일을 다시 하지 않도록 맞췄다)

**Phase 1 완료 기준:** 교사 1대 + 학생 N대, 같은 Wi‑Fi에서 출제 → 응시 → 채점 → **교사가 제출·점수 확인**까지 한 사이클.

> ✅ **2026-09-08 실기기로 이 사이클을 통과했다**(아이폰 학생 ↔ 시뮬레이터 허브, 86점 제출까지).
> Phase 1 항목 중 남은 것은 **iOS 스킴 분리**(개발 편의)와 **Android release 서명**뿐이고,
> 둘 다 교실 사용을 막지 않는다. 실질적으로 **Phase 1 은 끝났다**.

> **2026-09-02 진행**: 출제 → 수신 → 채점 → 제출 → 교사 수신 경로를 구현하고 자동 테스트로 증명(앱 9 + 패키지 11 GREEN). **남은 확인 = 실기기 2대 교실 리허설** — 교사 현황판 렌더는 위젯 테스트가 아니라 실기기로 봐야 한다(`NetworkInfo`·실허브 의존).

---

### Phase 2 — 받아쓰기·학습 기능 강화

**2.1 받아쓰기**

- [x] 다문항 출제 (2026-09-08 — 한 줄 = 한 문항. jammin 제약 준용: 문장 16글자·전체 20줄)
- [ ] TTS 문제 읽기 (`flutter_tts`, 속도 조절)
- [ ] 오답 노트 (로컬, 자모/음절별 취약 분석)
- [ ] 교사: jammin 스타일 **자모 가리기 옵션** 출제 (hidebox 개념 포팅)

**2.2 OCR·입력**

> ⚠️**2026-09-07 에 OCR 을 통째로 걷어냈다.** `google_mlkit_text_recognition` 이
> arm64 시뮬레이터 슬라이스를 제공하지 않아 Apple Silicon 에서 앱이 실행조차 되지
> 않았고, `OcrService` 는 **사용처가 0**이었다(손글씨는 캔버스로 받고 채점은
> `DictationCompare` 가 한다). `image_picker` 도 함께 제거 — 그래서 아래는
> "갤러리·캔버스만"이 아니라 **캔버스만**이 현재 상태다.
> 다시 할 때는 **시뮬레이터 검증을 포기하지 않는 대안**(Apple Vision / 서버 OCR)을 먼저 따질 것.

- [ ] 손글씨 → 텍스트 인식 (수단 재선정부터)
- [ ] 인식 후처리 (공백·자모 정규화) 공통 유틸

**2.3 획순 연습**

- [x] jammin SVG 자산 번들 (`assets/hangul/` — 83개. 받아쓰기 칸의 밑그림으로 실제 렌더된다)
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

### ✅ 해결됨 (2026-09-08) — sync 경로 하나만 게이트 밖으로

**선택지 ②를 택했다**: nginx 에서 `POST /chominjungum/api/sync/sessions` 만
`location =` 정확 매치로 게이트웨이 Basic 밖에 두고, **서버 JWT 로 지킨다**.

왜 ②인가 — ①(앱에 게이트 자격 필드)은 **앱에 홈랩 전체를 지키는 게이트 비번을 저장**하는
셈이라 앱 하나가 털리면 게이트가 무의미해진다. ③(현재 유지)은 교실에서 올릴 수 없다.
②는 노출 범위가 **이 한 경로**이고, 그 경로는 이미 토큰 없이는 401 이다.

적용 후 실측:

| 확인 | 결과 |
|---|---|
| sync 무인증 | `401` + `application/json` — **애플리케이션 응답**(`WWW-Authenticate` 없음) |
| sync + 유효 토큰, **Basic 없이** | `{"accepted":1,…}` — 앱이 하는 그대로 성공 |
| 다른 API(`/api/classrooms`) | `WWW-Authenticate: Basic` — 게이트 유지 |
| 정적 페이지 | 401 — 게이트 유지 |
| `/chominjungum/health` | 200 — 공개 유지 |

안전 근거: 점수는 **서버가 재채점**하고(클라이언트 숫자를 읽지 않는다), 남의 학급은
소유권 검사로 403, **로그인 엔드포인트는 게이트 뒤에 그대로** 두어 무차별 대입을 막는다
(+`LoginThrottle` 5회→5분). 선례는 `/haru/`(자체 api-key 로 지키며 게이트 밖).
백업 = `.25:/etc/nginx/backups/gateway.conf.bak-20260908`, 롤백은 그 블록만 삭제.

⚠️ 백업을 처음에 `sites-enabled/` 에 뒀다가 nginx 가 그것도 로드해 `duplicate upstream`
으로 문법 검사가 깨졌다. **`sites-enabled/` 안에 백업을 두면 안 된다** —
기존 관례대로 `/etc/nginx/backups/` 를 쓸 것. reload 전에 발견해 서비스 영향은 없었다.

### (이전 기록) 남은 결정 — 앱은 게이트웨이 Basic 자격을 보낼 수 없다

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

---

## 12. 2026-09-07 저녁 — 통합 테스트 초록불 + 오버플로 3건 (자율 진행)

### 통합 테스트가 왕복 9단계를 덮는다 (마우스 사용 0)

`apps/chominjungum/integration_test/classroom_roundtrip_test.dart` — 한 프로세스에서
교사 화면(실제 위젯·실제 플러그인·실제 소켓)과 학생 클라이언트를 함께 띄운다.

허브 기동 → 페어링 payload → 세션키 숨김 토글(B1) → 학생 WS+AES-GCM 연결 →
**화면 버튼으로 출제**(네트워크 없이 분해·전송) → 학생 수신·골든 일치 → 채점·제출 →
교사 현황판 → `/practice` 방문 → Hive 실파일 → **(선택) 실서버 업싱크**.

실행은 `tool/run-integration.sh`. 절차·함정은 `integration_test/README.md`.

첫 실행에서 두 곳이 걸렸고 **둘 다 테스트 쪽 문제**였다(제품 코드 정상):
1. 화면 밖 위젯 `tap` 이 **예외 없이 빗나간다** — 펼치면 밀려나는 버튼에서 걸렸다.
   ⇒ 조작은 전부 `tapVisible`/`typeVisible`(`ensureVisible` 후)
2. 서버가 `attemptId` 를 **UUID 로 검증** — 임의 문자열은 인증 통과 후 400

### 앱 업싱크가 실서버까지 동작한다

게이트웨이는 외부 요청에 Basic 을 요구하고 **앱은 그 자격을 못 보낸다**.
검증은 SSH 터널로 직결한다(서버가 `127.0.0.1` 로 보아 게이트를 지나지 않는다):
`ssh -f -N -L 18100:127.0.0.1:8100 homelab25`.
실측 = `업로드 완료 — 신규 1건 · 명단 연결 필요한 기기 1대`.
부수 확인: 같은 문장을 다시 출제해도 서버 문항이 새로 생기지 않았다(`contentHash` 재사용).

### 🔴 그런데 화면을 눈으로 보니 오버플로 3건이 있었다

통합 테스트 9단계가 통과하는데도 살아 있었다 — **위젯 존재는 확인하지만 레이아웃이
넘치는지는 안 봤고**, 통합 테스트가 `/practice` 를 방문하지도 않았다.

| | 무엇 | 왜 심각한가 |
|---|---|---|
| **A** ★ | 문항 칸이 화면 밖으로 32px 잘림 | **잘린 칸에는 학생이 답을 쓸 수 없다** — 미관이 아니라 기능 장애 |
| **B** | 앱바 넘침 | 로고가 고정 크기 SVG + 뒤로가기 + 액션 3개 |
| **C** | 툴바 1.4px 넘침 | |

A 의 원인: `cellW = (maxW / lineBreakCount).clamp(60, 140)` 에서 좁은 화면이면
`maxW/8 < 60` 이라 **하한이 60으로 끌어올려 `칸수 × 60 > maxW`** 가 됐다.
17 Pro Max 에서 이미 7칸이 넘쳤고 더 좁은 기기·더 긴 문장은 더 심하다.
⇒ 한 줄 칸 수를 화면 폭이 정하게(`perRow = min(lb, ⌊maxW/60⌋)`). 7칸이 6+1 로 접힌다.
인쇄 학습지는 lineBreakCount 를 지키지만 이 위젯은 화면 응시 전용이다.
형제 위젯 `hangul_worksheet.dart` 는 이미 가로 스크롤로 대응돼 있어 무사했다.

C 는 처음에 `Flexible`+ellipsis 만 넣었더니 **라벨이 통째로 사라져 아이콘만 남았다**.
지우기는 되돌릴 수 없는 동작이라 초등학생 화면에서 그건 후퇴다 —
패딩·글자를 줄이고 `이 칸 지우기` → `이 칸` 으로. **짧고 온전한 라벨 > 잘린 라벨.**

### 회귀 방어 — 근본 원인은 "이 화면에 위젯 테스트가 없었다"

오버플로는 위젯 테스트에서 예외로 잡힌다. `test/worksheet_overflow_test.dart` 가
**기기 4종(SE 375pt ~ 17 Pro Max 440pt) × 문장 5개(5~13칸) + 툴바 + 채점 시트 + 설정**
을 덮고, 툴바 라벨 존재까지 단정한다. **수정을 되돌리면 15개가 실패**하는 것을 확인했다.
통합 테스트에도 `/practice` 방문을 넣었다.

⚠️ 첫 판에서 **기기 배율을 틀렸다** — SE 는 @2x 인데 dpr 3 을 줘서 250pt 로 테스트됐고
그 폭에서만 채점 시트가 넘쳤다. 실기기 폭에서는 문제없다. 기기별 dpr 을 함께 넣었다.

### 검증

**114 GREEN**(단위·위젯) · 통합 1 GREEN(기본 29초 / 업싱크 포함 44초) · analyze 0
라이브 DB 는 테스트 흔적을 지워 리허설 상태로 되돌렸다(세션·답안 0 · 문항 3건).

### ⚠️ CGEvent 시뮬레이터 조작의 한계

`swift` + CGEvent 로 클릭하면 **사용자의 실제 커서를 가져가** 작업을 방해한다.
그리고 **앱바 같은 상단 요소에는 좌표가 닿지 않았다**(창 크롬 오프셋 추정, 원인 미확정).
⇒ 조작이 필요한 검증은 통합 테스트로 옮기고, CGEvent 는 "화면을 눈으로 보는" 용도로만.
`xcrun simctl io <UDID> screenshot` 은 언제든 안전하다 — **띄워서 보는 것만으로
오버플로 3건을 찾았다.**

---

### 실기기에서만 남는 것

- QR **카메라** 스캔 (시뮬레이터에 카메라가 없다 — 이번엔 페이로드 붙여넣기로 우회했다)
- 서로 다른 기기 간 LAN 도달성 (`NetworkInfo` 가 준 IP 가 학생 기기에서 실제로 열리는가)
- iOS 로컬 네트워크 권한 **프롬프트 수락** 흐름 (B 를 고쳐 이제 프롬프트가 뜬다)
- 손글씨 터치 입력 품질


---

## 13. 2026-09-08 — 실사용 갭 세 개를 메웠다 + 남은 둘에 대한 판단

실기기 왕복이 통과한 뒤 "기능적으로 완벽한가"를 다시 훑어 **교실에서 못 쓰게 만드는
갭 세 개**를 찾아 메웠다. 셋 다 "코드는 다 돌아가는데 수업에는 못 쓰는" 종류였다.

### ✅ 메운 것

| | 무엇이 문제였나 |
|---|---|
| **다문항 출제** | `items: [item]` — 한 번에 한 문항. 받아쓰기는 보통 열 문항이다. **프로토콜·학습 화면·채점 시트는 이미 다문항을 지원**했고 출제 UI만 막혀 있었다 ⇒ 한 줄 = 한 문항인 여러 줄 입력. jammin 제약 준용(문장 16글자·전체 20줄), 잘못된 줄은 **몇 번째인지** 알려준다 |
| **학생 이름** | 교사 화면이 `학생 a3f2…`(기기 ID)로만 보였다. `studentName` 은 **입력할 곳이 없는 死필드**였다 ⇒ 학생 화면에 선택 입력. 비우면 종전대로. 기기에만 저장하고 **서버 업싱크에는 안 실린다**(서버는 기기↔학생 배정으로 붙인다) |
| **끊김 감지·재연결** | `StudentHubClient` 에 `onDone`/`onError` 가 아예 없어, 끊겨도 화면은 "허브에 연결됨"이고 **제출이 조용히 실패**했다 ⇒ 통보 + 자동 재연결(2·4·6·8·10초, 5회) |

검증: 앱 114 → **124 GREEN**. 끊김 감지는 `onDone`/`onError` 를 떼면 실패하는 것까지 확인.

⚠️ 학생 이름에서 배운 것: 처음엔 `_submit` 안에서 `await StudentProfile.load()` 를 했는데
**제출 경로에 플랫폼 채널 I/O가 끼어들어** 제출이 아예 나가지 않았다(e2e 테스트가 잡았다).
선택 기능이 핵심 경로를 막으면 안 된다 ⇒ 미리 읽어 두고, 저장소 실패는 삼킨다.

### 하지 않기로 한 것 — 하단 탭

리허설로 동선을 본 뒤 정하기로 했던 항목이다. **보고 나니 필요가 없다.**

- **학생**: QR 스캔 → 문제를 받으면 **자동으로** 받아쓰기로 넘어간다. 화면이 사실상 둘이고
  그 사이를 사용자가 오갈 일이 없다
- **교사**: 허브 → 출제 → 현황 → 업싱크가 **한 흐름**이라 한 화면 스크롤이 맞다
- 역할이 엔트리로 갈려 있어 공통 탭을 만들 이유도 없다

설정은 이미 앱바 아이콘으로 닿는다. **탭을 넣으면 없던 이동을 만들 뿐이다.** 종결.

### 사람 결정이 필요한 것 — B2 (QR 세션키 X25519)

지금 QR 에는 **대칭 세션 키가 그대로** 담긴다(`publicKeyB64` 는 이름과 달리 대칭키).
QR 을 촬영당하면 같은 Wi-Fi 의 제3자가 도청·위조할 수 있다.

X25519 로 바꿀 수 있다는 것은 `packages/sync_protocol/test/x25519_feasibility_test.dart`
가 이미 확인해 뒀다(공개키 32바이트 = QR 용량 동일, HKDF 유도 키로 기존 envelope 무변경).

**그런데 단순 치환이 아니다.** 지금은 모든 학생이 *같은* 대칭키를 써서 교사가 한 번
브로드캐스트하면 전원이 푼다. ECDH 는 **학생마다 다른 키**를 만들므로, 그대로 바꾸면
브로드캐스트를 학생 수만큼 암호화해야 한다. 제대로 하려면 **키 래핑**이 필요하다:

1. QR = 교사 공개키
2. 학생 접속 → 학생 공개키 전송(`hello`)
3. 교사가 ECDH+HKDF 로 **학생별 키**를 유도하고, 그 키로 **세션 대칭키를 감싸 전달**
4. 이후 브로드캐스트는 기존처럼 세션 대칭키 하나로

즉 **메시지 타입 2개 추가 + 핸드셰이크 도입**이다. 하위호환은 불가능하고(키를 QR 에서
빼는 것이 목적이라 옛 경로를 남기면 의미가 없다) 교사·학생 앱을 동시에 올려야 한다.

⇒ **오늘은 하지 않았다.** 이유: ①오늘 이미 다문항·이름·재연결이 들어가 **그것들의 실기기
재검증이 먼저**다 ②방금 통과한 왕복 프로토콜을 같은 날 바꾸면 수요일 리허설에서
**원인 분리가 어려워진다** ③보안 이득은 "교실에서 QR 을 촬영당하는" 시나리오에 한정된다.

**권장 순서: 오늘 변경분 실기기 재검증 → 수요일 2대 리허설 → 그 뒤 B2.**

---

## 14. 2026-09-10 — 자산에 "출처 가드"를 달았다 + 실기기 렌더를 수치로 판정

### 배경

09-09 에 자모 SVG 83개와 상단 로고가 **jammin 원본이 아니라 다시 그린 것**임을
발견해 전부 원본 변환으로 갈아끼웠다. 그런데 그때 든 의문이 남아 있었다 —
**왜 아무도 몰랐나.**

답은 단순하다. 자모 *분해 로직*에는 골든 벡터가 있어 Java·Dart·TS 가 어긋나면
즉시 깨지는데, *자산*에는 그런 장치가 하나도 없었다. 그래서 고치는 것으로 끝내면
같은 일이 또 생긴다.

### ✅ 붙인 가드

| 어디 | 무엇을 강제하나 |
|---|---|
| 앱 `test/hangul_assets_provenance_test.dart` | 자모 83개가 `build_hangul_assets.py --check` 결과와 **바이트까지 같다**(= 원본에서 재생성한 것이다) |
| 〃 (같은 파일) | 학습지 글꼴이 웹과 **같은 윤곽**이다 (`tool/check_font_provenance.py`) |
| 웹 `frontend/test/hangul-assets-provenance.test.ts` | 웹 자산 83개 + 로고가 원본과 **바이트 동일**하다 |
| 앱 `test/glyph_ink_host_test.dart` | 렌더된 잉크 경계가 **웹의 배치 사각형**과 같다 (`hangul-metrics.ts` 수치) |

⚠️jammin 은 별도 저장소라 항상 옆에 있지 않다 ⇒ **없으면 건너뛴다**(실패시키지 않음).

### ★글꼴은 헛다리였다 — 바이트로 판정하면 안 된다

앱 `KCCDodamdodamR.ttf` 와 웹 `KCCDodamdodam.woff` 는 해시가 다르고, 테이블 단위로
봐도 `glyf`·`loca` 가 달라 **13789개 중 97.2% 가 다른 글리프처럼 보인다.**
좌표를 실제로 디코딩하니 **13789개 전부 완전히 같았다** — 차이는 좌표 인코딩
(플래그 압축) 방식뿐이었다.

그래도 가드는 남겼다. jammin 이 **v2.0.0(13789자)과 v3.0.0(18180자)을 둘 다 배포**해서
실수로 바뀔 여지가 실제로 있고, 그러면 자모는 멀쩡한데 **숫자·문장부호만** 웹과
달라진다(학습지에서 숫자는 SVG 가 아니라 `<text>`+글꼴로 그려진다).

### ✅ 실기기 렌더 — 눈이 아니라 픽셀로

자산이 원본과 같아도 **기기가 그 좌표대로 그리는지**는 별개다. 그래서 같은 측정을
호스트와 실기기에서 돌려 대조하는 경로를 만들었다(`integration_test/README.md`).

**최종 실측(iPhone 15 Pro Max · iOS 26.6.1): 83/83 일치** — 경계 0건 · 모양 지문 0건 · 총 잉크량 0건.

- **경계 상자** ±1.5px 안 — 배치는 기기에서도 정확하다
- **모양 지문**(8×8 격자) 최대 셀 차이 5.0%
- 총 잉크량은 글꼴 자산(`!`·숫자·`?`)이 일관되게 **−4~5%**, 중성 3개가 +4%
  → iOS 래스터화가 획을 얇게 그리는 것. 방향이 균일하고 모양이 같아 **모양 차이가 아니다**

★**총 잉크량만으로는 부족하다**: 특수문자 자산은 테두리가 함께 들어 있어, 글꼴이 없어
대체 글리프가 그려져도 **경계가 안 변한다** ⇒ 격자 지문을 추가해 잉크가 *어디* 있는지로
판정한다.

★**통과했다고 끝내지 않고 자의 판별력을 따로 쟀다.** 허용치는 "통과되는 값"이 아니라
**틀린 것을 잡아내는 값**이어야 한다:

| | 지문 최대 차이 |
|---|---|
| 같은 자산 호스트↔기기 (허용해야 함) | 중앙 **1.0%** · 최대 5.0% |
| 숫자끼리 서로 (잡아내야 함) | 최소 **31.0%** |

⇒ 허용치 6% 는 막으려는 실패(대체 글리프)에 **5배 여유**가 있다.
⚠️한계: 자모끼리 가장 닮은 쌍(종성 4535·4545)은 3.3% 라 지문으로 못 가른다 — 자산이
서로 뒤바뀌는 경우는 출처 가드가 본다.

### 🔴 흰 화면 함정 — 기록보다 조건이 넓다

측정 중 앱이 **흰 화면**으로 뜨고 `Dart VM Service was not discovered` 로 죽었다.
`flutter clean` + `rm -rf ios/Pods` + `pub get` 으로 해결.

⚠️기존 기록은 이 함정을 **"device 릴리스 빌드 뒤 simulator 빌드"** 조건으로 적어 뒀는데,
이번은 **device 디버그 빌드를 연속으로 돌린 경우**였다. 조건을 좁게 적어 두면 같은 증상을
만나고도 다른 원인을 찾게 된다.

⚠️함께 겪은 것 둘:
- **아이폰이 잠겨 있으면** 개발자 이미지가 마운트되지 않아 빌드가 실패하는데
  **`flutter drive` 는 그래도 종료코드 0** 을 낸다 ⇒ 성공 판정은 **산출물 파일 존재**로 한다
- 죽은 실행의 `devicectl device process launch` 가 **10분 넘게 남아** 다음 시도를 방해했다
  ⇒ 재시도 전에 정리한다
- `flutter clean` 은 `build/` 를 지우므로 **호스트 기준선도 함께 날아간다** — 대조 전에 다시 만든다

### 배운 것

**"원본을 준용한다"는 문장은 검증 장치가 아니다.** 준용을 강제하는 테스트가 없으면
그 문장은 주석일 뿐이고, 자산은 조용히 갈라진다. 로직에 골든 벡터를 두었으면
자산에도 같은 급의 장치가 있어야 한다.
