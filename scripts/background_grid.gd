class_name BackgroundGrid
extends Sprite2D

## 흐르는 바닥 격자.
##
## 왜 있는가
## ---------
## M16에서 카메라가 들어와 주인공이 화면 한가운데 고정됐다. 그런데 배경이 단색이면
## **흐를 것이 아무것도 없다** — 가만히 서 있는지 전속력으로 달리는지 화면만 봐서는
## 구분이 안 된다. 카메라를 넣는 변경은 이 격자가 있어야 비로소 의미가 생긴다.
##
## 어떻게 도는가
## -------------
## 타일 텍스처 하나를 `texture_repeat` 로 넓게 반복시키고, 스프라이트 자체를
## **타일 크기 단위로 끊어서** 화면 중앙에 따라 옮긴다. 한 타일씩 점프하므로
## 격자는 월드에 붙박여 있는 것처럼 보이고, 스프라이트는 항상 화면을 덮는다.
##
## `Parallax2D` 를 쓰지 않은 이유는 하나다 — 여기서 필요한 건 시차가 아니라
## **월드에 고정된 바닥**이고, 그건 배율 1의 특수한 경우일 뿐이라 직접 그리는 쪽이
## 동작을 확신할 수 있다.

## 타일 한 칸의 크기. tools/make_ground_tile.py 의 TILE 과 같아야 한다.
const TILE_SIZE: float = 256.0

## 격자 선의 색. tools/make_ground_tile.py 의 GRID_TINT 와 같아야 한다.
##
## **이 색이 게임에서 가장 밝은 배경 톤이다.** 즉 모든 대비 계산의 최악값 기준이며,
## `tools/check_sprite_luminance.py` 와 `tests/test_visual_hierarchy.gd` 가
## 이 값을 읽어 쓴다. 더 밝게 바꾸면 어두운 요소(투사체)가 3:1 아래로 떨어진다.
const GRID_TINT: Color = Color(0.118, 0.118, 0.149)


func _ready() -> void:
	# 배경보다는 위, 나머지 전부보다는 아래.
	z_index = -100
	z_as_relative = false
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_follow_view()


func _process(_delta: float) -> void:
	_follow_view()


func _follow_view() -> void:
	var view_center: Vector2 = Arena.get_view_center(self)
	global_position = Vector2(
		snappedf(view_center.x, TILE_SIZE),
		snappedf(view_center.y, TILE_SIZE)
	)


## 테스트 이음매 — 스냅된 위치를 계산만 해서 돌려준다.
func get_snapped_position_for(view_center: Vector2) -> Vector2:
	return Vector2(snappedf(view_center.x, TILE_SIZE), snappedf(view_center.y, TILE_SIZE))
