#!/usr/bin/env python3
"""jammin hangul_1 SVG → flutter_svg용 (자모 획만, 격자·display:none 제거)."""
from __future__ import annotations

import re
import shutil
import sys
from pathlib import Path

JAMMIN_HANGUL_1 = Path(__file__).resolve().parents[4] / "jammin" / "src" / "main" / "resources" / "static" / "hangul_1"
APP_HANGUL = Path(__file__).resolve().parent.parent / "assets" / "hangul"

# cls-5 / stroke-width 20px = 실제 자모 획
GLYPH_CLASS = re.compile(r'\bcls-5\b')
GRID_STROKE = re.compile(r'stroke-width:\s*3px|stroke-width="3"')


def parse_classes(style_text: str) -> dict[str, dict[str, str]]:
    inner = re.sub(r"<style[^>]*>|</style>", "", style_text, flags=re.I | re.S).strip()
    classes: dict[str, dict[str, str]] = {}
    for match in re.finditer(r"\.([a-zA-Z0-9_-]+)\s*\{([^}]*)\}", inner):
        name, body = match.group(1), match.group(2)
        props: dict[str, str] = {}
        for decl in body.split(";"):
            if ":" not in decl:
                continue
            k, v = [x.strip() for x in decl.split(":", 1)]
            if k in ("fill", "stroke", "stroke-width", "stroke-linecap", "stroke-miterlimit", "stroke-dasharray"):
                props[k] = v.replace("px", "")
        classes[name] = props
    return classes


def is_glyph_tag(tag: str, class_map: dict[str, dict[str, str]]) -> bool:
    if GLYPH_CLASS.search(tag):
        return True
    m = re.search(r'\bclass="([^"]+)"', tag)
    if m:
        for cls in m.group(1).split():
            sw = class_map.get(cls, {}).get("stroke-width", "")
            if sw == "20":
                return True
    if re.search(r'stroke-width="20"', tag) or re.search(r"stroke-width:\s*20", tag):
        return True
    return False


def inline_glyph_tag(tag: str, class_map: dict[str, dict[str, str]]) -> str:
    m = re.search(r'\bclass="([^"]+)"', tag)
    props: dict[str, str] = {"fill": "none", "stroke": "#231F20"}
    if m:
        for cls in m.group(1).split():
            props.update(class_map.get(cls, {}))
    tag = re.sub(r'\s*class="[^"]*"', "", tag)
    insert = ""
    for k, v in props.items():
        if k == "display":
            continue
        if not re.search(rf'\b{re.escape(k)}=', tag):
            insert += f' {k}="{v}"'
    if tag.rstrip().endswith("/>"):
        return tag.rstrip()[:-2] + insert + " />"
    if tag.endswith(">"):
        return tag[:-1] + insert + ">"
    return tag + insert


def extract_glyphs(svg_text: str) -> str:
    style_m = re.search(r"<style[^>]*>.*?</style>", svg_text, flags=re.I | re.S)
    class_map = parse_classes(style_m.group(0)) if style_m else {}

    view_m = re.search(r'viewBox="([^"]+)"', svg_text)
    view_box = view_m.group(1) if view_m else "0 0 400 400"

    glyphs: list[str] = []
    for tag_m in re.finditer(r"<(path|line)\b[^>]*/>", svg_text, flags=re.I):
        tag = tag_m.group(0)
        if is_glyph_tag(tag, class_map):
            glyphs.append(inline_glyph_tag(tag, class_map))

    if not glyphs:
        # 이미 인라인된 static/hangul 형식: display none 없는 stroke-width 20만
        for tag_m in re.finditer(r"<(path|line)\b[^>]*/>", svg_text, flags=re.I):
            tag = tag_m.group(0)
            if 'display="none"' in tag or "display:none" in tag:
                continue
            if 'stroke-width="20"' in tag or GLYPH_CLASS.search(tag):
                if not GRID_STROKE.search(tag):
                    glyphs.append(re.sub(r'\s*display="[^"]*"', "", tag))

    body = "\n  ".join(glyphs)
    return (
        f'<?xml version="1.0" encoding="UTF-8"?>\n'
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{view_box}">\n'
        f"  {body}\n"
        f"</svg>\n"
    )


def main() -> None:
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else JAMMIN_HANGUL_1
    dst = Path(sys.argv[2]) if len(sys.argv) > 2 else APP_HANGUL
    if not src.is_dir():
        print(f"Source not found: {src}", file=sys.stderr)
        sys.exit(1)
    dst.mkdir(parents=True, exist_ok=True)
    n = 0
    for path in sorted(src.glob("*.svg")):
        out = extract_glyphs(path.read_text(encoding="utf-8"))
        (dst / path.name).write_text(out, encoding="utf-8")
        n += 1
    print(f"Prepared {n} glyph SVGs → {dst}")


if __name__ == "__main__":
    main()
