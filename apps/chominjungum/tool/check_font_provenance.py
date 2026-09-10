#!/usr/bin/env python3
"""앱 글꼴이 웹·jammin 과 **같은 글꼴인지** 윤곽으로 확인한다.

## 왜 해시로는 안 되나 (2026-09-10 실제로 헛다리를 짚었다)

앱은 `KCCDodamdodamR.ttf`(3.1MB), 웹은 `KCCDodamdodam.woff`(764KB)를 쓴다.
파일 해시가 당연히 다르고, 테이블 단위로 봐도 `glyf`·`loca` 가 달라서 **97.2% 의
글리프가 다른 것처럼 보인다.** 그런데 좌표를 실제로 디코딩하면 13789개 전부
**완전히 같다** — 차이는 좌표 인코딩(플래그 압축) 방식뿐이다.

그러니 판정은 **바이트가 아니라 윤곽**으로 해야 한다.

## 무엇을 막나

jammin 은 글꼴을 **두 버전** 배포한다:

    KCCDodamdodam(Windows용).ttf   v2.0.0 · 글리프 13789
    KCCDodamdodam_OTF(MAC용).otf   v3.0.0 · 글리프 18180   ← 모양이 다르다

앱이 v3 로 바뀌면 학습지의 **숫자·문장부호 모양이 웹과 달라진다**. 자모는 SVG 라
멀쩡하니 눈에 잘 띄지도 않는다. 그 순간을 잡는 것이 이 검사다.

## 쓰는 법

    python3 tool/check_font_provenance.py     # 0 = 동일, 1 = 다름
"""

from __future__ import annotations

import os
import struct
import sys
import zlib
from pathlib import Path

APP_DIR = Path(__file__).resolve().parent.parent      # apps/chominjungum
WORKSPACE = APP_DIR.parent.parent.parent              # 형제 저장소가 놓이는 자리

APP = APP_DIR / "assets" / "fonts" / "KCCDodamdodamR.ttf"

# 절대경로를 박아 두면 이 맥 한 대에서만 동작한다.
#   ① 환경변수 `CHOMINJUNGUM_WEB_DIR`  ② 워크스페이스 형제 저장소
WEB = Path(
    os.environ.get("CHOMINJUNGUM_WEB_DIR")
    or WORKSPACE / "chominjungum-web"
) / "frontend/public/fonts/KCCDodamdodam.woff"


def read_sfnt(data: bytes) -> dict[str, bytes]:
    """ttf/otf/woff 컨테이너에서 테이블을 꺼낸다."""
    tables: dict[str, bytes] = {}
    if data[:4] == b"wOFF":
        num = struct.unpack(">H", data[12:14])[0]
        off = 44
        for _ in range(num):
            tag, o, clen, olen, _cs = struct.unpack(">4sIIII", data[off:off + 20])
            off += 20
            raw = data[o:o + clen]
            tables[tag.decode()] = zlib.decompress(raw) if clen != olen else raw
    else:
        num = struct.unpack(">H", data[4:6])[0]
        off = 12
        for _ in range(num):
            tag, _cs, o, length = struct.unpack(">4sIII", data[off:off + 16])
            off += 16
            tables[tag.decode()] = data[o:o + length]
    return tables


def loca_offsets(t: dict[str, bytes]) -> list[int]:
    fmt = struct.unpack(">h", t["head"][50:52])[0]
    n = struct.unpack(">H", t["maxp"][4:6])[0]
    d = t["loca"]
    if fmt == 0:
        return [struct.unpack(">H", d[i * 2:i * 2 + 2])[0] * 2 for i in range(n + 1)]
    return [struct.unpack(">I", d[i * 4:i * 4 + 4])[0] for i in range(n + 1)]


def outline(g: bytes):
    """글리프 → 모양을 결정하는 값만 (인코딩 방식은 버린다)."""
    if not g:
        return ("empty",)
    ncont = struct.unpack(">h", g[0:2])[0]
    bbox = struct.unpack(">4h", g[2:10])
    if ncont < 0:
        return ("composite", bbox, g[10:])

    off = 10
    ends = [struct.unpack(">H", g[off + i * 2:off + i * 2 + 2])[0] for i in range(ncont)]
    off += ncont * 2
    npts = (ends[-1] + 1) if ends else 0
    ilen = struct.unpack(">H", g[off:off + 2])[0]
    off += 2 + ilen  # 힌팅 인스트럭션은 모양이 아니라 렌더 보정이라 뺀다

    flags: list[int] = []
    while len(flags) < npts:
        f = g[off]
        off += 1
        flags.append(f)
        if f & 8:  # repeat
            rep = g[off]
            off += 1
            flags += [f] * rep
    flags = flags[:npts]

    def coords(short_bit: int, same_bit: int) -> list[int]:
        vals, v = [], 0
        nonlocal off
        for f in flags:
            if f & short_bit:
                d = g[off]
                off += 1
                v += d if f & same_bit else -d
            elif not f & same_bit:
                v += struct.unpack(">h", g[off:off + 2])[0]
                off += 2
            vals.append(v)
        return vals

    xs = coords(2, 16)
    ys = coords(4, 32)
    # 온커브 플래그도 모양의 일부다
    return ("simple", bbox, tuple(ends), tuple(zip(xs, ys, (f & 1 for f in flags))))


def main() -> int:
    for p in (APP, WEB):
        if not p.exists():
            # 🔴 여기서 0(통과)을 내면 **검사하지 않은 것이 초록불로 보인다.**
            # 이 파일이 막으려는 실패가 바로 그런 종류라, 자기 자신이 같은 함정에
            # 빠지면 안 된다. 2 = "검사 못 함"으로 1(=틀렸다)과 구분한다.
            print(
                f"없음: {p}\n"
                "  → 형제 저장소로 두거나 CHOMINJUNGUM_WEB_DIR 를 지정하세요.",
                file=sys.stderr,
            )
            return 2

    a = read_sfnt(APP.read_bytes())
    w = read_sfnt(WEB.read_bytes())

    na = struct.unpack(">H", a["maxp"][4:6])[0]
    nw = struct.unpack(">H", w["maxp"][4:6])[0]
    if na != nw:
        print(f"❌ 글리프 수가 다르다 — 앱 {na} vs 웹 {nw} (다른 버전의 글꼴이다)")
        return 1

    if a["cmap"] != w["cmap"]:
        print("❌ cmap 이 다르다 — 문자↔글리프 대응이 갈렸다")
        return 1

    la, lw = loca_offsets(a), loca_offsets(w)
    diff = [
        g for g in range(na)
        if outline(a["glyf"][la[g]:la[g + 1]]) != outline(w["glyf"][lw[g]:lw[g + 1]])
    ]

    if diff:
        print(f"❌ 글리프 {na}개 중 {len(diff)}개의 윤곽이 다르다 — 예: {diff[:10]}")
        return 1

    print(f"✅ 앱·웹 글꼴 윤곽 동일 — 글리프 {na}개 (바이트 포장만 다르다)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
