"""밝은 타일의 양끝 톤에서 스프라이트 실루엣과 본체 색을 검사한다.

왜 필요한가
-----------
M22의 바닥은 여러 톤을 가진 밝은 포장 타일이다. 평균 바닥색 하나만 기준으로 삼으면
가장 어둡거나 밝은 포석 위에서 사라지는 스프라이트가 잘못 통과한다. 그래서 완성된
타일의 2·98백분위 톤을 직접 읽고, 축소된 외곽선과 본체를 서로 다른 기준으로 잰다.

원본 크기로 눈으로 보는 것만으로는 실제 표시 크기의 외곽선과 색 분리를 알 수 없다.
반드시 게임에 그려지는 크기로 줄인 뒤 재야 한다.

쓰는 법
-------
    python tools/check_sprite_luminance.py <이미지 파일 또는 폴더> [...]
    python tools/check_sprite_luminance.py --tile 다른_타일.png assets/sprites
    python tools/check_sprite_luminance.py --name enemy_tank C:/some/generated.png

파일명(확장자 제외)이 아래 SPEC의 키와 일치해야 한다. 일치하지 않으면 --name으로
지정한다. 종료 코드: 전부 통과 0, 하나라도 실패 1, 사용법이나 타일 오류 2.

규칙의 출처는 docs/ASSETS.md 3-0절이며, 게임 안에서는
tests/test_visual_hierarchy.gd가 같은 계층을 검사한다.
"""

from __future__ import annotations

import argparse
import os
import sys
from dataclasses import dataclass
from itertools import combinations
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.exit("Pillow가 필요하다:  pip install Pillow")

try:
    from make_ground_tile import extract_tones
except ImportError:  # 모듈로 불러올 때도 같은 구현을 쓰기 위한 경로다.
    from tools.make_ground_tile import extract_tones


EDGE_MIN_CONTRAST = 3.0
BODY_MIN_DELTA_E = 25.0
ENEMY_MIN_DELTA_E = 20.0

# 이름 -> (게임 내 표시 크기 px, 목표 색)
SPEC: dict[str, tuple[int, tuple[float, float, float]]] = {
    "player": (72, (0.55, 0.90, 1.00)),
    "enemy_boss": (180, (0.95, 0.45, 0.95)),
    "enemy_tank": (84, (0.72, 0.30, 0.95)),
    "enemy_basic": (60, (0.90, 0.22, 0.22)),
    "enemy_fast": (51, (0.75, 0.32, 0.06)),
}

# xp_gem·projectile·orbital 장면은 PNG가 아니라 ColorRect를 그리므로 그 색은
# 이 도구가 아니라 tests/test_visual_hierarchy.gd에서 검사한다.

# 외곽선이 평균색을 정당하게 어둡게 만들므로 이 범위는 실패가 아니라 경고에만 쓴다.
RATIO_MIN = 0.70
RATIO_MAX = 1.40

# 휘도만 재면 "작지만 밝은" 스프라이트가 통과하므로 실제로 칠해지는 면적도 지킨다.
MIN_COVERAGE = 0.35

DEFAULT_TILE = Path(__file__).resolve().parent.parent / "assets" / "sprites" / "ground_tile.png"


@dataclass
class Measurement:
    image: Image.Image
    coverage: float
    mean_colour: tuple[float, float, float]
    body_colour: tuple[float, float, float]
    edge_mask: list[bool]
    body_mask: list[bool]


@dataclass
class Result:
    key: str
    size: int
    coverage: float
    dark_contrast: float
    bright_contrast: float
    dark_delta_e: float
    bright_delta_e: float
    ratio: float
    body_colour: tuple[float, float, float] | None
    ok: bool
    reason: str


def _srgb_to_linear(channel: float) -> float:
    if channel <= 0.04045:
        return channel / 12.92
    return ((channel + 0.055) / 1.055) ** 2.4


def relative_luminance(colour: tuple[float, float, float]) -> float:
    red, green, blue = (_srgb_to_linear(channel) for channel in colour)
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue


def contrast_ratio(first: float, second: float) -> float:
    brighter, darker = max(first, second), min(first, second)
    return (brighter + 0.05) / (darker + 0.05)


def rgb_to_lab(colour: tuple[float, float, float]) -> tuple[float, float, float]:
    """sRGB를 D65 기준 CIE Lab으로 바꿔 색 사이의 지각 거리를 잴 수 있게 한다."""
    red, green, blue = (_srgb_to_linear(channel) for channel in colour)
    x = (0.4124564 * red + 0.3575761 * green + 0.1804375 * blue) / 0.95047
    y = 0.2126729 * red + 0.7151522 * green + 0.0721750 * blue
    z = (0.0193339 * red + 0.1191920 * green + 0.9503041 * blue) / 1.08883
    delta = 6.0 / 29.0

    def curve(value: float) -> float:
        if value > delta ** 3:
            return value ** (1.0 / 3.0)
        return value / (3.0 * delta ** 2) + 4.0 / 29.0

    fx, fy, fz = curve(x), curve(y), curve(z)
    return 116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz)


def delta_e(first: tuple[float, float, float], second: tuple[float, float, float]) -> float:
    first_lab = rgb_to_lab(first)
    second_lab = rgb_to_lab(second)
    return sum((a - b) ** 2 for a, b in zip(first_lab, second_lab)) ** 0.5


def _erode(solid: list[bool], size: int) -> list[bool]:
    # 캔버스 밖은 투명하다고 보아 가장자리 픽셀도 실제 외곽 띠에 남긴다.
    eroded = [False] * len(solid)
    for y in range(1, size - 1):
        for x in range(1, size - 1):
            index = y * size + x
            if solid[index] and all(
                solid[(y + dy) * size + x + dx]
                for dy in (-1, 0, 1)
                for dx in (-1, 0, 1)
            ):
                eroded[index] = True
    return eroded


def _foreground_mean(image: Image.Image, mask: list[bool]) -> tuple[float, float, float]:
    totals = [0.0, 0.0, 0.0]
    weight_sum = 0.0
    for selected, (red, green, blue, alpha) in zip(mask, image.getdata()):
        if not selected:
            continue
        weight = alpha / 255.0
        totals[0] += red / 255.0 * weight
        totals[1] += green / 255.0 * weight
        totals[2] += blue / 255.0 * weight
        weight_sum += weight
    return tuple(total / weight_sum for total in totals)


def _composite_mean(
    image: Image.Image,
    mask: list[bool],
    background: tuple[float, float, float],
) -> tuple[float, float, float]:
    totals = [0.0, 0.0, 0.0]
    count = 0
    for selected, (red, green, blue, alpha) in zip(mask, image.getdata()):
        if not selected:
            continue
        foreground = (red / 255.0, green / 255.0, blue / 255.0)
        weight = alpha / 255.0
        for index in range(3):
            totals[index] += foreground[index] * weight + background[index] * (1.0 - weight)
        count += 1
    return tuple(total / count for total in totals)


def measure(path: str, size: int) -> Measurement | None:
    """표시 크기에서 외곽 띠와 한 픽셀 안쪽 본체를 나눠 잰다.

    침식으로 본체가 사라지는 아주 작은 도형은 고형 영역 전체를 두 역할에 함께 쓴다.
    본체 고유색은 타일에 따라 적 종류 판정이 바뀌지 않도록 알파 가중 원색으로 남긴다.
    """
    with Image.open(path) as opened:
        image = opened.convert("RGBA").resize((size, size), Image.Resampling.LANCZOS)
    pixels = list(image.getdata())
    solid = [alpha >= 128 for _red, _green, _blue, alpha in pixels]
    solid_count = sum(solid)
    if solid_count == 0:
        return None

    eroded = _erode(solid, size)
    body_mask = eroded if any(eroded) else solid
    edge_mask = [inside and not inner for inside, inner in zip(solid, eroded)]
    if not any(edge_mask):
        edge_mask = solid

    visible = [alpha >= 20 for _red, _green, _blue, alpha in pixels]
    mean_colour = _foreground_mean(image, visible)
    body_colour = _foreground_mean(image, body_mask)
    return Measurement(
        image=image,
        coverage=solid_count / float(size * size),
        mean_colour=mean_colour,
        body_colour=body_colour,
        edge_mask=edge_mask,
        body_mask=body_mask,
    )


def collect_targets(paths: list[str]) -> list[str]:
    files: list[str] = []
    for path in paths:
        if os.path.isdir(path):
            for entry in sorted(os.listdir(path)):
                if entry.lower().endswith(".png"):
                    files.append(os.path.join(path, entry))
        else:
            files.append(path)
    return files


def _hex(colour: tuple[float, float, float]) -> str:
    return "#%02X%02X%02X" % tuple(round(channel * 255.0) for channel in colour)


def _judge(
    key: str,
    path: str,
    dark_tone: tuple[float, float, float],
    bright_tone: tuple[float, float, float],
) -> Result:
    size, target_colour = SPEC[key]
    try:
        measured = measure(path, size)
    except OSError as error:
        return Result(key, size, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, None, False, f"파일을 열 수 없다: {error}")
    if measured is None:
        return Result(key, size, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, None, False, "전부 투명하다")

    dark_edge = _composite_mean(measured.image, measured.edge_mask, dark_tone)
    bright_edge = _composite_mean(measured.image, measured.edge_mask, bright_tone)
    dark_body = _composite_mean(measured.image, measured.body_mask, dark_tone)
    bright_body = _composite_mean(measured.image, measured.body_mask, bright_tone)
    dark_contrast = contrast_ratio(relative_luminance(dark_edge), relative_luminance(dark_tone))
    bright_contrast = contrast_ratio(relative_luminance(bright_edge), relative_luminance(bright_tone))
    dark_delta_e = delta_e(dark_body, dark_tone)
    bright_delta_e = delta_e(bright_body, bright_tone)
    target_luminance = relative_luminance(target_colour)
    ratio = relative_luminance(measured.mean_colour) / target_luminance if target_luminance > 0.0 else 0.0

    reasons: list[str] = []
    if dark_contrast < EDGE_MIN_CONTRAST:
        reasons.append(f"어두운 톤 외곽 {dark_contrast:.2f}:1 < {EDGE_MIN_CONTRAST:.1f}:1")
    if bright_contrast < EDGE_MIN_CONTRAST:
        reasons.append(f"밝은 톤 외곽 {bright_contrast:.2f}:1 < {EDGE_MIN_CONTRAST:.1f}:1")
    if dark_delta_e < BODY_MIN_DELTA_E:
        reasons.append(f"어두운 톤 본체 dE {dark_delta_e:.1f} < {BODY_MIN_DELTA_E:.1f}")
    if bright_delta_e < BODY_MIN_DELTA_E:
        reasons.append(f"밝은 톤 본체 dE {bright_delta_e:.1f} < {BODY_MIN_DELTA_E:.1f}")
    if measured.coverage < MIN_COVERAGE:
        reasons.append(f"충전율 {measured.coverage:.0%} < {MIN_COVERAGE:.0%} — 슬롯 안에서 너무 작다")

    return Result(
        key=key,
        size=size,
        coverage=measured.coverage,
        dark_contrast=dark_contrast,
        bright_contrast=bright_contrast,
        dark_delta_e=dark_delta_e,
        bright_delta_e=bright_delta_e,
        ratio=ratio,
        body_colour=measured.body_colour,
        ok=not reasons,
        reason=", ".join(reasons),
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="밝은 타일용 스프라이트 실루엣 검사")
    parser.add_argument("paths", nargs="+", help="PNG 파일 또는 폴더")
    parser.add_argument("--name", help="파일명 대신 쓸 스펙 키 (파일 하나일 때만)")
    parser.add_argument("--tile", default=str(DEFAULT_TILE), help="판정에 쓸 완성 바닥 타일")
    args = parser.parse_args()

    if not os.path.isfile(args.tile):
        print(f"바닥 타일이 없다: {args.tile}", file=sys.stderr)
        print("실제 타일 없이 고정색으로 판정하지 않는다.", file=sys.stderr)
        return 2
    try:
        with Image.open(args.tile) as tile_image:
            dark_tone, bright_tone = extract_tones(tile_image)
    except (OSError, ValueError) as error:
        print(f"바닥 타일의 톤을 읽을 수 없다: {args.tile} — {error}", file=sys.stderr)
        return 2

    files = collect_targets(args.paths)
    if args.name and len(files) != 1:
        print("--name은 파일 하나에만 쓸 수 있다.", file=sys.stderr)
        return 2

    results: list[Result] = []
    for path in files:
        key = args.name or os.path.splitext(os.path.basename(path))[0]
        if key not in SPEC:
            print(f"건너뜀 (스펙에 없는 이름): {path}", file=sys.stderr)
            continue
        results.append(_judge(key, path, dark_tone, bright_tone))

    if not results:
        print("검사할 파일이 없다.", file=sys.stderr)
        return 2

    print(f"어두운 타일 톤: {_hex(dark_tone)} · 상대 휘도 {relative_luminance(dark_tone):.4f}")
    print(f"밝은 타일 톤:   {_hex(bright_tone)} · 상대 휘도 {relative_luminance(bright_tone):.4f}")
    print()
    print(
        f"{'에셋':<13} {'크기':>6} {'충전율':>8} {'어두운톤 대비':>13} {'밝은톤 대비':>12} "
        f"{'어두운톤 dE':>12} {'밝은톤 dE':>11}  판정"
    )
    print("-" * 114)
    for result in results:
        verdict = "통과" if result.ok else f"실패 — {result.reason}"
        print(
            f"{result.key:<13} {result.size:>5}px {result.coverage:>7.1%} "
            f"{result.dark_contrast:>12.2f}:1 {result.bright_contrast:>11.2f}:1 "
            f"{result.dark_delta_e:>12.1f} {result.bright_delta_e:>11.1f}  {verdict}"
        )

    warnings: list[str] = []
    for result in results:
        if result.body_colour is None:
            continue
        if result.ratio < RATIO_MIN:
            warnings.append(f"{result.key}: 목표 휘도의 {result.ratio:.2f}배 — 외곽선 포함 평균이 낮다")
        elif result.ratio > RATIO_MAX:
            warnings.append(f"{result.key}: 목표 휘도의 {result.ratio:.2f}배 — 외곽선 포함 평균이 높다")
    if warnings:
        print()
        print("목표색 휘도 경고 (판정에는 영향 없음)")
        for warning in warnings:
            print(f"  경고: {warning}")

    # #A9A3C4에서는 측정 대비가 boss 1.00 < tank 1.29 < basic 1.51 < fast 1.58로
    # 거의 뒤집힌다. 대비는 밝기만 추적하고 바닥이 각 요소보다 어두울 때의 순서라서,
    # 바닥 휘도가 요소를 지나면 그 요소의 대비가 다시 커진다. 균일한 어두운 외곽선은
    # 모두를 같은 방향으로 옮겨 이 순서를 고칠 수 없다. 순위별로 검정을 더하면 가장
    # 밝은 플레이어를 검정 속에 묻게 되어, 기존 그림을 보존하려는 접근 자체가 깨진다.
    enemy_by_name = {
        result.key: result
        for result in results
        if result.key in {"enemy_basic", "enemy_fast", "enemy_tank", "enemy_boss"}
        and result.body_colour is not None
    }
    enemy_results = list(enemy_by_name.values())
    enemies_ok = True
    if len(enemy_results) >= 2:
        print()
        print("적 변형 간 본체 색 구분")
        for first, second in combinations(enemy_results, 2):
            distance = delta_e(first.body_colour, second.body_colour)
            pair_ok = distance >= ENEMY_MIN_DELTA_E
            enemies_ok = enemies_ok and pair_ok
            verdict = "통과" if pair_ok else f"실패 (< {ENEMY_MIN_DELTA_E:.1f})"
            print(f"  {first.key} / {second.key}: dE {distance:.1f} — {verdict}")

    failed = [result for result in results if not result.ok]
    print()
    if failed or not enemies_ok:
        if failed:
            print(f"개별 판정 실패 {len(failed)}건.")
        if not enemies_ok:
            print("적 변형끼리 본체 색이 충분히 구분되지 않는다.")
        return 1
    print("전부 통과.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
