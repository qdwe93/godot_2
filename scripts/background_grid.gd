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
const TILE_SIZE: float = 512.0

## 바닥색의 유일한 원본은 타일 PNG다. `tools/check_sprite_luminance.py` 도 그 PNG에서
## 실제 톤을 직접 읽으므로 손으로 옮겨 적은 색이 서로 어긋날 자리가 없다.


static func read_tile_mean_colour() -> Color:
	var tile_texture: Texture2D = load("res://assets/sprites/ground_tile.png") as Texture2D
	if tile_texture == null:
		push_error("바닥 타일 텍스처를 읽을 수 없다.")
		return Color.BLACK
	var tile_image: Image = tile_texture.get_image()
	if tile_image == null or tile_image.is_empty():
		push_error("바닥 타일 이미지를 읽을 수 없다.")
		return Color.BLACK
	var red_sum: float = 0.0
	var green_sum: float = 0.0
	var blue_sum: float = 0.0
	var alpha_sum: float = 0.0
	var sample_count: int = 0
	for y in range(0, tile_image.get_height(), 4):
		for x in range(0, tile_image.get_width(), 4):
			var pixel: Color = tile_image.get_pixel(x, y)
			red_sum += pixel.r
			green_sum += pixel.g
			blue_sum += pixel.b
			alpha_sum += pixel.a
			sample_count += 1
	if sample_count == 0:
		push_error("바닥 타일에서 평균색을 계산할 픽셀이 없다.")
		return Color.BLACK
	return Color(
		red_sum / sample_count,
		green_sum / sample_count,
		blue_sum / sample_count,
		alpha_sum / sample_count
	)


func _ready() -> void:
	# 배경보다는 위, 나머지 전부보다는 아래.
	z_index = -100
	z_as_relative = false
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_follow_view()
	# 언더레이는 타일이 뷰포트를 못 덮을 때만 보인다. 평균색을 맞추는 것이 그 실패를
	# 검은 번쩍임 대신 보이지 않게 만드는 가장 싼 방법이다.
	var underlay := get_node_or_null("../BackgroundLayer/Background") as ColorRect
	if underlay != null:
		underlay.color = read_tile_mean_colour()


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
