#!/usr/bin/env python3
"""바닥 색을 바꾸면 어느 스프라이트가 대비 미달이 되는지 **그리기 전에** 계산한다.

왜 필요한가
-----------
M22(밝은 바닥)의 위험은 "스프라이트를 다시 칠해야 한다"가 아니라 **얼마나 많이
깨지는지 모르는 것**이었다. 그림을 8장 다시 만들고 나서 재는 것은 너무 늦다.
이 도구는 그림을 건드리기 전에 후보 바닥 색에 대해 답을 준다.

`check_sprite_luminance.py` 와의 차이: 그쪽은 **지금 배경 기준으로 실제 파일을**
재고, 이쪽은 **가상의 배경 기준으로 이미 잰 휘도를** 굴려 본다. 후보를 고를 때는
이쪽, 결과를 판정할 때는 그쪽이다.

    python tools/contrast_preview.py                 # 기본 후보들을 비교
    python tools/contrast_preview.py A9A3C4 6A6480   # 특정 색만

주의: SPRITE_LUMINANCE 는 `check_sprite_luminance.py` 가 출력한 **측정 휘도**다.
스프라이트를 다시 만들면 이 표도 다시 채워야 한다. 안 그러면 옛 그림을 기준으로
계획을 세우게 된다.
"""

import sys

MIN_CONTRAST = 3.0  # check_sprite_luminance.py 와 같은 기준

# `python tools/check_sprite_luminance.py assets/sprites` 의 "측정휘도" 열 (2026-08-15)
SPRITE_LUMINANCE = {
    "player": 0.7127,
    "enemy_boss": 0.3863,
    "enemy_tank": 0.2889,
    "enemy_basic": 0.2379,
    "enemy_fast": 0.2255,
    "orbital": 0.1750,
    "xp_gem": 0.1668,
    "projectile": 0.1501,
}

DEFAULT_CANDIDATES = [
    ("1E1E26", "현재 격자선"),
    ("3A3A4A", "살짝 밝게"),
    ("6A6480", "중간"),
    ("A9A3C4", "레퍼런스급 — M22 채택"),
]


def srgb_to_linear(channel: float) -> float:
    return channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4


def relative_luminance(rgb: tuple) -> float:
    red, green, blue = (srgb_to_linear(value) for value in rgb)
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue


def hex_to_rgb(text: str) -> tuple:
    text = text.lstrip("#")
    if len(text) != 6:
        raise SystemExit("색은 RRGGBB 6자리로 준다: %r" % text)
    return tuple(int(text[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def contrast(first: float, second: float) -> float:
    high, low = max(first, second), min(first, second)
    return (high + 0.05) / (low + 0.05)


def main() -> int:
    if len(sys.argv) > 1:
        candidates = [(value, "") for value in sys.argv[1:]]
    else:
        candidates = DEFAULT_CANDIDATES

    print("=" * 72)
    print("경고: 이 수치는 M22 외곽선을 굽기 전에 측정한 값이다.")
    print("타일이 만들어진 뒤에는 check_sprite_luminance.py의 실제 판정을 기준으로 삼는다.")
    print("=" * 72)
    print("기준 %.1f:1 · 스프라이트 %d종" % (MIN_CONTRAST, len(SPRITE_LUMINANCE)))
    for hex_colour, label in candidates:
        background = relative_luminance(hex_to_rgb(hex_colour))
        print("\n#%s %s  (배경 휘도 %.4f)" % (hex_colour.upper().lstrip("#"), label, background))
        failures = 0
        for name, luminance in sorted(SPRITE_LUMINANCE.items(), key=lambda item: -item[1]):
            ratio = contrast(luminance, background)
            ok = ratio >= MIN_CONTRAST
            failures += 0 if ok else 1
            print("  %-12s %7.2f:1  %s" % (name, ratio, "통과" if ok else "**미달**"))
        print("  -> 미달 %d종 / %d종" % (failures, len(SPRITE_LUMINANCE)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
