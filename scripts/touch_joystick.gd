extends CanvasLayer

## 모바일용 가상 조이스틱 (떠다니는 방식).
##
## 화면 아무 데나 손가락을 대면 그 자리에 조이스틱이 생기고, 끌면 그 방향으로 움직인다.
## 떼면 사라진다. 고정 위치 조이스틱보다 손 위치를 안 가려도 되어 편하다.
##
## 설계에서 가장 중요한 결정
## -------------------------
## **이 노드는 `player.gd`를 건드리지 않는다.** 대신 `Input.action_press()`로
## InputMap의 `move_*` 액션을 직접 눌러 준다.
##
## 플레이어는 이미 `Input.get_vector("move_left", ...)`로 입력을 읽고 있으므로,
## 그 아래에 값을 넣어 주면 **키보드와 완전히 같은 경로**로 흐른다. 덕분에
##   - `player.gd`는 한 줄도 안 바뀐다
##   - 기존 이동 테스트가 그대로 유효하다
##   - 봇 진단(`tests/diag_balance.gd`)도 같은 방식이라 서로 자연스럽게 공존한다
## 플레이어에 조이스틱 참조를 심는 방식이었다면 세 곳을 다 고쳐야 했다.
##
## `_unhandled_input`을 쓰는 이유
## ------------------------------
## GUI 컨트롤(타이틀 시작 버튼, 레벨업 3택)이 입력을 **먼저** 가져간다.
## `_input`을 쓰면 버튼 위를 눌러도 조이스틱이 먼저 잡아채 버튼이 안 눌린다.

const MAX_RADIUS: float = 90.0
## 이 비율 아래의 기울기는 0으로 본다. 손가락을 댄 채 가만히 있을 때
## 미세한 떨림으로 캐릭터가 흐르는 것을 막는다.
const DEAD_ZONE: float = 0.15

# 반투명 흰색. 폰 야외에서도 보이되 게임 요소를 이기지 않는 선이다.
# 시각 위계(docs/ASSETS.md 3-0절)상 플레이어(배경 대비 12.92:1)보다 확실히 어두워야 한다.
const BASE_COLOR: Color = Color(1.0, 1.0, 1.0, 0.22)
const KNOB_COLOR: Color = Color(1.0, 1.0, 1.0, 0.45)
const BASE_RADIUS: float = 62.0
const KNOB_RADIUS: float = 28.0

const MOVE_ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_up", &"move_down",
]

var _touch_index: int = -1
var _origin: Vector2 = Vector2.ZERO
var _current: Vector2 = Vector2.ZERO

@onready var _canvas: Control = $Canvas


func _ready() -> void:
	# 일시정지 중에도 입력을 받아야 한다. 안 그러면 레벨업 창이 뜬 순간 손가락을 떼도
	# 그 사실이 전달되지 않아, 재개했을 때 누른 방향으로 계속 달린다.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas.visible = false


func _exit_tree() -> void:
	# 액션은 전역 상태다. 눌린 채로 사라지면 그 방향으로 영원히 이동하게 된다.
	_release_actions()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed:
			if _touch_index == -1:
				_begin(touch.index, touch.position)
		elif touch.index == _touch_index:
			_end()
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if drag.index == _touch_index:
			_move(drag.position)


func _begin(index: int, position: Vector2) -> void:
	_touch_index = index
	_origin = position
	_current = position
	_canvas.visible = true
	_canvas.queue_redraw()
	_apply_actions()


func _move(position: Vector2) -> void:
	_current = position
	_canvas.queue_redraw()
	_apply_actions()


func _end() -> void:
	_touch_index = -1
	_canvas.visible = false
	_canvas.queue_redraw()
	_release_actions()


## 손가락 위치에서 이동 벡터를 만든다. 길이는 0~1이다.
func get_vector() -> Vector2:
	if _touch_index == -1:
		return Vector2.ZERO
	var offset: Vector2 = _current - _origin
	var strength: float = minf(offset.length() / MAX_RADIUS, 1.0)
	if strength < DEAD_ZONE:
		return Vector2.ZERO
	return offset.normalized() * strength


func is_active() -> bool:
	return _touch_index != -1


func _apply_actions() -> void:
	var vector: Vector2 = get_vector()
	_release_actions()
	if vector.x < 0.0:
		Input.action_press(&"move_left", absf(vector.x))
	elif vector.x > 0.0:
		Input.action_press(&"move_right", vector.x)
	if vector.y < 0.0:
		Input.action_press(&"move_up", absf(vector.y))
	elif vector.y > 0.0:
		Input.action_press(&"move_down", vector.y)


func _release_actions() -> void:
	for action in MOVE_ACTIONS:
		if Input.is_action_pressed(action):
			Input.action_release(action)


## 테스트 이음매 — 실제 터치 이벤트를 만들지 않고도 같은 경로를 태울 수 있다.
func feed_event_for_testing(event: InputEvent) -> void:
	_unhandled_input(event)


func _on_canvas_draw() -> void:
	if _touch_index == -1:
		return
	var offset: Vector2 = _current - _origin
	if offset.length() > MAX_RADIUS:
		offset = offset.normalized() * MAX_RADIUS
	_canvas.draw_circle(_origin, BASE_RADIUS, BASE_COLOR)
	_canvas.draw_circle(_origin + offset, KNOB_RADIUS, KNOB_COLOR)
