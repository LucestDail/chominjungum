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
