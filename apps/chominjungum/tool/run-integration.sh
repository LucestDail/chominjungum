#!/bin/zsh
# 교실 왕복 통합 테스트를 시뮬레이터(또는 실기기)에서 돌린다.
#
#   tool/run-integration.sh              # 부팅된 기기 중 첫 번째, 없으면 시뮬레이터 하나 부팅
#   tool/run-integration.sh <device-id>  # 특정 기기 지정 (실기기 리허설)
#
# ⚠️ **물리 마우스·키보드를 쓰지 않는다.** 테스트가 코드로 탭·입력한다.
#    (CGEvent 로 실제 커서를 움직이는 방식은 사용자 작업을 방해한다 — 2026-09-07)
#
# 실패하면 아래를 먼저 볼 것:
#   - "허브 시작 실패: ... address already in use"
#       → 포트 30020 을 다른 프로세스(앞서 띄운 앱)가 쓰고 있다.
#         `lsof -iTCP:30020 -sTCP:LISTEN` 로 찾아 종료.
#   - "출제 실패: ..." 가 화면에 있다는 실패
#       → 출제가 다시 네트워크를 타고 있다. lib/services/dictation_composer.dart 확인.
#   - 학생 수신 타임아웃
#       → hubHost 가 127.0.0.1 로 들어갔는지, 시뮬레이터 네트워크가 살아 있는지.
#   - 실기기에서 연결만 안 될 때
#       → iOS 로컬 네트워크 권한 프롬프트를 수락했는지(기기 설정 > 앱 > 로컬 네트워크).

set -e
cd "$(dirname "$0")/.."

DEVICE="$1"

if [[ -z "$DEVICE" ]]; then
  DEVICE=$(xcrun simctl list devices booted -j 2>/dev/null \
    | python3 -c "
import json,sys
d=json.load(sys.stdin)['devices']
for runtime, devs in d.items():
    for x in devs:
        if x.get('state')=='Booted':
            print(x['udid']); raise SystemExit
" || true)
fi

if [[ -z "$DEVICE" ]]; then
  echo "부팅된 기기가 없다 — iPhone 시뮬레이터를 하나 띄운다"
  DEVICE=$(xcrun simctl list devices available -j \
    | python3 -c "
import json,sys
d=json.load(sys.stdin)['devices']
for runtime, devs in sorted(d.items(), reverse=True):
    for x in devs:
        if x['name'].startswith('iPhone'):
            print(x['udid']); raise SystemExit
")
  xcrun simctl boot "$DEVICE"
  # 시뮬레이터 앱 없이도 flutter test 는 동작한다(창을 띄우지 않아 방해가 적다).
  sleep 8
fi

echo "── 기기: $DEVICE"
xcrun simctl list devices | grep "$DEVICE" || true
echo "── 포트 30020 점유 확인"
lsof -iTCP:30020 -sTCP:LISTEN 2>/dev/null || echo "   (비어 있음)"
echo "── 통합 테스트 실행"
flutter test integration_test -d "$DEVICE"
