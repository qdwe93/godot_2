#!/usr/bin/env python3
"""밝은 회보라 광장 타일을 만들고 실제로 그려진 톤을 기록한다.

왜 필요한가
-----------
M22의 바닥은 어두운 격자가 아니라 레퍼런스 게임처럼 밝은 포장 광장이다. 여기서는
명도 차를 크게 벌리는 대신 채도와 무늬로 면을 나눈다. 그래야 외곽선을 입힌 기존
스프라이트의 색을 보존하면서도 바닥이 단조롭게 보이지 않는다.

검사 기준
---------
그림에 쓰는 모든 색은 WCAG 상대 휘도 0.28~0.58 안에 있어야 한다. 타일을 만든 뒤에는
픽셀의 2·98백분위 톤을 다시 재서 검사기가 실제 바닥의 양끝을 그대로 쓰게 한다.

    python tools/make_ground_tile.py
"""

from __future__ import annotations

from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:
    raise SystemExit("Pillow가 필요하다:  pip install Pillow")


TILE = 512
PAVER = 128
JOINT_WIDTH = 4
BOUNDARY_WIDTH = 8
HATCH_WIDTH = 3
HATCH_SPACING = 16
DIAMOND_SIZE = 10

BASE = (169, 163, 196, 255)       # 바닥 바탕 #A9A3C4
JOINT = (182, 176, 208, 255)      # 포석 줄눈 #B6B0D0
BOUNDARY = (192, 176, 228, 255)   # 큰 필드 경계 #C0B0E4
# 레퍼런스의 경계선은 **흰색**이지만 흰색은 쓸 수 없다. 휘도 1.0 은 명도 대역을
# 통째로 벌려 놓고, 무엇보다 주인공 본체(#74A1B1)와 CIE76 dE 가 23 까지 좁혀져
# 밝은 톤 위에서 주인공이 흐려진다. 밝기 대신 **채도**로 경계를 낸 이유다
# (dE 23.5 -> 31.1). 계획의 '화려함은 채도와 무늬로 낸다'가 이 자리다.
ACCENT = (167, 155, 210, 255)     # 채도를 올린 강조 포석 #A79BD2
DIAMOND = (154, 148, 180, 255)    # 큰 교차점 표식 #9A94B4

COLOURS = {
    "바탕": BASE,
    "줄눈": JOINT,
    "경계선": BOUNDARY,
    "강조 포석": ACCENT,
    "교차점 마름모": DIAMOND,
}

OUTPUT = Path(__file__).resolve().parent.parent / "assets" / "sprites" / "ground_tile.png"


def _srgb_to_linear(channel: float) -> float:
    if channel <= 0.04045:
        return channel / 12.92
    return ((channel + 0.055) / 1.055) ** 2.4


def relative_luminance(colour: tuple[float, float, float]) -> float:
    red, green, blue = (_srgb_to_linear(channel) for channel in colour)
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue


def _rgb_float(colour: tuple[int, int, int, int]) -> tuple[float, float, float]:
    return tuple(channel / 255.0 for channel in colour[:3])


def _hex(colour: tuple[float, float, float]) -> str:
    return "#%02X%02X%02X" % tuple(round(channel * 255.0) for channel in colour)


def _percentile(sorted_values: list[float], fraction: float) -> float:
    # 보간값을 새 톤으로 만들지 않고 실제 픽셀 경계를 고르면 검사 결과를 다시 추적하기 쉽다.
    index = round((len(sorted_values) - 1) * fraction)
    return sorted_values[index]


def extract_tones(image: Image.Image) -> tuple[tuple[float, float, float], tuple[float, float, float]]:
    """2·98백분위 바깥 픽셀의 평균색을 어두운 톤과 밝은 톤으로 돌려준다.

    단 한 픽셀의 장식이나 압축 잡음이 바닥 기준을 독점하지 않게 양끝 2%를 묶는다.
    반환값은 검사기가 바로 합성에 쓸 수 있도록 0..1 범위의 RGB 세 쌍이다.
    """
    rgb_image = image.convert("RGB")
    samples: list[tuple[float, float, float, float]] = []
    for red, green, blue in rgb_image.getdata():
        colour = (red / 255.0, green / 255.0, blue / 255.0)
        samples.append((relative_luminance(colour), *colour))
    if not samples:
        raise ValueError("톤을 잴 픽셀이 없다.")

    luminances = sorted(sample[0] for sample in samples)
    dark_limit = _percentile(luminances, 0.02)
    bright_limit = _percentile(luminances, 0.98)
    dark_pixels = [sample[1:] for sample in samples if sample[0] <= dark_limit]
    bright_pixels = [sample[1:] for sample in samples if sample[0] >= bright_limit]

    def mean(pixels: list[tuple[float, float, float]]) -> tuple[float, float, float]:
        return tuple(sum(pixel[index] for pixel in pixels) / len(pixels) for index in range(3))

    return mean(dark_pixels), mean(bright_pixels)


def _validate_colours() -> None:
    # 그림을 보기 좋게 다듬다가 명도 대역을 몰래 깨뜨리지 못하도록 저장 전에 막는다.
    for name, rgba in COLOURS.items():
        luminance = relative_luminance(_rgb_float(rgba))
        if luminance < 0.28 or luminance > 0.58:
            raise SystemExit(
                f"명도 대역 위반: {name} {_hex(_rgb_float(rgba))}의 상대 휘도 "
                f"{luminance:.4f}가 0.28~0.58 밖이다."
            )


def _draw_hatched_paver(image: Image.Image, column: int, row: int) -> None:
    left = column * PAVER + JOINT_WIDTH // 2
    top = row * PAVER + JOINT_WIDTH // 2
    right = (column + 1) * PAVER - JOINT_WIDTH // 2 - 1
    bottom = (row + 1) * PAVER - JOINT_WIDTH // 2 - 1

    # 가장자리 포석도 무늬가 타일 밖에서 잘리지 않게 안쪽 여백에서 끝낸다.
    patch = Image.new("RGBA", (right - left + 1, bottom - top + 1), ACCENT)
    hatch = ImageDraw.Draw(patch)
    width, height = patch.size
    for offset in range(-height, width + height, HATCH_SPACING):
        hatch.line([(offset, height - 1), (offset + height, -1)], fill=BASE, width=HATCH_WIDTH)
    image.alpha_composite(patch, (left, top))


def _draw_wrapped_diamond(draw: ImageDraw.ImageDraw) -> None:
    radius = DIAMOND_SIZE // 2
    positive_edge = radius - 1
    # 교차점은 네 타일이 나눠 갖는다. 반대편 조각까지 함께 그려야 반복 경계에서 완성된다.
    for center_x in (0, TILE):
        for center_y in (0, TILE):
            draw.polygon(
                [
                    (center_x, center_y - radius),
                    (center_x + positive_edge, center_y),
                    (center_x, center_y + positive_edge),
                    (center_x - radius, center_y),
                ],
                fill=DIAMOND,
            )


def main() -> None:
    _validate_colours()
    image = Image.new("RGBA", (TILE, TILE), BASE)

    _draw_hatched_paver(image, 1, 2)
    _draw_hatched_paver(image, 3, 0)
    draw = ImageDraw.Draw(image)

    # 내부 줄눈은 밝은 바닥에서 패턴만 읽히면 되므로 명도 차를 작게 유지한다.
    half_joint = JOINT_WIDTH // 2
    for position in range(PAVER, TILE, PAVER):
        draw.rectangle(
            [position - half_joint, 0, position + half_joint - 1, TILE - 1],
            fill=JOINT,
        )
        draw.rectangle(
            [0, position - half_joint, TILE - 1, position + half_joint - 1],
            fill=JOINT,
        )

    # 왼쪽·위쪽에만 그리면 반복될 때 각 512px 경계가 정확히 한 번만 나타난다.
    draw.rectangle([0, 0, BOUNDARY_WIDTH - 1, TILE - 1], fill=BOUNDARY)
    draw.rectangle([0, 0, TILE - 1, BOUNDARY_WIDTH - 1], fill=BOUNDARY)
    _draw_wrapped_diamond(draw)

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    image.save(OUTPUT)

    with Image.open(OUTPUT) as finished:
        dark_tone, bright_tone = extract_tones(finished)
        pixels = list(finished.convert("RGB").getdata())
    mean_colour = tuple(sum(pixel[index] for pixel in pixels) / (255.0 * len(pixels)) for index in range(3))

    print(f"타일 크기: {TILE}x{TILE}")
    print(f"가장 어두운 톤: {_hex(dark_tone)} (상대 휘도 {relative_luminance(dark_tone):.4f})")
    print(f"가장 밝은 톤: {_hex(bright_tone)} (상대 휘도 {relative_luminance(bright_tone):.4f})")
    print(f"평균색: {_hex(mean_colour)}")
    print(f"저장: {OUTPUT}")


if __name__ == "__main__":
    main()
