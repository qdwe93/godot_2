#!/usr/bin/env python3
"""레벨업 카드에 쓰는 UI 조각 생성 (별 등급, 빈 슬롯).

왜 코드로 그리는가
------------------
별은 imagegen 으로 뽑을 것이 아니다. 다섯 개가 나란히 놓여 **개수를 세는** 물건이라
모양이 매번 조금씩 달라지면 오히려 읽기 나빠진다. 폰트의 U+2605(★)를 쓰는 방법도
있지만 Godot 기본 폰트에 그 글자가 있다는 보장이 없고, 없으면 두부(□)가 나온다.
코드로 그리면 두 문제가 다 사라진다.

  python tools/make_ui_icons.py
"""

import math
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:
    raise SystemExit("Pillow가 필요하다:  pip install Pillow")

SIZE = 64
OUTLINE_WIDTH = 4

# 채워진 별 = 이미 올린 레벨, 빈 별 = 아직 남은 레벨.
# 빈 별은 카드 배경(#2E3440)보다 어두워야 "꺼져 있다"로 읽힌다.
STAR_FULL = (255, 197, 49, 255)      # #FFC531 금색
STAR_FULL_EDGE = (176, 122, 16, 255)
STAR_EMPTY = (58, 64, 78, 255)       # #3A404E
STAR_EMPTY_EDGE = (30, 34, 42, 255)

# 아직 안 얻은 스킬 슬롯. 카드가 아니라 슬롯 바에 쓴다.
SLOT_EMPTY = (42, 47, 58, 255)
SLOT_EMPTY_EDGE = (90, 98, 114, 255)

OUTPUT_DIR = Path(__file__).resolve().parent.parent / "assets" / "ui"


def star_points(centre: float, outer: float, inner: float) -> list:
    """5각별. 위쪽 꼭짓점부터 시작해 바깥·안쪽 반지름을 번갈아 찍는다."""
    points = []
    for index in range(10):
        radius = outer if index % 2 == 0 else inner
        angle = -math.pi / 2 + index * math.pi / 5
        points.append((centre + radius * math.cos(angle), centre + radius * math.sin(angle)))
    return points


def draw_star(fill: tuple, edge: tuple) -> Image.Image:
    # 안티에일리어싱을 위해 4배로 그린 뒤 줄인다.
    scale = 4
    canvas = Image.new("RGBA", (SIZE * scale, SIZE * scale), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    centre = SIZE * scale / 2.0
    outer = centre * 0.94
    draw.polygon(
        star_points(centre, outer, outer * 0.45),
        fill=fill,
        outline=edge,
        width=OUTLINE_WIDTH * scale,
    )
    return canvas.resize((SIZE, SIZE), Image.LANCZOS)


def draw_empty_slot() -> Image.Image:
    scale = 4
    canvas = Image.new("RGBA", (SIZE * scale, SIZE * scale), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    inset = 3 * scale
    draw.rounded_rectangle(
        [inset, inset, SIZE * scale - inset, SIZE * scale - inset],
        radius=8 * scale,
        fill=SLOT_EMPTY,
        outline=SLOT_EMPTY_EDGE,
        width=3 * scale,
    )
    return canvas.resize((SIZE, SIZE), Image.LANCZOS)


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    outputs = {
        "star_full.png": draw_star(STAR_FULL, STAR_FULL_EDGE),
        "star_empty.png": draw_star(STAR_EMPTY, STAR_EMPTY_EDGE),
        "slot_empty.png": draw_empty_slot(),
    }
    for name, image in outputs.items():
        image.save(OUTPUT_DIR / name)
        print(f"wrote {OUTPUT_DIR / name} ({SIZE}x{SIZE})")


if __name__ == "__main__":
    main()
