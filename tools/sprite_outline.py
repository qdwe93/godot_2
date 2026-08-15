#!/usr/bin/env python3
"""원본의 색과 캔버스 크기를 지키면서 밝은 바닥용 외곽선을 굽는다.

왜 필요한가
-----------
M22의 밝은 바닥에서는 기존 그림의 실루엣이 바닥과 섞인다. 그림을 다시 칠하면 이미
정해진 캐릭터 색과 디테일을 잃으므로, 다시 실행할 수 있는 원본을 따로 보관하고 표시
크기에 맞춘 어두운 외곽선만 출력 PNG에 더한다.

    python tools/sprite_outline.py
    python tools/sprite_outline.py player
    python tools/sprite_outline.py --revert
"""

from __future__ import annotations

import argparse
import shutil
from pathlib import Path

try:
    from PIL import Image, ImageChops
except ImportError:
    raise SystemExit("Pillow가 필요하다:  pip install Pillow")


ROOT = Path(__file__).resolve().parent.parent
SOURCE_DIR = ROOT / "assets" / "sprites_src"
OUTPUT_DIR = ROOT / "assets" / "sprites"

DISPLAY_SIZES = {
    "player": 72,
    "enemy_boss": 180,
    "enemy_tank": 84,
    "enemy_basic": 60,
    "enemy_fast": 51,
}

# 타일의 가장 밝은 톤(약 L 0.53)에도 약 9:1이고, L 0.133까지 어느 톤에서도 3:1을 지킨다.
OUTLINE_COLOUR = (20, 20, 26, 255)


def _seed_sources() -> None:
    if SOURCE_DIR.exists():
        return
    missing = [OUTPUT_DIR / f"{name}.png" for name in DISPLAY_SIZES if not (OUTPUT_DIR / f"{name}.png").is_file()]
    if missing:
        raise SystemExit("원본 보관 실패: 렌더링 파일이 없다 — " + ", ".join(str(path) for path in missing))
    SOURCE_DIR.mkdir(parents=True)
    print("=" * 72)
    print("주의: sprites_src가 없어 현재 렌더링 PNG 5장을 원본으로 처음 보관한다.")
    print("이 메시지가 나온 뒤에는 sprites의 외곽선 결과를 원본 쪽으로 되돌려 복사하지 않는다.")
    print("=" * 72)
    for name in DISPLAY_SIZES:
        source = OUTPUT_DIR / f"{name}.png"
        shutil.copy2(source, SOURCE_DIR / source.name)


def _solid_coverage(alpha: Image.Image) -> float:
    solid = sum(1 for value in alpha.getdata() if value >= 128)
    return solid / float(alpha.width * alpha.height)


def _disc_dilate(alpha: Image.Image, radius: int) -> Image.Image:
    # 사각 최대 필터는 모서리를 부풀린다. 정확한 유클리드 거리장을 구해 원 안만 채운다.
    width, height = alpha.size
    source = list(alpha.getdata())
    infinity = width * width + height * height + radius * radius + 1
    vertical = [infinity] * (width * height)

    # 한 열에서는 가장 가까운 고형 픽셀의 세로 거리만 앞뒤로 훑으면 정확히 구해진다.
    for x in range(width):
        last: int | None = None
        for y in range(height):
            index = y * width + x
            if source[index] > 0:
                last = y
                vertical[index] = 0
            elif last is not None:
                vertical[index] = (y - last) ** 2
        last = None
        for y in range(height - 1, -1, -1):
            index = y * width + x
            if source[index] > 0:
                last = y
            elif last is not None:
                vertical[index] = min(vertical[index], (last - y) ** 2)

    def distance_row(values: list[int]) -> list[int]:
        # 포물선의 아래쪽 껍질만 남기면 가로축의 제곱 거리 변환도 한 번에 끝난다.
        count = len(values)
        sites = [0] * count
        limits = [0.0] * (count + 1)
        result = [0] * count
        level = 0
        sites[0] = 0
        limits[0] = float("-inf")
        limits[1] = float("inf")
        for position in range(1, count):
            site = sites[level]
            crossing = (
                (values[position] + position * position) - (values[site] + site * site)
            ) / (2.0 * position - 2.0 * site)
            while crossing <= limits[level]:
                level -= 1
                site = sites[level]
                crossing = (
                    (values[position] + position * position) - (values[site] + site * site)
                ) / (2.0 * position - 2.0 * site)
            level += 1
            sites[level] = position
            limits[level] = crossing
            limits[level + 1] = float("inf")
        level = 0
        for position in range(count):
            while limits[level + 1] < position:
                level += 1
            difference = position - sites[level]
            result[position] = difference * difference + values[sites[level]]
        return result

    radius_squared = radius * radius
    output = bytearray(width * height)
    for y in range(height):
        start = y * width
        distances = distance_row(vertical[start:start + width])
        output[start:start + width] = bytes(255 if value <= radius_squared else 0 for value in distances)
    return Image.frombytes("L", (width, height), bytes(output))


def _prepare_source(source: Image.Image, thickness: int) -> Image.Image:
    width, height = source.size
    alpha_box = source.getchannel("A").getbbox()
    if alpha_box is None:
        raise ValueError("알파가 전부 투명하다.")

    crop = source.crop(alpha_box)
    available_width = width - 2 * thickness
    available_height = height - 2 * thickness
    if available_width <= 0 or available_height <= 0:
        raise ValueError("외곽선이 캔버스보다 두꺼워 원본을 넣을 자리가 없다.")

    scale = min(available_width / crop.width, available_height / crop.height)
    resized_size = (
        max(1, round(crop.width * scale)),
        max(1, round(crop.height * scale)),
    )
    resized = crop.resize(resized_size, Image.Resampling.LANCZOS)
    prepared = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    position = ((width - resized.width) // 2, (height - resized.height) // 2)
    prepared.alpha_composite(resized, position)
    return prepared


def bake(name: str) -> None:
    source_path = SOURCE_DIR / f"{name}.png"
    output_path = OUTPUT_DIR / f"{name}.png"
    if not source_path.is_file():
        raise SystemExit(f"원본이 없다: {source_path}")

    with Image.open(source_path) as opened:
        source = opened.convert("RGBA")
    width, height = source.size
    display_size = DISPLAY_SIZES[name]
    source_size = max(width, height)
    thickness_display = min(5.0, max(2.0, 0.05 * display_size))
    thickness = max(1, round(thickness_display * source_size / display_size))

    before = _solid_coverage(source.getchannel("A"))
    prepared = _prepare_source(source, thickness)
    alpha = prepared.getchannel("A")
    dilated = _disc_dilate(alpha, thickness)
    ring = ImageChops.subtract(dilated, alpha)

    outline = Image.new("RGBA", source.size, OUTLINE_COLOUR)
    outline.putalpha(ring)
    result = Image.alpha_composite(outline, prepared)
    after = _solid_coverage(result.getchannel("A"))

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    result.save(output_path)
    print(
        f"{name}: 원본 {width}x{height}px · 표시 {display_size}px · "
        f"표시 외곽선 t_display={thickness_display:.2f}px · 원본 외곽선 t={thickness}px · "
        f"고형 픽셀 {before:.1%} -> {after:.1%}"
    )


def revert() -> None:
    if not SOURCE_DIR.is_dir():
        raise SystemExit(f"되돌릴 원본 폴더가 없다: {SOURCE_DIR}")
    for name in DISPLAY_SIZES:
        source = SOURCE_DIR / f"{name}.png"
        if not source.is_file():
            raise SystemExit(f"되돌릴 원본이 없다: {source}")
        shutil.copy2(source, OUTPUT_DIR / source.name)
        print(f"되돌림: {name} — {source.name} 원본을 렌더링 경로에 복원했다.")


def main() -> int:
    parser = argparse.ArgumentParser(description="밝은 바닥용 스프라이트 외곽선 굽기")
    parser.add_argument("names", nargs="*", help="처리할 이름, 생략하면 렌더링 PNG 5장 전부")
    parser.add_argument("--revert", action="store_true", help="보관한 원본 5장을 렌더링 경로에 복원")
    args = parser.parse_args()

    if args.revert:
        if args.names:
            parser.error("--revert와 개별 이름은 함께 쓸 수 없다.")
        revert()
        return 0

    names = args.names or list(DISPLAY_SIZES)
    unknown = [name for name in names if name not in DISPLAY_SIZES]
    if unknown:
        parser.error("알 수 없는 이름: " + ", ".join(unknown))

    _seed_sources()
    for name in names:
        bake(name)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
