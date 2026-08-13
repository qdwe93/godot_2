extends Node

## 조이스틱이 실제로 **화면에 그려지는지** 눈으로 확인하기 위한 캡처용 진단.
##
## 유닛 테스트는 "액션이 눌렸는가"까지만 본다. 이 프로젝트는 유닛이 다 통과하는데
## 화면에는 안 나오는 사고를 여러 번 겪었으므로(보스 실루엣, 산탄 미노출) 그리기
## 경로는 캡처로 따로 확인한다.
##
## 창 모드로만 의미가 있다:
##   Godot..._console.exe --path <project> res://tests/diag_joystick_capture.tscn \
##       --quit-after 600 -- "--auto-play" "--capture=<경로>.png" "--capture-after=2.0"

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")


func _ready() -> void:
	var main: Node = MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var game_flow: Node = main.get_node_or_null("GameFlow")
	if game_flow != null:
		game_flow.call(&"enable_auto_play")

	var joystick: Node = main.get_node_or_null("TouchJoystick")
	if joystick == null:
		print("DIAG_ERROR joystick_missing")
		return

	# 화면 왼쪽 아래를 누른 뒤 오른쪽 위로 끈 상태로 유지한다.
	var touch: InputEventScreenTouch = InputEventScreenTouch.new()
	touch.index = 0
	touch.position = Vector2(300.0, 500.0)
	touch.pressed = true
	joystick.call(&"feed_event_for_testing", touch)

	var drag: InputEventScreenDrag = InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(370.0, 430.0)
	joystick.call(&"feed_event_for_testing", drag)

	print("DIAG_JOYSTICK active=%s vector=%s" % [
		str(joystick.call(&"is_active")).to_lower(),
		str(joystick.call(&"get_vector")),
	])
