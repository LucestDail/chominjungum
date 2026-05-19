#!/usr/bin/env python3
"""jammin SVG의 CSS 클래스(.st0, .cls-1)를 인라인 속성으로 변환 — flutter_svg 호환."""
from __future__ import annotations

import re
import sys
from pathlib import Path


def css_to_attr(name: str, value: str) -> tuple[str, str] | None:
    name = name.strip()
    value = value.strip()
    if not name or not value:
        return None
    if name == "stroke-width":
        return ("stroke-width", value.replace("px", ""))
    if name in (
        "fill",
        "stroke",
        "stroke-miterlimit",
        "stroke-linecap",
        "stroke-linejoin",
        "stroke-dasharray",
        "opacity",
        "display",
    ):
        return (name, value)
    return None


def parse_style_block(style_text: str) -> dict[str, dict[str, str]]:
    inner = re.sub(r"^<style[^>]*>|</style>\s*$", "", style_text, flags=re.IGNORECASE | re.DOTALL).strip()
    classes: dict[str, dict[str, str]] = {}
    for match in re.finditer(r"([^{]+)\{([^}]*)\}", inner):
        selectors, body = match.group(1), match.group(2)
        props: dict[str, str] = {}
        for decl in body.split(";"):
            if ":" not in decl:
                continue
            pair = css_to_attr(*decl.split(":", 1))
            if pair:
                props[pair[0]] = pair[1]
        for sel in selectors.split(","):
            sel = sel.strip()
            if not sel.startswith("."):
                continue
            cls = sel[1:].strip()
            merged = dict(classes.get(cls, {}))
            merged.update(props)
            classes[cls] = merged
    return classes


def apply_class(tag: str, class_map: dict[str, dict[str, str]]) -> str:
    class_m = re.search(r'\bclass="([^"]+)"', tag)
    if not class_m:
        return tag
    cls_name = class_m.group(1).split()[0]
    props = class_map.get(cls_name)
    if not props:
        return tag
    tag = re.sub(r'\s*class="[^"]*"', "", tag)
    insert = ""
    for k, v in props.items():
        if k == "display" and v == "inline":
            continue
        if re.search(rf'\b{re.escape(k)}="', tag):
            continue
        insert += f' {k}="{v}"'
    if tag.endswith("/>"):
        return tag[:-2] + insert + " />"
    if tag.endswith(">"):
        return tag[:-1] + insert + ">"
    return tag


def inline_styles(svg_text: str) -> str:
    style_match = re.search(r"<style[^>]*>.*?</style>", svg_text, flags=re.DOTALL | re.IGNORECASE)
    if not style_match:
        return svg_text

    class_map = parse_style_block(style_match.group(0))
    out = re.sub(r"<style[^>]*>.*?</style>\s*", "", svg_text, count=1, flags=re.DOTALL | re.IGNORECASE)

    def repl(m: re.Match[str]) -> str:
        return apply_class(m.group(0), class_map)

    tag_pattern = r"<(line|path|rect|circle|ellipse|polyline|polygon|g)\b[^>]*/>"
    out = re.sub(tag_pattern, repl, out)
    out = re.sub(
        r"<(line|path|rect|circle|ellipse|polyline|polygon|g)\b([^>]*>)",
        repl,
        out,
    )
    return out


def process_dir(directory: Path) -> int:
    count = 0
    for path in sorted(directory.glob("*.svg")):
        original = path.read_text(encoding="utf-8")
        converted = inline_styles(original)
        if converted != original:
            path.write_text(converted, encoding="utf-8")
            count += 1
    return count


def main() -> None:
    target = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "assets" / "hangul"
    if not target.is_dir():
        print(f"Not found: {target}", file=sys.stderr)
        sys.exit(1)
    n = process_dir(target)
    remaining = sum(1 for p in target.glob("*.svg") if 'class="st' in p.read_text() or 'class="cls' in p.read_text())
    print(f"Updated {n} SVG files; remaining class= attributes: {remaining}")


if __name__ == "__main__":
    main()
