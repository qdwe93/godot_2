extends Node2D


const PLAYER_SCENE := preload("res://scenes/player.tscn")
const EXPECTED_CASE_COUNT := 3
const SCREEN_CENTER := Vector2(640.0, 360.0)
const MOVEMENT_FRAMES := 30
const MOVEMENT_TOLERANCE := 0.05
const Y_TOLERANCE := 1.0
const MEASUREMENT_EPSILON := 0.001

var passed_count := 0
var failed_count := 0
var skipped_count := 0


func _ready() -> void:
	var setup_error: String = _validate_dependencies()
	if not setup_error.is_empty():
		print("TEST_ERROR setup_failed %s" % setup_error)
		get_tree().quit(1)
		return

	var player := PLAYER_SCENE.instantiate() as CharacterBody2D
	add_child(player)

	var case_1_distance: float = await _test_horizontal_movement(player)
	await _test_diagonal_speed(player, case_1_distance)
	await _test_movement_is_unbounded(player)

	_finish_suite()


func _validate_dependencies() -> String:
	if PLAYER_SCENE == null:
		return "player scene did not load"
	var player_node: Node = PLAYER_SCENE.instantiate()
	if not player_node is CharacterBody2D:
		player_node.free()
		return "player scene root is not CharacterBody2D"
	if player_node.get_script() == null:
		player_node.free()
		return "player script did not load"
	if not player_node.has_method("_physics_process"):
		player_node.free()
		return "player is missing _physics_process()"
	if not ("speed" in player_node) or not ("body_radius" in player_node):
		player_node.free()
		return "player is missing movement properties"
	if not player_node.get_node_or_null("Hurtbox") is Area2D:
		player_node.free()
		return "player Hurtbox Area2D is missing"
	player_node.free()
	return ""


func _finish_suite() -> void:
	var recorded_count := passed_count + failed_count + skipped_count
	var has_all_cases := recorded_count == EXPECTED_CASE_COUNT
	if not has_all_cases:
		print(
			"TEST_ERROR missing_cases expected=%d recorded=%d"
			% [EXPECTED_CASE_COUNT, recorded_count]
		)
	var all_passed := passed_count == EXPECTED_CASE_COUNT and failed_count == 0 and has_all_cases
	print(
		"TEST_RESULT %s passed=%d failed=%d skipped=%d"
		% [_verdict(all_passed), passed_count, failed_count, skipped_count]
	)
	get_tree().quit(0 if all_passed else 1)


func _test_horizontal_movement(player: CharacterBody2D) -> float:
	_release_movement_actions()
	player.global_position = SCREEN_CENTER
	var start_position := player.global_position
	var speed: float = float(player.get("speed"))
	var expected_x := speed * MOVEMENT_FRAMES / float(Engine.physics_ticks_per_second)

	Input.action_press("move_right")
	await _advance_physics(MOVEMENT_FRAMES)
	Input.action_release("move_right")

	var displacement := player.global_position - start_position
	var x_tolerance := expected_x * MOVEMENT_TOLERANCE
	var passed := (
		expected_x > MEASUREMENT_EPSILON
		and displacement.length() > MEASUREMENT_EPSILON
		and absf(displacement.x - expected_x) <= x_tolerance
		and absf(displacement.y) < Y_TOLERANCE
	)
	_record_case(
		"horizontal_movement",
		passed,
		"actual_x=%.3f expected_x=%.3f delta_y=%.3f tolerance=%.3f"
		% [displacement.x, expected_x, displacement.y, x_tolerance]
	)
	_release_movement_actions()
	return displacement.length()


func _test_diagonal_speed(player: CharacterBody2D, case_1_distance: float) -> void:
	_release_movement_actions()
	player.global_position = SCREEN_CENTER
	var start_position := player.global_position

	Input.action_press("move_right")
	Input.action_press("move_down")
	await _advance_physics(MOVEMENT_FRAMES)
	Input.action_release("move_right")
	Input.action_release("move_down")

	var displacement := player.global_position - start_position
	var diagonal_distance := displacement.length()
	var distance_tolerance := case_1_distance * MOVEMENT_TOLERANCE
	var passed := (
		diagonal_distance > MEASUREMENT_EPSILON
		and case_1_distance > MEASUREMENT_EPSILON
		and absf(diagonal_distance - case_1_distance) <= distance_tolerance
	)
	_record_case(
		"diagonal_speed",
		passed,
		"actual_distance=%.3f case_1_distance=%.3f dx=%.3f dy=%.3f tolerance=%.3f"
		% [
			diagonal_distance,
			case_1_distance,
			displacement.x,
			displacement.y,
			distance_tolerance,
		]
	)
	_release_movement_actions()


## M16에서 화면 가두기(`_clamp_to_screen`)를 없앴다.
##
## 카메라가 주인공을 따라다니면 뷰포트 사각형도 주인공과 함께 움직인다. 그 안에
## 가둔다는 것은 자기 자신을 가두는 꼴이라 아무 의미가 없다. 그래서 여기서 고정할
## 것은 예전 케이스의 정반대다 — 화면 끝에 닿아도 **계속 나아가는가.**
##
## 가두기가 되살아나면 이 케이스가 즉시 잡는다.
func _test_movement_is_unbounded(player: CharacterBody2D) -> void:
	_release_movement_actions()
	# 구현과 같은 출처를 쓴다. 헤드리스는 뷰포트 높이를 틀리게 보고하지만
	# "경계를 넘어가는가"라는 관계는 어느 환경에서나 그대로 성립한다.
	var arena_size := Arena.get_size(player)
	var start_position := Vector2(arena_size.x - 20.0, arena_size.y * 0.5)
	player.global_position = start_position
	var speed: float = float(player.get("speed"))
	var expected_x := speed * MOVEMENT_FRAMES / float(Engine.physics_ticks_per_second)

	Input.action_press("move_right")
	await _advance_physics(MOVEMENT_FRAMES)
	Input.action_release("move_right")

	var travelled := player.global_position.x - start_position.x
	var passed := (
		player.global_position.x > arena_size.x
		and travelled >= expected_x * 0.8
	)
	_record_case(
		"movement_is_unbounded",
		passed,
		"start_x=%.3f end_x=%.3f arena_width=%.3f travelled=%.3f expected=%.3f"
		% [
			start_position.x,
			player.global_position.x,
			arena_size.x,
			travelled,
			expected_x,
		]
	)
	_release_movement_actions()


func _advance_physics(frame_count: int) -> void:
	for _frame in range(frame_count):
		await get_tree().physics_frame


func _release_movement_actions() -> void:
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("move_up")
	Input.action_release("move_down")


func _record_case(case_name: String, passed: bool, detail: String) -> void:
	if passed:
		passed_count += 1
	else:
		failed_count += 1
	print("TEST_CASE %s %s %s" % [case_name, _verdict(passed), detail])


func _record_skipped_case(case_name: String, detail: String) -> void:
	skipped_count += 1
	print("TEST_CASE %s SKIP %s" % [case_name, detail])


func _verdict(passed: bool) -> String:
	return "PASS" if passed else "FAIL"
