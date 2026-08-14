extends ProgressBar

# 72px 캐릭터의 실루엣을 가리지 않으면서 발밑에서 즉시 읽히는 크기와 간격이다.
const BAR_SIZE: Vector2 = Vector2(96.0, 12.0)
const BAR_OFFSET: Vector2 = Vector2(0.0, 44.0)

var _player: Node
var _original_fill_style: StyleBox
var _danger_fill_style: StyleBoxFlat
var _is_danger: bool = false


func _ready() -> void:
	_original_fill_style = get_theme_stylebox(&"fill")
	_danger_fill_style = StyleBoxFlat.new()
	_danger_fill_style.bg_color = Color(0.95, 0.25, 0.25, 1.0)
	_danger_fill_style.corner_radius_top_left = 3
	_danger_fill_style.corner_radius_top_right = 3
	_danger_fill_style.corner_radius_bottom_right = 3
	_danger_fill_style.corner_radius_bottom_left = 3

	# 부모가 Node2D라 Control 앵커가 적용되지 않으므로 월드 위치와 크기를 직접 맞춘다.
	size = BAR_SIZE
	position = BAR_OFFSET - Vector2(BAR_SIZE.x * 0.5, 0.0)
	show_percentage = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 10

	_player = get_parent()
	# 다른 부모 아래에 잘못 배치돼도 신호 연결 오류를 반복하지 않고 이 바만 멈춘다.
	if not _player.has_signal(&"health_changed"):
		push_error("PlayerHealthBar: parent has no health_changed signal.")
		return

	_player.connect(&"health_changed", Callable(self, &"_on_health_changed"))
	if _player.has_signal(&"died"):
		_player.connect(&"died", Callable(self, &"_on_player_died"))

	# 연결 직후 현재값을 채워 첫 피해 전에도 빈 체력바로 보이지 않게 한다.
	#
	# **반드시 지연 호출이어야 한다.** Godot 은 자식의 _ready() 를 부모보다 **먼저**
	# 부른다. 그래서 여기서 바로 읽으면 player.gd 의 _ready() 가 아직 안 돌아
	# `health` 가 0.0 이고, 체력이 가득인데도 바가 텅 빈 채로 남는다. 그 뒤로는
	# 처음 피해를 입을 때까지 health_changed 가 발생하지 않으므로 (재생도 만렙에서는
	# 신호를 쏘지 않는다) 빈 바가 계속 보인다. 실제로 캡처에서 이 상태로 잡혔다.
	_refresh_from_player.call_deferred()


func _refresh_from_player() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var current_health: float = float(_player.get(&"health"))
	var maximum_health: float = float(_player.get(&"max_health"))
	_on_health_changed(current_health, maximum_health)


func _on_health_changed(current: float, maximum: float) -> void:
	max_value = maximum
	value = current
	_set_danger_style(_get_low_health_state(current, maximum))


func _get_low_health_state(current: float, maximum: float) -> bool:
	# 0.3 기준이 player.gd와 hud.gd에 이미 있으므로 주인공의 판정을 단일 기준으로 삼는다.
	if _player != null and _player.has_method(&"is_low_health"):
		return bool(_player.call(&"is_low_health"))
	if maximum <= 0.0:
		return false
	return current / maximum <= 0.3


func _set_danger_style(is_danger: bool) -> void:
	_is_danger = is_danger
	if _is_danger:
		add_theme_stylebox_override(&"fill", _danger_fill_style)
	else:
		add_theme_stylebox_override(&"fill", _original_fill_style)


func _on_player_died() -> void:
	hide()


func is_danger_style() -> bool:
	return _is_danger
