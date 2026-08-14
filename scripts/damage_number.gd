extends Label

# 짧은 수명 안에 타격 지점에서 분리돼 보이면서도 전투 화면을 오래 가리지 않게 한다.
const RISE_DISTANCE: float = 52.0
const LIFETIME: float = 0.7
const FADE_START: float = 0.35
# 같은 프레임에 들어간 산탄 피해가 완전히 포개져 읽히지 않는 일을 줄인다.
const JITTER_X: float = 16.0
# 세 자리 이상의 피해도 타격 지점을 중심으로 정렬할 여유를 둔다.
const BOX_SIZE: Vector2 = Vector2(140.0, 40.0)

var _origin: Vector2 = Vector2.ZERO
var _elapsed: float = 0.0


func configure(at_position: Vector2, amount: float) -> void:
	# 실제 피해가 1보다 작아도 0으로 표시되면 빗나간 것으로 오해하기 쉽다.
	text = str(maxi(1, roundi(amount)))
	_origin = at_position + Vector2(randf_range(-JITTER_X, JITTER_X), 0.0)


func _ready() -> void:
	size = BOX_SIZE
	add_to_group(&"damage_numbers")
	z_index = 50
	position = _origin - BOX_SIZE * 0.5


func _process(delta: float) -> void:
	_elapsed += delta
	var t: float = _elapsed / LIFETIME
	position.y = _origin.y - BOX_SIZE.y * 0.5 - RISE_DISTANCE * t

	if _elapsed >= FADE_START:
		var fade_progress: float = (_elapsed - FADE_START) / (LIFETIME - FADE_START)
		modulate.a = 1.0 - clampf(fade_progress, 0.0, 1.0)

	if _elapsed >= LIFETIME:
		queue_free()


func get_amount_text() -> String:
	return text
