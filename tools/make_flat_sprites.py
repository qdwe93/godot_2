"""확정된 시각 규칙대로 플랫 스프라이트를 정확히 그린다.

왜 이게 필요한가
----------------
이 프로젝트의 스프라이트는 "지정한 색으로 꽉 찬 정확한 기하 도형"이다. 그런데 이미지
생성 모델은 작고 어두운 도형에서 반복적으로 실패했다.

- `xp_gem`(10px, #268038): 3회 시도 모두 **속이 빈 마름모 띠**가 나왔다. 배경 대비
  2.26:1, 충전율 27%로 규칙 미달.
- `orbital`(14px, #477A8C): 3회 시도 모두 **링**이 나왔다. 2.51:1 / 충전율 32%.

같은 프롬프트 레시피로 나머지 6종은 통과했으므로 프롬프트 문제가 아니라, 작고 어두운
단색 도형이라는 조건 자체가 생성 모델에 불리한 것으로 보인다.

이 스크립트로 그리면 색과 충전율이 **정의상 정확**하다. 규칙이 곧 코드다.

쓰는 법
-------
    python tools/make_flat_sprites.py                 # 전체 다시 그리기
    python tools/make_flat_sprites.py xp_gem orbital  # 지정한 것만

결과는 `assets/sprites/<이름>.png` (1024x1024, RGBA).
그린 뒤에는 반드시 검사한다:

    python tools/check_sprite_luminance.py assets/sprites
"""

from __future__ import annotations

import math
import os
import sys

try:
    from PIL import Image, ImageDraw
except ImportError:  # pragma: no cover
    sys.exit("Pillow가 필요하다:  pip install Pillow")


CANVAS = 1024
OUTPUT_DIR = os.path.join("assets", "sprites")

# 이름 -> (도형, 채움색 RGB, 테두리색 또는 None, 테두리 두께 비율)
# 색은 docs/ASSETS.md 3-0절 표와 같은 값이다.
SHAPES: dict[str, tuple[str, tuple[int, int, int], tuple[int, int, int] | None, float]] = {
    "player": ("circle", (140, 229, 255), None, 0.0),
    "enemy_boss": ("octagon", (242, 115, 242), (255, 184, 255), 0.10),
    "enemy_tank": ("hexagon", (184, 77, 242), (217, 160, 255), 0.10),
    "enemy_basic": ("square", (229, 56, 56), None, 0.0),
    "enemy_fast": ("triangle", (191, 82, 15), None, 0.0),
    "xp_gem": ("diamond", (38, 128, 56), None, 0.0),
    "projectile": ("capsule", (158, 92, 26), None, 0.0),
    "orbital": ("circle", (71, 122, 140), None, 0.0),
}


def polygon_points(shape: str, radius: float) -> list[tuple[float, float]]:
    centre = CANVAS / 2.0
    if shape == "square":
        return [
            (centre - radius, centre - radius),
            (centre + radius, centre - radius),
            (centre + radius, centre + radius),
            (centre - radius, centre + radius),
        ]
    if shape == "diamond":
        return [
            (centre, centre - radius),
            (centre + radius, centre),
            (centre, centre + radius),
            (centre - radius, centre),
        ]
    if shape == "triangle":
        half_width = radius * math.sqrt(3.0) * 0.5
        return [
            (centre, centre - radius),
            (centre + half_width, centre + radius * 0.5),
            (centre - half_width, centre + radius * 0.5),
        ]
    sides = {"hexagon": 6, "octagon": 8}.get(shape)
    if sides is None:
        raise ValueError(f"알 수 없는 도형: {shape}")
    points: list[tuple[float, float]] = []
    for index in range(sides):
        angle = -math.pi / 2.0 + 2.0 * math.pi * index / sides
        points.append((centre + math.cos(angle) * radius, centre + math.sin(angle) * radius))
    return points


def draw_sprite(name: str) -> str:
    shape, fill, rim, rim_ratio = SHAPES[name]
    image = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    centre = CANVAS / 2.0
    radius = centre * 0.98  # 캔버스를 거의 꽉 채운다

    if shape == "circle":
        if rim is not None:
            draw.ellipse(
                [centre - radius, centre - radius, centre + radius, centre + radius],
                fill=rim + (255,),
            )
            radius *= 1.0 - rim_ratio
        draw.ellipse(
            [centre - radius, centre - radius, centre + radius, centre + radius],
            fill=fill + (255,),
        )
    elif shape == "capsule":
        half_height = radius * 0.45
        left, right = centre - radius, centre + radius
        draw.rounded_rectangle(
            [left, centre - half_height, right, centre + half_height],
            radius=half_height,
            fill=fill + (255,),
        )
    else:
        if rim is not None:
            draw.polygon(polygon_points(shape, radius), fill=rim + (255,))
            radius *= 1.0 - rim_ratio
        draw.polygon(polygon_points(shape, radius), fill=fill + (255,))

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    path = os.path.join(OUTPUT_DIR, name + ".png")
    image.save(path)
    return path


def main() -> int:
    names = sys.argv[1:] or list(SHAPES)
    unknown = [n for n in names if n not in SHAPES]
    if unknown:
        print(f"알 수 없는 이름: {', '.join(unknown)}", file=sys.stderr)
        print(f"쓸 수 있는 이름: {', '.join(SHAPES)}", file=sys.stderr)
        return 2
    for name in names:
        print("그림:", draw_sprite(name))
    print()
    print("검사:  python tools/check_sprite_luminance.py assets/sprites")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
