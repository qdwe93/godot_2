extends Node2D


const PLAYER_SCENE := preload("res://scenes/player.tscn")
const SCREEN_CENTER := Vector2(640.0, 360.0)
const MOVEMENT_FRAMES := 30
const MOVEMENT_TOLERANCE := 0.05
const Y_TOLERANCE := 1.0
const CLAMP_FRAMES := 3

var passed_count := 0
var failed_count := 0
var skipped_count := 0


func _ready() -> void:
	var player := PLAYER_SCENE.instantiate() as CharacterBody2D
	add_child(player)

	var case_1_distance := await _test_horizontal_movement(player)
	await _test_diagonal_speed(player, case_1_distance)
	await _test_screen_bounds_clamp(player)

	var all_passed := failed_count == 0
	print(
		"TEST_RESULT %s passed=%d failed=%d skipped=%d"
		% [_verdict(all_passed), passed_count, failed_count, skipped_count]
	)
	get_tree().quit(0 if all_passed else 1)


func _test_horizontal_movement(player: CharacterBody2D) -> float:
	_release_movement_actions()
	player.global_position = SCREEN_CENTER
	var start_position := player.global_position
	var speed := float(player.get("speed"))
	var expected_x := speed * MOVEMENT_FRAMES / float(Engine.physics_ticks_per_second)

	Input.action_press("move_right")
	await _advance_physics(MOVEMENT_FRAMES)
	Input.action_release("move_right")

	var displacement := player.global_position - start_position
	var x_tolerance := expected_x * MOVEMENT_TOLERANCE
	var passed := (
		absf(displacement.x - expected_x) <= x_tolerance
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
	var passed := absf(diagonal_distance - case_1_distance) <= distance_tolerance
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
	var body_radius := float(player.get("body_radius"))
	var minimum_position := Vector2(body_radius, body_radius)
	var maximum_position := project_viewport_size - minimum_position
	if DisplayServer.get_name() == "headless":
		_record_skipped_case(
			"screen_bounds_clamp",
			(
				"headless does not report a correct viewport size; screen bounds require "
				+ "a windowed run project_settings=(%.3f,%.3f) "
				+ "project_bounds=(%.3f,%.3f)-(%.3f,%.3f) "
				+ "runtime_viewport=(%.3f,%.3f)"
			)
			% [
				project_viewport_size.x,
				project_viewport_size.y,
				minimum_position.x,
				minimum_position.y,
				maximum_position.x,
				maximum_position.y,
				runtime_viewport_size.x,
				runtime_viewport_size.y,
			]
		)
		return

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
