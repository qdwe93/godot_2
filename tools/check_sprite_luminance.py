"""스프라이트가 확정된 시각 위계 규칙을 지키는지 검사한다.

왜 필요한가
-----------
이미지 생성기는 1024px 캔버스에서 보기 좋은 그림을 만든다. 그런데 이 게임은 그걸
17~60px로 줄여서 거의 검정인 배경(#141419) 위에 그린다. 어두운 회색 디테일과 검은
외곽선은 원본에서는 멋있지만, 축소하면 평균 색을 검정 쪽으로 끌어내려 **밝기 위계를
통째로 무너뜨린다.**

실제로 1차 생성물 4장 중 3장이 이 검사에서 걸렸다. 탱커는 배경 대비 1.73:1까지
떨어져서, 우리가 방금 고친 "안 보이는 보스"(1.05:1)와 비슷한 수준이었다.

원본 크기로 눈으로 보는 것만으로는 절대 못 잡는다. 반드시 축소해서 재야 한다.

쓰는 법
-------
    python tools/check_sprite_luminance.py <이미지 파일 또는 폴더> [...]

파일명(확장자 제외)이 아래 SPEC의 키와 일치해야 한다. 일치하지 않으면 --name 으로
지정한다:

    python tools/check_sprite_luminance.py --name enemy_tank C:/some/generated.png

다른 서비스에서 생성한 이미지도 같은 기준으로 검사할 수 있다.
종료 코드: 전부 통과 0, 하나라도 실패 1.

규칙의 출처는 docs/ASSETS.md 3-0절이며, 게임 안에서는
tests/test_visual_hierarchy.gd 가 같은 규칙을 검사한다.
"""

from __future__ import annotations

import argparse
import os
import sys

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    sys.exit("Pillow가 필요하다:  pip install Pillow")


BACKGROUND = (0.08, 0.08, 0.10)  # main.tscn 의 Background ColorRect
MIN_CONTRAST = 3.0  # 비텍스트 요소의 WCAG 최소 권장

# 이름 -> (게임 내 표시 크기 px, 목표 색, 밝기 순위)
# 순위 1이 가장 밝다. docs/ASSETS.md 3-0절 표와 같은 값이다.
SPEC: dict[str, tuple[int, tuple[float, float, float], int]] = {
    "player": (24, (0.55, 0.90, 1.00), 1),
    "enemy_boss": (60, (0.95, 0.45, 0.95), 2),
    "enemy_tank": (28, (0.72, 0.30, 0.95), 3),
    "enemy_basic": (20, (0.90, 0.22, 0.22), 4),
    "enemy_fast": (17, (0.75, 0.32, 0.06), 5),
    "xp_gem": (10, (0.15, 0.50, 0.22), 6),
    "projectile": (8, (0.62, 0.36, 0.10), 7),
    "orbital": (14, (0.28, 0.48, 0.55), 0),  # 장비. 순위 검사에서는 제외
}

# 축소 후 휘도가 목표의 몇 배까지 허용되는가.
# 아래로 벗어나면 어두운 디테일이 먹은 것이고, 위로 벗어나면 규칙보다 밝아
# 위계를 침범한다.
RATIO_MIN = 0.70
RATIO_MAX = 1.40

# 축소 후 실제로 칠해지는 면적 비율의 하한.
# 휘도만 재면 "작지만 밝은" 스프라이트가 통과해 버린다. 실제로 orbital이 14px 슬롯
# 안에서 5px짜리 점으로 그려지면서도 대비 3.79:1로 통과했다.
# 참고로 코드로 그리는 도형의 충전율은 사각형 1.00 / 육각형 0.83 / 원 0.78 /
# 삼각형·마름모 0.50 근처다.
MIN_COVERAGE = 0.35


def _srgb_to_linear(channel: float) -> float:
    if channel <= 0.04045:
        return channel / 12.92
    return ((channel + 0.055) / 1.055) ** 2.4


def relative_luminance(colour: tuple[float, float, float]) -> float:
    red, green, blue = (_srgb_to_linear(c) for c in colour)
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue


def contrast_ratio(luminance: float, other: float) -> float:
    brighter, darker = max(luminance, other), min(luminance, other)
    return (brighter + 0.05) / (darker + 0.05)


def measure(path: str, size: int) -> tuple[tuple[float, float, float], float] | None:
    """게임에 그려지는 크기로 줄인 뒤 (알파 가중 평균색, 면적 충전율)을 구한다.

    충전율은 알파 128 이상인 픽셀이 전체 슬롯에서 차지하는 비율이다.
    평균색만으로는 스프라이트가 실제로 얼마나 큰지 알 수 없다.
    """
    image = Image.open(path).convert("RGBA").resize((size, size), Image.LANCZOS)
    pixels = image.load()
    totals = [0.0, 0.0, 0.0]
    weight_sum = 0.0
    solid_pixels = 0
    for y in range(size):
        for x in range(size):
            red, green, blue, alpha = pixels[x, y]
            if alpha >= 128:
                solid_pixels += 1
            if alpha < 20:  # 사실상 투명한 픽셀은 화면에 기여하지 않는다
                continue
            weight = alpha / 255.0
            totals[0] += red / 255.0 * weight
            totals[1] += green / 255.0 * weight
            totals[2] += blue / 255.0 * weight
            weight_sum += weight
    if weight_sum <= 0.0:
        return None
    mean = (totals[0] / weight_sum, totals[1] / weight_sum, totals[2] / weight_sum)
    return mean, solid_pixels / float(size * size)


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


def main() -> int:
    parser = argparse.ArgumentParser(description="스프라이트 밝기 위계 검사")
    parser.add_argument("paths", nargs="+", help="PNG 파일 또는 폴더")
    parser.add_argument("--name", help="파일명 대신 쓸 스펙 키 (파일 하나일 때만)")
    args = parser.parse_args()

    files = collect_targets(args.paths)
    if args.name and len(files) != 1:
        print("--name 은 파일 하나에만 쓸 수 있다.", file=sys.stderr)
        return 2

    background_luminance = relative_luminance(BACKGROUND)
    results: list[tuple[str, int, float, float, float, bool, str]] = []

    for path in files:
        key = args.name or os.path.splitext(os.path.basename(path))[0]
        if key not in SPEC:
            print(f"건너뜀 (스펙에 없는 이름): {path}", file=sys.stderr)
            continue
        size, target_colour, rank = SPEC[key]
        measured_pair = measure(path, size)
        if measured_pair is None:
            results.append((key, size, 0.0, 0.0, 0.0, False, "전부 투명하다"))
            continue
        mean, coverage = measured_pair
        measured = relative_luminance(mean)
        target = relative_luminance(target_colour)
        ratio = measured / target if target > 0 else 0.0
        contrast = contrast_ratio(measured, background_luminance)

        reasons: list[str] = []
        if contrast < MIN_CONTRAST:
            reasons.append(f"배경 대비 {contrast:.2f}:1 < {MIN_CONTRAST}:1")
        if ratio < RATIO_MIN:
            reasons.append(f"목표의 {ratio:.2f}배 — 어두운 디테일이 먹었다")
        elif ratio > RATIO_MAX:
            reasons.append(f"목표의 {ratio:.2f}배 — 위계를 침범한다")
        if coverage < MIN_COVERAGE:
            reasons.append(f"충전율 {coverage:.0%} < {MIN_COVERAGE:.0%} — 슬롯 안에서 너무 작게 그려진다")
        results.append((key, size, measured, target, contrast, not reasons, ", ".join(reasons)))

    if not results:
        print("검사할 파일이 없다.", file=sys.stderr)
        return 2

    print(f"{'에셋':<13}{'크기':>6}{'측정휘도':>10}{'목표휘도':>10}{'대비':>9}  판정")
    print("-" * 74)
    for key, size, measured, target, contrast, ok, reason in results:
        verdict = "통과" if ok else f"실패 — {reason}"
        print(f"{key:<13}{size:>5}px{measured:>10.4f}{target:>10.4f}{contrast:>8.2f}:1  {verdict}")

    # 순위 검사는 순위가 매겨진 에셋이 2개 이상 모였을 때만 의미가 있다
    ranked = sorted(
        ((SPEC[k][2], k, m) for k, _s, m, _t, _c, _o, _r in results if SPEC[k][2] > 0),
    )
    order_ok = True
    if len(ranked) >= 2:
        print()
        print("밝기 순서 (규칙: 플레이어 > 보스 > 탱커 > 기본 > 빠른 > 젬 > 투사체)")
        for index in range(len(ranked) - 1):
            _, name_a, lum_a = ranked[index]
            _, name_b, lum_b = ranked[index + 1]
            if lum_a <= lum_b:
                order_ok = False
                print(f"  위반: {name_a}({lum_a:.4f}) <= {name_b}({lum_b:.4f})")
        if order_ok:
            print("  이 묶음 안에서는 순서 위반 없음")
        print("  (전체 순서 검증은 8종을 모두 넣고 돌려야 한다)")

    failed = [r for r in results if not r[5]]
    print()
    if failed or not order_ok:
        if failed:
            print(f"개별 판정 실패 {len(failed)}건.")
        if not order_ok:
            print("개별 판정은 통과했지만 밝기 순서가 깨졌다. 순서를 어긴 쪽을 다시 뽑아야 한다.")
        print("실패한 파일만 표적 재생성한다 (docs/ASSETS.md 4-1절).")
        return 1
    print("전부 통과.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
