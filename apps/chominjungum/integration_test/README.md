# 교실 왕복 통합 테스트 (`apps/chominjungum/integration_test/`)

위젯 테스트로는 닿지 않는 것만 여기서 검증한다. **실기기·시뮬레이터에서 앱을 실제로 띄운다.**

## 왜 필요했나

2026-09-07, 자동 테스트 107개가 전부 통과하는데도 실환경 버그 3건이 살아 있었다.
공통 원인은 **검증 계층이 실환경에 닿지 않았다**는 것:

| 못 잡았던 것 | 왜 |
|---|---|
| 출제가 원격 jammin 서버에 의존 | 기존 e2e 가 `broadcastEncrypted` 를 직접 불러 출제 앞단(분해)을 지나가지 않았다 |
| 교사 화면 전체 렌더 | `NetworkInfo` 플러그인 때문에 위젯 테스트가 아예 불가능했다 |
| Hive 실제 파일 I/O | 위젯 테스트는 임시 디렉토리를 쓴다 |
| iOS 로컬 네트워크 권한 | 시뮬레이터에는 그 제약이 없다(**실기기만**) |

이 테스트는 앞의 셋을 덮는다. 마지막 하나는 실기기 실행에서만 드러난다.

## 실행

🔴 **실기기에서는 `all_device_tests.dart` 하나로 돌린다.** 파일별로 따로 돌리면
설치할 때마다 사람이 "개발자 신뢰"를 눌러 줘야 한다(아래 절 참고).

```bash
cd apps/chominjungum
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/all_device_tests.dart -d <기기>
python3 tool/compare_glyph_ink.py     # 자모 렌더 대조(호스트 기준선 필요)
```

2026-09-12 실측: 설치 1회 · 신뢰 1회로 **20건 전부 통과**(56초),
자모 83개 호스트↔기기 지문·경계·총량 **불일치 0건**.

개별 파일을 돌리고 싶을 때는 아래를 쓴다.

```bash
cd apps/chominjungum

# 부팅된 기기 확인
flutter devices

# 시뮬레이터 (교사 역할 엔트리로 띄운다 — 역할이 엔트리로 갈린다)
flutter test integration_test -d <simulator-udid>

# 실기기 (수요일 리허설 — iOS 로컬 네트워크 권한 프롬프트가 여기서만 뜬다)
flutter test integration_test -d <device-id>
```

⚠️ **`flutter test` (인자 없음)에는 포함되지 않는다** — `test/` 만 긁는다. 통합 테스트는
기기가 필요하므로 분리돼 있다.

⚠️ **마우스를 쓰지 않는다.** CGEvent 로 실제 커서를 움직이는 방식은 사용자의 작업을
방해하므로(09-07 중단), 조작이 필요한 검증은 이 테스트로 옮긴다.

## 무엇을 확인하나 — `classroom_roundtrip_test.dart`

한 프로세스에서 교사 화면(실제 위젯·실제 플러그인)과 학생 클라이언트를 함께 띄워
교실 한 사이클을 통과시킨다.

1. **교사 화면 렌더 + 허브 기동** — `NetworkInfo` 실호출, 실제 소켓 바인딩(30020)
2. **QR 페어링 페이로드 생성** — `PairingInfoCard` 에서 실물 payload 획득
3. **세션 키 화면 노출 기본 숨김(B1)** — 토글 양방향
4. **학생 연결** — 실제 WebSocket, 실제 AES-GCM
5. ★**출제** — 화면의 "문제 전송" 버튼을 실제로 눌러 `DictationComposer` 경로를 지난다.
   **네트워크가 없어도 성공해야 한다**(원격 jammin 의존 회귀를 실기동으로 잡는다)
6. **학생 수신·채점·제출** — `DictationCompare` + `attempt.submit`
7. **교사 현황판 반영** — 접속 수·제출 건수·평균
8. **Hive 실파일 영속화** — 문항·답안·세션이 실제로 디스크에 남는지

## 무엇을 확인하나 — `glyph_device_render_test.dart`

자모 자산 83개가 **실기기에서 원본대로 그려지는지**를 픽셀로 판정한다.
호스트에서 잰 같은 값과 대조하므로, 사람이 화면을 들여다볼 필요가 없다.

```bash
flutter test test/glyph_ink_host_test.dart          # ① 호스트 기준선
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/glyph_device_render_test.dart -d <기기>   # ② 기기 측정
python3 tool/compare_glyph_ink.py                   # ③ 대조
```

⚠️ **이 테스트만 `flutter drive` 를 쓴다.** 측정값을 호스트 파일로 받아야 대조가
기계적으로 되는데, 그 통로가 `reportData`(= `test_driver/`)뿐이다.

⚠️ 아이폰이 **잠겨 있으면** 개발자 이미지가 마운트되지 않아
`Could not find the built application bundle` 로 끝난다. 더 헷갈리는 건
**`flutter drive` 가 그래도 종료코드 0 을 낸다**는 점이다 — 성공 여부는 종료코드가
아니라 `build/glyph_ink_device.json` 이 생겼는지로 본다.
확인: `xcrun devicectl device info lockState --device <기기>` → `passcodeRequired: false`

무엇을 재나: 자산 한 장을 240×240 흰 캔버스에 그려 **경계 상자**, **8×8 격자별 잉크
비율(모양 지문)**, 총 잉크량을 낸다. 판정은 **경계와 지문**이고 총 잉크량은 참고다
(iOS 래스터화가 호스트보다 획을 얇게 그려 글꼴 자산이 −4~5% 나온다).

★**총 잉크량만으로는 부족하다**: 특수문자·숫자 자산은 테두리가 함께 들어 있어,
글꼴이 없어 대체 글리프가 그려져도 **경계는 그대로**다. 지문이 그 경우를 잡는다.

## 무엇을 확인하나 — `late_additions_device_test.dart`

09-10 에 실기기 왕복을 **한 번 통과시킨 뒤에도 작업을 계속**했다. 그 뒤에 넣은 여섯은
기기에서 한 번도 안 돌았고, `new_features_device_test.dart` 는 그 검증 시점까지의
것만 덮는다. 여기 있는 여섯은 전부 **호스트 테스트가 원리상 닿지 못하는 층**에 걸린다.

| 항목 | 호스트에서 못 보는 것 |
|---|---|
| AI 동의 | `flutter_secure_storage` = 실제 **키체인** |
| PDF 출력 | 실제 GPU 래스터(`toImage`)에서 나온 픽셀 |
| 학급 현황 | 실제 소켓으로 오는 `student.join` |
| 제출 ACK | 실제 소켓 왕복 |
| 오프라인 번들 | 실제 플랫폼 암호 구현 |
| 획순 지도 | 실제 포인터 이벤트(제스처 아레나) |

★**PDF 판정을 내 파서에 맡기지 않는다** — 내 포맷을 내 파서가 통과시키면 순환 논증이다.
헤더·`%%EOF` 바이트, `startxref` 오프셋이 **실제로 `xref` 표를 가리키는지**, 이미지
스트림을 **표준 zlib 으로 풀어** 정확히 `w*h*3` 인지를 본다.

⚠️**획은 칸(`HangulWritingCell`) 안에서만 받는다.** 학습지 전체 사각형을 기준으로
제스처를 잡으면 칸 밖에 떨어져 아무 일도 안 일어난다 — "획순 지도가 동작 안 한다"로
오판하기 쉬운 자리다(작성 중 실제로 그랬다).

⚠️**QR 경계는 3음절이다**(2026-09-11 실측). 2음절 1문항 898B 는 들어가고 4음절
1438B 부터 넘는다(상한 1200B). 실제 받아쓰기 10문항은 11974B 로 한참 넘는다.
무게의 70% 가 `expectedGlyphsJson` 이고 학생 기기가 로컬로 다시 분해할 수 있는
값이라(골든 벡터가 동치를 강제) 빼면 10문항이 962B 지만, **프로토콜 변경이라
손대지 않고** 사실을 단언으로 못박아 두었다 — 슬림화하면 그 단언이 깨져 알려 준다.
사용자에게 깨지는 것은 없다: 번들 QR 화면 자체가 없고(`QrImageView` 는 세션 페어링
전용) 교사 화면은 파일·클립보드로 떨구며 안내 문구를 덧붙인다.

## 🔴 실기기에서는 `flutter test integration_test` 가 아니라 `flutter drive` 를 쓴다

2026-09-10 실측: 같은 기기·같은 테스트인데

```
flutter test integration_test/x.dart -d <기기>
  → Error starting debug session in Xcode:
    Timed out waiting for CONFIGURATION_BUILD_DIR to update.   ← 2회 연속 실패

flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/x.dart -d <기기>
  → All tests passed.                                          ← 한 번에 성공
```

`flutter test` 는 Xcode 디버그 세션에 붙는 방식이라 이 타임아웃을 맞는다.
`flutter drive` 는 앱을 띄우고 VM 서비스로 접속해서 그 단계를 지나지 않는다.
**시뮬레이터에서는 둘 다 되므로 이 차이는 실기기에서만 드러난다.**

⚠️새 플러그인을 추가하면(파드 구성이 바뀌면) **흰 화면 함정이 재발**한다.
`flutter clean` + `rm -rf ios/Pods` + `pub get` + `pod install` 후 다시 돌릴 것.

## 🔴 흰 화면 + VM 미발견에는 원인이 **둘** 있다 — 로그로 가른다

2026-09-12 에 하마터면 엉뚱한 것을 고칠 뻔했다. 증상이 똑같다:
**앱이 흰 화면이고 `The Dart VM Service was not discovered` 가 뜬다.**

| 원인 | 로그가 덧붙이는 말 | 조치 |
|---|---|---|
| `objective_c` dlopen (빌드 갈아타기) | 없음 — 그냥 타임아웃 | `flutter clean` + `rm -rf ios/Pods` + `pub get` |
| **앱의 로컬 네트워크 권한** (무선일 때만) | `Click "Allow" … Settings > Your App Name > Local Network` | **설정 > 초민정음 > 로컬 네트워크 켜기** (탭 한 번) |

무선 디버깅은 앱이 자기 VM 서비스를 **mDNS 로 광고**하고 호스트가 찾아가는 구조라,
iOS 가 그 광고를 권한으로 막으면 발견이 안 된다. **앱을 지웠다 새로 설치하면 이 권한이
초기화된다** — 09-08 에 허용해 둔 것이 09-12 재설치로 날아가 그대로 걸렸다.
⚠️**설정에서 켜도 지금 도는 앱은 회복 못 한다**(iOS 가 앱 재시작을 요구) — 켜고 다시 돌릴 것.

★**케이블로 꽂으면 이 권한이 아예 필요 없다**(VM 서비스가 USB 로 간다).
사람이 자리에 없는 채로 무인 검증을 돌릴 거라면 케이블이 맞다.

⚠️**`integration_test` 앱은 원래 흰 화면이다** — 테스트가 위젯을 펌프하기 전까지 아무것도
안 그린다. 드라이버가 붙기 전에 죽으면 흰 화면만 남으므로, **흰 화면 자체는 아무것도
말해 주지 않는다.** 판정은 로그로 한다.

## 🔴 무료 프로비저닝에서는 **설치 1회 = 신뢰 탭 1회**다

2026-09-12 에 테스트 3개를 연달아 큐에 넣었다가 중단됐다. `flutter drive` 는
실행할 때마다 앱을 **지웠다 다시 설치**하는데, 이 앱은 개인 Apple ID 무료
프로비저닝(`Apple Development: …@gmail.com`)으로 서명되고 **그 개발자의 앱이 기기에서
사라지면 신뢰 항목도 같이 날아간다.** 그래서 매번

> 설정 > 일반 > VPN 및 기기 관리 > 개발자 앱 > 신뢰

를 사람이 눌러야 한다. 자리를 비우면 거기서 멈춘다.

⚠️**"인증서당 1회"는 유료 개발자 계정 기준이고 여기엔 틀리다.** 무료 서명은
인증서도 7일 만료다. 유료 계정($99/yr)이면 이 문제 자체가 없다.

⇒ **`all_device_tests.dart` 로 묶어 한 번에 돌린다.** 설치 1회 · 신뢰 1회.

## 🔴 device ↔ simulator 를 오가면 그때마다 흰 화면 함정을 밟는다

같은 날, 합본을 시뮬레이터에서 예행 연습하려다 정확히 이걸 맞았다(직전까지 device
빌드를 반복한 뒤였다). 증상은 **앱 isolate 는 resume 되는데 driver extension 이
끝내 안 올라오고**, `flutter:` 출력이 **한 줄도 없다**.

⇒ 검증 대상이 실기기면 **시뮬레이터 예행을 넣지 않는 쪽이 빠르다.** 굳이 오가야
한다면 매번 `flutter clean` + `rm -rf ios/Pods` + `pub get` + `pod install` 값을 치러야 한다.
⚠️`flutter clean` 은 `build/` 를 지우므로 **`build/glyph_ink_host.json`(호스트 기준선)이
같이 날아간다** — 먼저 빼 두고 나중에 되돌릴 것.

## 🔴 기기가 `unavailable` 이면 폰이 아니라 **맥**을 먼저 의심한다

2026-09-12: 폰은 잠금 해제·같은 Wi-Fi·개발자 모드 ON 이었는데도 이틀 내내
`unavailable` 이었다. 실제로는 **맥의 CoreDevice 데몬이 09-10 마지막 케이블 연결
상태에 굳어** 있었다.

```bash
# 진단 — 폰이 정말 안 보이는 건지부터 가른다
xcrun devicectl list devices --json-output /tmp/d.json   # tunnelState / transportType / pairingState
ping6 -c2 <기기이름>.local                                 # LAN 도달 여부(= 폰은 멀쩡한가)

# 조치 — 두 데몬을 죽이면 launchd 가 다시 띄운다(sudo 불필요)
pkill -f remotepairingd; pkill -f CoreDeviceService
```

실측: `tunnel: unavailable / transport: None` → 재기동 후 `tunnel: connected /
transport: localNetwork`, `flutter devices` 가 곧바로 무선 기기로 인식.

## 실서버 업싱크까지 태우기 (선택 · 9단계)

서버 정보를 주면 앱의 업싱크 경로를 **끝까지** 검증한다. 안 주면 그 단계를 건너뛴다.

⚠️ 게이트웨이(nginx)는 외부 요청에 HTTP Basic 을 요구하고 **앱은 그 자격을 보낼 수
없다**(`UpsyncConfig` 에 필드가 없다 — 원래 LAN 직결 전제 설계다). 그래서 검증은
SSH 터널로 서버에 직결한다. 서버는 이 요청을 `127.0.0.1` 로 보므로 게이트를 지나지 않는다.

```bash
# 1) 터널 (서버는 이 요청을 로컬로 본다 → gwauth 우회)
ssh -f -N -L 18100:127.0.0.1:8100 homelab25

# 2) 교사 토큰
TOKEN=$(curl -s -X POST http://127.0.0.1:18100/api/auth/teacher/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"<교사 이메일>","password":"<비번>"}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')

# 3) 학급 UUID
curl -s http://127.0.0.1:18100/api/classrooms -H "X-Auth-Token: $TOKEN"

# 4) 실행
flutter test integration_test -d <기기> \
  --dart-define=UPSYNC_URL=http://127.0.0.1:18100 \
  --dart-define=UPSYNC_TOKEN="$TOKEN" \
  --dart-define=UPSYNC_CLASSROOM=<학급 UUID>

# 5) 터널 정리
pkill -f 'ssh -f -N -L 18100'
```

성공하면 화면 배너가 `업로드 완료 — 신규 1건 · 명단 연결 필요한 기기 1대` 다
(기기가 학생 명단에 아직 안 묶여 있으면 "명단 연결 필요"가 정상이다).

🔴 **이 단계는 실서버에 세션·답안 행을 남긴다.** 리허설 전에 지울 것:

```sql
-- 남은 것 확인 후
DELETE FROM attempt WHERE session_id='<세션>';
DELETE FROM exam_session WHERE id='<세션>';
```

문항은 `contentHash` 로 재사용되므로 같은 문장이면 새로 생기지 않는다(실측 확인).

## 주의

- 허브 포트는 `SyncDefaults.hubPort`(30020) 고정이다. 다른 프로세스가 쓰고 있으면 실패한다
- 테스트는 끝에 `LocalStore.clearAll()` 로 자기가 만든 것을 지운다.
  실기기에 실제 수업 이력이 있으면 **함께 지워진다** — 리허설 데이터를 남겨야 하면 먼저 확인할 것
- **교사 화면은 긴 스크롤 화면이다.** 화면 밖 위젯을 `tap` 하면 **예외 없이 빗나가서**
  "눌렀는데 아무 일도 안 일어난" 것처럼 보인다(첫 실행에서 겪었다 — "연결 정보 보기"를
  펼치자 내용이 길어져 "숨기기" 버튼이 밖으로 밀렸다). 그래서 조작은 전부
  `tapVisible`/`typeVisible`(= `ensureVisible` 후 조작)을 쓴다
- **서버는 `attemptId`·`sessionId`·`classroomId` 를 UUID 로 검증한다.** 아무 문자열을
  넣으면 인증을 통과하고도 400 이 된다(여기서 한 번 걸렸다). 앱은 `Uuid().v4()` 를 쓴다
