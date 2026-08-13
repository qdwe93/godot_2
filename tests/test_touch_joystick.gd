extends Node

## 가상 조이스틱 검사.
##
## 이 스위트가 지키는 계약은 하나다.
##
##   **조이스틱은 키보드와 똑같은 경로(InputMap의 move_* 액션)로 값을 넣는다.**
##
## 그래야 `player.gd`를 안 고치고도 터치가 동작하고, 봇 진단과 기존 이동 테스트가
## 그대로 유효하다. 그래서 검사도 "플레이어가 움직였는가"가 아니라
## **"액션이 눌렸는가"**를 본다 — 계약을 직접 보는 쪽이 회귀를 정확히 잡는다.

const EXPECTED_CASE_COUNT: int = 6
const JOYSTICK_SCENE: PackedScene = preload("res://scenes/touch_joystick.tscn")
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

const MOVE_ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_up", &"move_down",
]

var _passed: int = 0
var _failed: int = 0
var _skipped: int = 0
var _recorded: int = 0


func _ready() -> void:
	await get_tree().process_frame
	_release_all()
	_case_drag_presses_direction()
	_case_release_clears_actions()
	_case_dead_zone_ignores_tiny_drag()
	_case_strength_scales_with_distance()
	_case_second_finger_does_not_steal()
	await _case_wired_into_main_scene()

	_release_all()
	if _recorded != EXPECTED_CASE_COUNT:
		print("TEST_ERROR missing_cases expected=%d recorded=%d" % [EXPECTED_CASE_COUNT, _recorded])
		_failed += 1
	var overall: String = "PASS" if _failed == 0 and _passed > 0 and _recorded == EXPECTED_CASE_COUNT else "FAIL"
	print("TEST_RESULT %s passed=%d failed=%d skipped=%d" % [overall, _passed, _failed, _skipped])
	get_tree().quit(0 if overall == "PASS" else 1)


func _make_joystick() -> Node:
	var joystick: Node = JOYSTICK_SCENE.instantiate()
	add_child(joystick)
	return joystick


func _touch(index: int, position: Vector2, pressed: bool) -> InputEventScreenTouch:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	return event


func _drag(index: int, position: Vector2) -> InputEventScreenDrag:
	var event: InputEventScreenDrag = InputEventScreenDrag.new()
	event.index = index
	event.position = position
	return event


func _release_all() -> void:
	for action in MOVE_ACTIONS:
		if Input.is_action_pressed(action):
			Input.action_release(action)


## 오른쪽 위로 끌면 move_right / move_up 이 눌려야 한다.
## 화면 좌표는 y가 아래로 커지므로, 위로 끄는 것은 y가 **줄어드는** 것이다.
func _case_drag_presses_direction() -> void:
	var joystick: Node = _make_joystick()
	joystick.call(&"feed_event_for_testing", _touch(0, Vector2(300, 400), true))
	joystick.call(&"feed_event_for_testing", _drag(0, Vector2(390, 310)))

	var right: float = Input.get_action_strength(&"move_right")
	var up: float = Input.get_action_strength(&"move_up")
	var left: float = Input.get_action_strength(&"move_left")
	var down: float = Input.get_action_strength(&"move_down")
	_record("drag_presses_direction", right > 0.0 and up > 0.0 and left == 0.0 and down == 0.0,
		"right=%.2f up=%.2f left=%.2f down=%.2f" % [right, up, left, down])
	joystick.free()
	_release_all()


## 손가락을 떼면 액션이 전부 풀려야 한다.
## 액션은 전역 상태라, 안 풀면 그 방향으로 영원히 달린다.
func _case_release_clears_actions() -> void:
	var joystick: Node = _make_joystick()
	joystick.call(&"feed_event_for_testing", _touch(0, Vector2(300, 400), true))
	joystick.call(&"feed_event_for_testing", _drag(0, Vector2(400, 400)))
	var pressed_before: bool = Input.get_action_strength(&"move_right") > 0.0
	joystick.call(&"feed_event_for_testing", _touch(0, Vector2(400, 400), false))

	var any_pressed: bool = false
	for action in MOVE_ACTIONS:
		if Input.get_action_strength(action) > 0.0:
			any_pressed = true
	_record("release_clears_actions", pressed_before and not any_pressed,
		"pressed_before=%s any_after=%s" % [str(pressed_before).to_lower(), str(any_pressed).to_lower()])
	joystick.free()
	_release_all()


## 아주 조금 끄는 것은 무시해야 한다. 손가락을 댄 채 가만히 있을 때 캐릭터가 흐르면
## 조준이 어긋난다.
func _case_dead_zone_ignores_tiny_drag() -> void:
	var joystick: Node = _make_joystick()
	var dead_zone: float = float(joystick.get(&"DEAD_ZONE"))
	var max_radius: float = float(joystick.get(&"MAX_RADIUS"))
	# 데드존 경계의 절반만큼만 끈다 — 정의에서 계산하므로 상수를 바꿔도 안 깨진다.
	var tiny: float = max_radius * dead_zone * 0.5

	joystick.call(&"feed_event_for_testing", _touch(0, Vector2(300, 400), true))
	joystick.call(&"feed_event_for_testing", _drag(0, Vector2(300 + tiny, 400)))

	var vector: Vector2 = joystick.call(&"get_vector")
	var any_pressed: bool = false
	for action in MOVE_ACTIONS:
		if Input.get_action_strength(action) > 0.0:
			any_pressed = true
	_record("dead_zone_ignores_tiny_drag", dead_zone > 0.0 and vector == Vector2.ZERO and not any_pressed,
		"dead_zone=%.2f drag_px=%.1f vector=%s pressed=%s" % [dead_zone, tiny, str(vector), str(any_pressed).to_lower()])
	joystick.free()
	_release_all()


## 멀리 끌수록 세게. 그리고 최대 반경을 넘어도 1.0을 넘지 않아야 한다.
func _case_strength_scales_with_distance() -> void:
	var joystick: Node = _make_joystick()
	var max_radius: float = float(joystick.get(&"MAX_RADIUS"))

	joystick.call(&"feed_event_for_testing", _touch(0, Vector2(300, 400), true))
	joystick.call(&"feed_event_for_testing", _drag(0, Vector2(300 + max_radius * 0.5, 400)))
	var half: float = Input.get_action_strength(&"move_right")
	joystick.call(&"feed_event_for_testing", _drag(0, Vector2(300 + max_radius * 3.0, 400)))
	var beyond: float = Input.get_action_strength(&"move_right")

	_record("strength_scales_with_distance", half > 0.0 and beyond > half and beyond <= 1.0,
		"half=%.2f beyond_max=%.2f" % [half, beyond])
	joystick.free()
	_release_all()


## 두 번째 손가락이 조이스틱을 빼앗으면 안 된다.
## 폰에서는 한 손으로 움직이며 다른 손으로 화면을 누르는 일이 흔하다.
func _case_second_finger_does_not_steal() -> void:
	var joystick: Node = _make_joystick()
	joystick.call(&"feed_event_for_testing", _touch(0, Vector2(300, 400), true))
	joystick.call(&"feed_event_for_testing", _drag(0, Vector2(390, 400)))
	var before: float = Input.get_action_strength(&"move_right")

	# 다른 손가락이 반대쪽을 누르고 뗀다
	joystick.call(&"feed_event_for_testing", _touch(1, Vector2(900, 200), true))
	joystick.call(&"feed_event_for_testing", _drag(1, Vector2(800, 200)))
	joystick.call(&"feed_event_for_testing", _touch(1, Vector2(800, 200), false))
	var after: float = Input.get_action_strength(&"move_right")

	_record("second_finger_does_not_steal", before > 0.0 and is_equal_approx(before, after),
		"before=%.2f after=%.2f still_active=%s" % [before, after, str(joystick.call(&"is_active")).to_lower()])
	joystick.free()
	_release_all()


## 배선 검사 — 실제 main.tscn 안에 조이스틱이 들어 있는가.
## 유닛으로는 다 통과하는데 게임에는 안 붙어 있는 사고를 이 프로젝트가 세 번 겪었다.
func _case_wired_into_main_scene() -> void:
	var main: Node = MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame

	var joystick: Node = null
	for child in main.get_children():
		if child.get_script() != null and child.has_method(&"get_vector") and child.has_method(&"is_active"):
			joystick = child
			break

	var ok: bool = joystick != null
	var always_on: bool = ok and int(joystick.get(&"process_mode")) == Node.PROCESS_MODE_ALWAYS
	_record("wired_into_main_scene", ok and always_on,
		"found=%s process_mode=%s (ALWAYS=%d)" % [
			str(ok).to_lower(),
			str(joystick.get(&"process_mode")) if ok else "-",
			Node.PROCESS_MODE_ALWAYS])
	main.free()
	_release_all()


func _record(case_name: String, ok: bool, detail: String) -> void:
	_recorded += 1
	if ok:
		_passed += 1
		print("TEST_CASE %s PASS %s" % [case_name, detail])
	else:
		_failed += 1
		print("TEST_CASE %s FAIL %s" % [case_name, detail])
