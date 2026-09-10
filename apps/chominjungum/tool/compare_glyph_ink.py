#!/usr/bin/env python3
"""호스트 렌더와 실기기 렌더를 대조한다 — 자모 자산 83개.

## 무엇을 보나

`test/support/glyph_ink.dart` 가 자산 한 장을 240×240 흰 캔버스에 그리고
**잉크 픽셀의 비율과 경계 상자**를 잰다. 같은 측정을 두 곳에서 돌린다:

    호스트  flutter test test/glyph_ink_host_test.dart      → build/glyph_ink_host.json
    실기기  flutter drive … glyph_device_render_test.dart   → build/glyph_ink_device.json

두 값이 어긋나면 **기기에서만 다르게 그려졌다**는 뜻이다. 대표적으로:

  - 폰트가 번들에 없다 → `<text>` 자산(숫자·특수문자)이 대체 글리프로 바뀌어
    coverage 가 크게 튄다
  - 자산이 번들에서 누락 → coverage 0
  - 렌더러 차이로 선 굵기가 달라짐 → coverage 만 미세하게 다르고 경계는 같다

## 판정 기준

**경계 상자**는 1.5픽셀까지 같아야 한다 — 좌표를 원본 그대로 옮겼으므로 배치가
다를 이유가 없다. 실제로 83/83 이 이 안에 들어온다(2026-09-10 iPhone 실측).

**모양 지문**(8×8 격자별 잉크 비율)이 진짜 판정이다. 잉크가 *어디* 있는지를 보므로
글자가 다른 모양으로 바뀌면(대체 글리프 등) 반드시 걸린다.

**총 잉크량**은 참고만 한다. 기기 실측에서 글꼴로 그리는 자산(`!`·숫자·`?`)이
일관되게 −4~5%, 중성 일부가 +4% 나왔다 — iOS 의 래스터화가 호스트보다 획을 얇게
그린 것으로, 경계와 지문이 모두 일치하므로 **모양 차이가 아니다.** 방향이 제각각인
큰 차이만 의미가 있어 상한을 넉넉히 둔다.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
HOST = HERE / "build" / "glyph_ink_host.json"
DEVICE = HERE / "build" / "glyph_ink_device.json"

BBOX_TOL = 1.5 / 240        # 1.5픽셀
COVERAGE_REL_TOL = 0.08     # 총 잉크량 — 래스터화 차이를 넉넉히 허용
SIGNATURE_CELL_TOL = 0.06   # 격자 한 칸의 잉크 비율 차이(절대값)

# ## 허용치 6% 의 근거 (2026-09-10 iPhone 15 Pro Max 실측)
#
# 허용치는 "통과시키기 좋은 값"이 아니라 **판별력이 남는 값**이어야 한다.
# 그래서 통과를 확인한 뒤, 이 자가 실제로 무엇을 가려내는지 따로 쟀다:
#
#   같은 자산 호스트↔기기   중앙 1.0% · 최대 5.0%   ← 허용해야 하는 차이
#   숫자끼리 서로           최소 31.0%              ← 잡아내야 하는 차이
#
# 막으려는 실패는 **글꼴이 없어 대체 글리프가 그려지는 것**이고, 그 경우 지문은
# 최소 31% 벌어진다 — 허용치의 5배다. 여유가 충분하다.
#
# ⚠️한계: 자모끼리는 가장 닮은 쌍(종성 4535·4545)이 3.3% 라 지문만으로는 못 가른다.
# 자산이 서로 뒤바뀌는 상황은 여기서 막는 실패가 아니고(그건 출처 가드가 본다),
# 경계·총량도 함께 보므로 실용상 문제가 없다.


def load(path: Path) -> dict[int, dict]:
    if not path.exists():
        print(f"없음: {path}", file=sys.stderr)
        sys.exit(2)
    data = json.loads(path.read_text())
    return {g["code"]: g for g in data["glyphs"]}


def main() -> int:
    host, dev = load(HOST), load(DEVICE)

    only_host = sorted(set(host) - set(dev))
    only_dev = sorted(set(dev) - set(host))
    if only_host or only_dev:
        print(f"⚠️ 자산 목록이 다르다 — 호스트만 {only_host} · 기기만 {only_dev}")

    bad_box, bad_cov, bad_sig = [], [], []
    worst_cell = 0.0
    for code in sorted(set(host) & set(dev)):
        h, d = host[code], dev[code]
        for field in ("left", "top", "right", "bottom"):
            if abs(h[field] - d[field]) > BBOX_TOL:
                bad_box.append((code, field, h[field], d[field]))

        hc, dc = h["coverage"], d["coverage"]
        if hc > 0 and abs(hc - dc) / hc > COVERAGE_REL_TOL:
            bad_cov.append((code, hc, dc))

        hs, ds = h.get("signature") or [], d.get("signature") or []
        if len(hs) != len(ds):
            bad_sig.append((code, -1, 0.0))
            continue
        for i, (a, b) in enumerate(zip(hs, ds)):
            worst_cell = max(worst_cell, abs(a - b))
            if abs(a - b) > SIGNATURE_CELL_TOL:
                bad_sig.append((code, i, abs(a - b)))

    n = len(set(host) & set(dev))
    print(f"대조 {n}개")
    print(f"  모양 지문 불일치 {len(bad_sig)}건   (칸당 허용 ±{SIGNATURE_CELL_TOL:.0%}, "
          f"최대 실측차 {worst_cell:.1%})")
    print(f"  경계 불일치     {len(bad_box)}건   (허용 ±{BBOX_TOL * 240:.1f}px)")
    print(f"  총 잉크량 차이   {len(bad_cov)}건   (허용 ±{COVERAGE_REL_TOL:.0%}, 참고용)")

    for code, field, a, b in bad_box[:15]:
        print(f"  경계 {code} {field}: 호스트 {a:.4f} vs 기기 {b:.4f} "
              f"({abs(a - b) * 240:.2f}px)")
    for code, cell, delta in bad_sig[:15]:
        print(f"  지문 {code} 칸{cell}: 차이 {delta:.1%}")
    for code, a, b in bad_cov[:15]:
        print(f"  잉크 {code}: 호스트 {a:.4f} vs 기기 {b:.4f} ({(b - a) / a:+.1%})")

    # 모양(지문·경계)이 판정이다. 총 잉크량은 래스터화 차이라 단독으로는 실패시키지 않는다.
    if bad_box or bad_sig:
        print("\n❌ 기기 렌더의 **모양**이 호스트와 다르다")
        return 1
    if bad_cov:
        print("\n✅ 모양은 일치 — 총 잉크량만 허용치를 넘었다(래스터화 차이로 본다)")
        return 0
    print("\n✅ 기기 렌더가 호스트와 일치한다")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
