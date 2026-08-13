#!/usr/bin/env python3
"""바닥 격자 타일 생성 — 카메라가 움직일 때 '월드가 흐른다'는 것을 보여주는 유일한 단서.

왜 필요한가
-----------
M16에서 카메라가 들어오면서 주인공은 화면 한가운데에 고정되고 세계가 흐르게 됐다.
그런데 배경이 **단색**이면 흐를 것이 아무것도 없다. 주인공이 멈춰 있는지 시속
200으로 달리는지 화면만 봐서는 구분이 안 된다. 격자는 그 차이를 보여주는 장치다.

밝기 규칙
---------
격자는 배경보다 **밝다**. 그러니 이 색이 게임에서 '가장 밝은 배경 색'이 되고,
모든 대비 계산의 최악값 기준이 된다 (docs/ASSETS.md 3절).

  배경 ColorRect  #14141A  (0.08, 0.08, 0.10)
  격자 GRID_TINT  #1E1E26  (0.118, 0.118, 0.149)

가장 어두운 게임 요소인 투사체(3.48:1 대 #14141A)조차 #1E1E26 기준으로 3.14:1 이라
WCAG 최소 권장 3:1 을 넘긴다. 이보다 더 밝게 칠하면 그 여유가 사라진다 —
계산상 한계는 약 #23232B 다.

  python tools/make_ground_tile.py
"""

from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:
    raise SystemExit("Pillow가 필요하다:  pip install Pillow")

TILE = 256
LINE_WIDTH = 4
DOT_SIZE = 10
GRID_TINT = (30, 30, 38, 255)      # #1E1E26 — scripts/background_grid.gd 의 GRID_TINT 와 같아야 한다
DOT_TINT = (30, 30, 38, 150)       # 셀 중앙 점은 조금 옅게

OUTPUT = Path(__file__).resolve().parent.parent / "assets" / "sprites" / "ground_tile.png"


def main() -> None:
    image = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    # 타일 왼쪽·위쪽 가장자리에만 선을 그린다. 이어 붙이면 TILE 간격의 격자가 된다.
    draw.rectangle([0, 0, TILE - 1, LINE_WIDTH - 1], fill=GRID_TINT)
    draw.rectangle([0, 0, LINE_WIDTH - 1, TILE - 1], fill=GRID_TINT)

    # 셀 한가운데 점 — 선만 있으면 대각선 이동이 잘 안 읽힌다.
    half = TILE // 2
    radius = DOT_SIZE // 2
    draw.rectangle([half - radius, half - radius, half + radius, half + radius], fill=DOT_TINT)

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    image.save(OUTPUT)
    print(f"wrote {OUTPUT} ({TILE}x{TILE}, grid {GRID_TINT[:3]})")


if __name__ == "__main__":
    main()
