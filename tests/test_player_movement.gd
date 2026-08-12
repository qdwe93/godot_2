extends Node2D


const PLAYER_SCENE := preload("res://scenes/player.tscn")
const EXPECTED_CASE_COUNT := 3
const SCREEN_CENTER := Vector2(640.0, 360.0)
const MOVEMENT_FRAMES := 30
const MOVEMENT_TOLERANCE := 0.05
const Y_TOLERANCE := 1.0
const CLAMP_FRAMES := 3
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
	await _test_screen_bounds_clamp(player)

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


func _test_screen_bounds_clamp(player: CharacterBody2D) -> void:
	_release_movement_actions()
	player.global_position = SCREEN_CENTER
	var project_viewport_size := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width")),
		float(ProjectSettings.get_setting("display/window/size/viewport_height"))
	)
	var runtime_viewport_size := get_viewport_rect().size
	var body_radius: float = float(player.get("body_radius"))
	var minimum_position := Vector2(body_radius, body_radius)
	var maximum_position := project_viewport_size - minimum_position

	player.global_position = Vector2(5000.0, 5000.0)
	await _advance_physics(CLAMP_FRAMES)
	var positive_corner_position := player.global_position
	var positive_corner_inside := _is_inside_bounds(
		positive_corner_position, minimum_position, maximum_position
	)

	player.global_position = Vector2(-5000.0, -5000.0)
	await _advance_physics(CLAMP_FRAMES)
	var negative_corner_position := player.global_position
	var negative_corner_inside := _is_inside_bounds(
		negative_corner_position, minimum_position, maximum_position
	)

	var passed := positive_corner_inside and negative_corner_inside
	_record_case(
		"screen_bounds_clamp",
		passed,
		(
			"positive=(%.3f,%.3f) negative=(%.3f,%.3f) "
			+ "project_settings=(%.3f,%.3f) "
			+ "project_bounds=(%.3f,%.3f)-(%.3f,%.3f) "
			+ "runtime_viewport=(%.3f,%.3f) radius=%.3f"
		)
		% [
			positive_corner_position.x,
			positive_corner_position.y,
			negative_corner_position.x,
			negative_corner_position.y,
			project_viewport_size.x,
			project_viewport_size.y,
			minimum_position.x,
			minimum_position.y,
			maximum_position.x,
			maximum_position.y,
			runtime_viewport_size.x,
			runtime_viewport_size.y,
			body_radius,
		]
	)
	_release_movement_actions()


func _advance_physics(frame_count: int) -> void:
	for _frame in range(frame_count):
		await get_tree().physics_frame


func _is_inside_bounds(position: Vector2, minimum: Vector2, maximum: Vector2) -> bool:
	return (
		position.x >= minimum.x
		and position.x <= maximum.x
		and position.y >= minimum.y
		and position.y <= maximum.y
	)


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
