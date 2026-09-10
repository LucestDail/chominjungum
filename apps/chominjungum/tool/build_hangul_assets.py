#!/usr/bin/env python3
"""jammin 원본 자모 SVG → 앱 자산으로 변환한다 (좌표 오차 0).

## 왜 그대로 복사하지 않나

원본(`jammin/src/main/resources/static/hangul/*.svg`)은 브라우저를 전제로 만들어졌다:

  1. **한 파일에 자모가 여러 개** 들어 있고 `<style>.st5{display:none}</style>` 로
     하나만 보이게 한다. `flutter_svg` 는 CSS 를 완전히 지원하지 않아 그대로 쓰면
     숨겨진 자모까지 전부 그려진다.
  2. **부위별로 크롭된 조각**이라 viewBox 가 제각각이다
     (초성 419.5×218.3 · 중성 623.6×400.9 · 종성 623.6×221.1).
     앱 렌더러(`HangulGlyphCell`)는 자산이 **전체 상자 좌표계**라고 전제하고
     셀 전체에 `BoxFit.fill` 로 채운다.

그래서 **보이는 요소만 남기고 전체 상자(623.6) 좌표계로 옮긴다.**
좌표값 자체는 손대지 않고 `translate` 로만 옮기므로 **렌더 결과가 원본과 같다**.

## 배치 근거

`chominjungum-web/frontend/src/features/worksheet/hangul-metrics.ts` 와 같은 값이다
(그쪽은 원본 SVG 를 그대로 쓰고 CSS 로 배치한다 — 두 구현이 같은 좌표를 쓰게 맞췄다):

  초성 → 좌상단 (0, 0)
  중성 → 좌상단 (0, 0), 폭 전체
  종성 → **바닥 기준** (0, BOX - 221.1 = 402.5)
  특수·숫자 → 폭을 상자에 맞추고 높이는 캔버스 비율 (BOX / 598.28)

## 쓰는 법

    python3 tool/build_hangul_assets.py          # 변환 + assets/hangul 갱신
    python3 tool/build_hangul_assets.py --check  # 갱신 없이 원본과 어긋난 것만 보고

원본이 바뀌면 다시 돌린다. 결과물은 커밋한다(빌드 때 파이썬을 요구하지 않기 위해).
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path
from xml.etree import ElementTree as ET

APP_DIR = Path(__file__).resolve().parent.parent      # apps/chominjungum
WORKSPACE = APP_DIR.parent.parent.parent              # jammin 과 같은 자리(형제 저장소)

# 원본 위치. 절대경로를 박아 두면 **이 맥 한 대에서만 동작**하고 다른 곳에서는
# 조용히 건너뛴다 — 검사하지 않는 검사기가 된다. 그래서
#   ① 환경변수 `JAMMIN_DIR`  ② 워크스페이스 형제 저장소  순으로 찾는다.
SRC = Path(
    os.environ.get("JAMMIN_DIR")
    or WORKSPACE / "jammin"
) / "src/main/resources/static/hangul"

DST = APP_DIR / "assets" / "hangul"

BOX = 623.6
SVG_NS = "http://www.w3.org/2000/svg"

# 유니코드 자모 코드 범위 — jammin 파일명 규약
CHO = range(4352, 4371)   # 초성 19
JUNG = range(4449, 4470)  # 중성 21
JONG = range(4520, 4547)  # 종성 27
NO_JONG = 4519            # 받침 없음

# 특수문자·숫자 캔버스 높이 (폭은 598.28 로 공통) — 실측값
SPECIAL_HEIGHT = {44: 713.95, 46: 744.95, 63: 601.78}
SPECIAL_HEIGHT_DEFAULT = 598.28
SPECIAL_WIDTH = 598.28


def parse_style(root: ET.Element) -> dict[str, dict[str, str]]:
    """`<style>` 의 `.stN{a:b;c:d}` 를 클래스별 속성 사전으로."""
    out: dict[str, dict[str, str]] = {}
    for st in root.iter(f"{{{SVG_NS}}}style"):
        text = st.text or ""
        # ⚠️콤마로 묶인 셀렉터를 놓치면 안 된다.
        #   `.cls-1, .cls-2, .cls-3 { fill: none; stroke: … }`
        # 특수문자·숫자 SVG 가 이 형식이라, 단일 셀렉터만 잡으면 `fill:none` 이 빠져
        # 도형이 채워진 회색 덩어리로 렌더된다(실제로 그렇게 깨졌다).
        for m in re.finditer(r"((?:\.[A-Za-z0-9_-]+\s*,\s*)*\.[A-Za-z0-9_-]+)\s*\{([^}]*)\}", text):
            selectors, body = m.group(1), m.group(2)
            props: dict[str, str] = {}
            for decl in body.split(";"):
                if ":" in decl:
                    k, v = decl.split(":", 1)
                    props[k.strip()] = v.strip()
            for sel in selectors.split(","):
                name = sel.strip().lstrip(".")
                out.setdefault(name, {}).update(props)
    return out


def is_hidden(el: ET.Element, styles: dict[str, dict[str, str]]) -> bool:
    for cls in (el.get("class") or "").split():
        if styles.get(cls, {}).get("display") == "none":
            return True
    return "display:none" in (el.get("style") or "").replace(" ", "")


def strip_hidden(el: ET.Element, styles: dict[str, dict[str, str]]) -> None:
    """숨겨진 자식을 통째로 제거한다(CSS 를 못 읽는 렌더러 대비)."""
    for child in list(el):
        if is_hidden(child, styles):
            el.remove(child)
        else:
            strip_hidden(child, styles)


def inline_styles(el: ET.Element, styles: dict[str, dict[str, str]]) -> None:
    """클래스 스타일을 속성으로 펼친다. 이미 있는 속성은 건드리지 않는다."""
    for child in el.iter():
        cls = child.get("class")
        if not cls:
            continue
        for name in cls.split():
            for k, v in styles.get(name, {}).items():
                if k == "display":
                    continue  # 숨김은 위에서 제거했고, inline 은 기본값이라 불필요
                if child.get(k) is None:
                    child.set(k, v)
        del child.attrib["class"]


# 원본 특수문자·숫자는 `<text>` 로 KCC 도담도담체를 써서 그린다.
# 원본이 쓰는 이름(`KCCDodamdodamOTF-KSCpc-EUC-H`)은 앱에 등록된 이름과 달라
# `flutter_svg` 가 폰트를 못 찾고 **대체 글리프(회색 네모)** 를 그린다(실제로 그랬다).
# 같은 글꼴(KCCDodamdodam v2.0.0)이므로 이름만 앱 등록명으로 바꾼다.
APP_FONT_FAMILY = "KCCDodamdodamR"


def retarget_fonts(root: ET.Element) -> None:
    for el in root.iter():
        fam = el.get("font-family")
        if fam and "KCCDodamdodam" in fam:
            el.set("font-family", APP_FONT_FAMILY)
        size = el.get("font-size")
        if size and size.endswith("px"):
            el.set("font-size", size[:-2])  # flutter_svg 는 단위 없는 값이 안전하다


def viewbox_of(root: ET.Element) -> tuple[float, float, float, float]:
    vb = root.get("viewBox")
    if not vb:
        raise ValueError("viewBox 없음")
    x, y, w, h = (float(v) for v in vb.replace(",", " ").split())
    return x, y, w, h


def placement(code: int, w: float, h: float) -> tuple[float, float, float]:
    """(dx, dy, scale) — 전체 상자 좌표계로 옮기는 변환."""
    if code in CHO or code in JUNG:
        return 0.0, 0.0, 1.0
    if code in JONG:
        return 0.0, BOX - h, 1.0          # 바닥 기준
    if code == NO_JONG:
        return 0.0, BOX - h, 1.0
    # 특수문자·숫자·빈칸: 폭을 상자에 맞춘다
    if abs(w - BOX) < 1.0:                 # 빈칸(623.62) 등 이미 상자 크기
        return 0.0, 0.0, 1.0
    return 0.0, 0.0, BOX / SPECIAL_WIDTH


def convert(path: Path) -> str:
    code_txt = path.stem
    ET.register_namespace("", SVG_NS)
    tree = ET.parse(path)
    root = tree.getroot()

    styles = parse_style(root)
    for st in list(root.iter(f"{{{SVG_NS}}}style")):
        for parent in root.iter():
            if st in list(parent):
                parent.remove(st)
    strip_hidden(root, styles)
    inline_styles(root, styles)
    retarget_fonts(root)
    # 스타일을 걷어낸 뒤 남는 빈 <defs> 는 지운다.
    for parent in root.iter():
        for child in list(parent):
            if child.tag == f"{{{SVG_NS}}}defs" and len(child) == 0:
                parent.remove(child)

    _, _, w, h = viewbox_of(root)
    try:
        code = int(code_txt)
    except ValueError:
        code = -1  # 000000.svg 등
    dx, dy, scale = placement(code, w, h)

    body = "".join(ET.tostring(c, encoding="unicode") for c in list(root))
    transform = []
    if dx or dy:
        transform.append(f"translate({dx:g} {dy:g})")
    if scale != 1.0:
        transform.append(f"scale({scale:.6f})")
    inner = f'<g transform="{" ".join(transform)}">{body}</g>' if transform else body

    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        f'<!-- 생성물 — 직접 고치지 말 것. tool/build_hangul_assets.py 로 만든다.\n'
        f'     원본: jammin/src/main/resources/static/hangul/{path.name}'
        f' (viewBox {w:g}x{h:g})\n'
        f'     좌표는 원본 그대로이고 전체 상자 {BOX:g} 좌표계로 옮기기만 했다. -->\n'
        f'<svg xmlns="{SVG_NS}" viewBox="0 0 {BOX:g} {BOX:g}">{inner}</svg>\n'
    )


def main() -> int:
    check = "--check" in sys.argv
    if not SRC.is_dir():
        # ⚠️2 = "검사 못 함"(1 = "검사했고 틀렸다"와 구분한다).
        # 조용히 0 을 내면 검사하지 않은 것이 통과로 보인다.
        print(f"원본 없음: {SRC}\n  → jammin 저장소를 워크스페이스 형제로 두거나 JAMMIN_DIR 를 지정하세요.", file=sys.stderr)
        return 2
    DST.mkdir(parents=True, exist_ok=True)

    changed, same = [], 0
    for path in sorted(SRC.glob("*.svg")):
        out = convert(path)
        target = DST / path.name
        if target.exists() and target.read_text(encoding="utf-8") == out:
            same += 1
            continue
        changed.append(path.name)
        if not check:
            target.write_text(out, encoding="utf-8")

    # 원본에 없는 잔여 파일
    extra = sorted(p.name for p in DST.glob("*.svg") if not (SRC / p.name).exists())

    print(f"원본 {len(list(SRC.glob('*.svg')))}개 · 그대로 {same} · {'차이' if check else '갱신'} {len(changed)}")
    for n in changed[:10]:
        print(f"  - {n}")
    if len(changed) > 10:
        print(f"  … 외 {len(changed) - 10}개")
    if extra:
        print(f"⚠️ 원본에 없는 파일 {len(extra)}개: {extra[:5]}")
    return 1 if (check and (changed or extra)) else 0


if __name__ == "__main__":
    raise SystemExit(main())
