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
- **메시지 타입 정의만 존재**: `dictation.package`, `attempt.submit`, `ack` — **`attempt.submit` 앱 연동 없음**

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

### 2.6 학생 앱 (`StudentHomeScreen`)

- QR 스캔 (`mobile_scanner` 7.x) 또는 JSON 붙여넣기 → `StudentHubClient`
- `dictation.package` 수신 시 Provider 갱신 + `/practice` 이동
- 허브 없이 로컬 샘플 받아쓰기

### 2.7 받아쓰기 (`DictationPracticeScreen`)

- jammin `static/hangul/*.svg` → `assets/hangul/` + `HangulWorksheet` / `HangulGlyphCell` (editor 프로필)
- **학생**: 지험지(받아쓰기 모드·획순 가이드 토글), 키보드 채점, 손글씨 연습 캔버스 — **OCR UI 없음**, 정답 문장 미표시
- **교사**: 정답·지험지 미리보기, 키보드 + 캔버스/갤러리 OCR 채점, 기기 바인딩 ID 표시
- 채점 결과 카드 (점수%, 글자별 피드백, 상위 12글자)

### 2.8 플랫폼

| 플랫폼 | 상태 |
|--------|------|
| Android | `student` / `teacher` productFlavors, `usesCleartextTraffic` (ws용) |
| iOS | Podfile, iOS 15.5+, `pod install` — flavor 없음, 엔트리로 역할 구분 |
| macOS / Web | 타깃 없음 |

### 2.9 미구현 (코드 없음)

- 학생 **답안·채점 결과** 교사 기기로 전송 (`attempt.submit`)
- 학습 이력 **Hive/DB 저장**
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
| `attempt.submit` 미연동 | 프로토콜만 정의 | 학생 채점 후 교사로 전송 구현 |
| Hive 미사용 | init만 됨 | Box 설계 후 시도·이력 저장 |

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

- [ ] 학생 채점 완료 → `SyncMessageTypes.attemptSubmit`으로 교사 허브 전송
- [ ] 교사 화면: 접속 학생 수·최근 제출·점수 요약 (최소 리스트)
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
- [ ] 통합 테스트: 허브 → 수신 → 채점 → 제출 E2E (가능 시)
- [ ] Android release keystore·서명 분리
- [ ] README/PLAN과 실제 동작 정기 동기화

**Phase 1 완료 기준:** 교사 1대 + 학생 N대, 같은 Wi‑Fi에서 출제 → 응시 → 채점 → **교사가 제출·점수 확인**까지 한 사이클.

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
| OCR·QR | google_mlkit_text_recognition, mobile_scanner 7, qr_flutter, image_picker |
| 백엔드 | 없음 (기본) |

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
