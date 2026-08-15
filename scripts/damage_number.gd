extends Label

# 짧은 수명 안에 타격 지점에서 분리돼 보이면서도 전투 화면을 오래 가리지 않게 한다.
const RISE_DISTANCE: float = 52.0
const LIFETIME: float = 0.7
# M22 에서 0.35 -> 0.5 로 늦췄다.
#
# 피해 숫자는 흰 글자 + 8px 검은 외곽선이다. 근검정 바닥에서는 흰 글자 자체가
# 대비를 냈지만, 밝은 회보라 바닥(#A9A3C4)에서 흰색은 2.4:1 뿐이라 **대비를
# 외곽선이 혼자 떠받친다.** 그런데 `modulate.a` 는 글자와 외곽선을 함께 흐리므로
# 사라지는 동안 떠받칠 것이 같이 없어진다.
#
# 0.35 면 수명의 절반이 흐려지는 구간이었다. 캡처를 아무 때나 찍어도 절반은
# 읽히지 않는다는 뜻이다. 0.5 로 올려 71% 를 불투명하게 유지한다.
const FADE_START: float = 0.5
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
