extends Node2D


const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const ENEMY_SPAWNER_SCRIPT := preload("res://scripts/enemy_spawner.gd")
const PERIODIC_INTERVAL := 0.1
const PERIODIC_FRAMES := 30
const OFFSCREEN_SPAWN_COUNT := 20
const CHASE_FRAMES := 30
const CHASE_TOLERANCE := 0.1
const CAP_INTERVAL := 0.05
const CAP_VALUE := 5
const CAP_FRAMES := 90

var passed_count := 0
var failed_count := 0
var skipped_count := 0


func _ready() -> void:
	await _test_periodic_spawning()
	await _test_spawn_position_offscreen()
	await _test_enemies_chase_player()
	await _test_max_enemies_cap()

	var all_passed := failed_count == 0
	print(
		"TEST_RESULT %s passed=%d failed=%d skipped=%d"
		% [_verdict(all_passed), passed_count, failed_count, skipped_count]
	)
	get_tree().quit(0 if all_passed else 1)


func _test_periodic_spawning() -> void:
	var setup := _create_setup(PERIODIC_INTERVAL, 30)
	var container := setup["container"] as Node2D

	await _advance_physics(PERIODIC_FRAMES)
	var actual_count := container.get_child_count()
	_record_case(
		"periodic_spawning",
		actual_count >= 3,
		"actual_count=%d interval=%.3f frames=%d"
		% [actual_count, PERIODIC_INTERVAL, PERIODIC_FRAMES]
	)
	await _free_setup(setup)


func _test_spawn_position_offscreen() -> void:
	var setup := _create_setup(3600.0, OFFSCREEN_SPAWN_COUNT)
	var spawner := setup["spawner"] as Node
	var design_screen_size := _design_screen_size()
	var screen_center := design_screen_size / 2.0
	var inside_count := 0
	var minimum_center_distance := INF

	for _spawn_index in range(OFFSCREEN_SPAWN_COUNT):
		var enemy := spawner.call("spawn_one") as Node2D
		if enemy == null:
			inside_count += 1
			continue
		var spawn_position := enemy.global_position
		if _is_inside_design_screen(spawn_position, design_screen_size):
			inside_count += 1
		minimum_center_distance = minf(
			minimum_center_distance,
			spawn_position.distance_to(screen_center)
		)

	_record_case(
		"spawn_position_offscreen",
		inside_count == 0,
		"inside_count=%d spawn_count=%d minimum_center_distance=%.3f design_size=(%.3f,%.3f)"
		% [
			inside_count,
			OFFSCREEN_SPAWN_COUNT,
			minimum_center_distance,
			design_screen_size.x,
			design_screen_size.y,
		]
	)
	await _free_setup(setup)


func _test_enemies_chase_player() -> void:
	var setup := _create_setup(3600.0, 1)
	var player := setup["player"] as CharacterBody2D
	var spawner := setup["spawner"] as Node
	player.global_position = _design_screen_size() / 2.0
	var enemy := spawner.call("spawn_one") as CharacterBody2D

	if enemy == null:
		_record_case(
			"enemies_chase_player",
			false,
			"enemy_spawned=false initial_distance=0.000 final_distance=0.000 expected_delta=0.000"
		)
		await _free_setup(setup)
		return

	var initial_distance := enemy.global_position.distance_to(player.global_position)
	var enemy_speed := float(enemy.get("speed"))
	var expected_delta := (
		enemy_speed * CHASE_FRAMES / float(Engine.physics_ticks_per_second)
	)
	await _advance_physics(CHASE_FRAMES)
	var final_distance := enemy.global_position.distance_to(player.global_position)
	var actual_delta := initial_distance - final_distance
	var tolerance := expected_delta * CHASE_TOLERANCE
	var passed := (
		final_distance < initial_distance
		and absf(actual_delta - expected_delta) <= tolerance
	)
	_record_case(
		"enemies_chase_player",
		passed,
		(
			"initial_distance=%.3f final_distance=%.3f actual_delta=%.3f "
			+ "expected_delta=%.3f tolerance=%.3f"
		)
		% [initial_distance, final_distance, actual_delta, expected_delta, tolerance]
	)
	await _free_setup(setup)


func _test_max_enemies_cap() -> void:
	var setup := _create_setup(CAP_INTERVAL, CAP_VALUE)
	var container := setup["container"] as Node2D
	var peak_count := 0

	for _frame in range(CAP_FRAMES):
		await get_tree().physics_frame
		peak_count = maxi(peak_count, container.get_child_count())

	var final_count := container.get_child_count()
	var passed := peak_count <= CAP_VALUE and final_count == CAP_VALUE
	_record_case(
		"max_enemies_cap",
		passed,
		"peak_count=%d final_count=%d cap=%d interval=%.3f frames=%d"
		% [peak_count, final_count, CAP_VALUE, CAP_INTERVAL, CAP_FRAMES]
	)
	await _free_setup(setup)


func _create_setup(interval: float, cap: int) -> Dictionary:
	var player := PLAYER_SCENE.instantiate() as CharacterBody2D
	player.name = "Player"
	add_child(player)

	var container := Node2D.new()
	container.name = "EnemyContainer"
	add_child(container)

	var spawner := ENEMY_SPAWNER_SCRIPT.new()
	spawner.name = "EnemySpawner"
	spawner.set("enemy_scene", ENEMY_SCENE)
	spawner.set("spawn_interval", interval)
	spawner.set("max_enemies", cap)
	spawner.set("enemy_container_path", NodePath("../EnemyContainer"))
	spawner.set("target_path", NodePath("../Player"))
	add_child(spawner)

	return {
		"player": player,
		"container": container,
		"spawner": spawner,
	}


func _free_setup(setup: Dictionary) -> void:
	for key: String in ["spawner", "container", "player"]:
		var node := setup[key] as Node
		if is_instance_valid(node):
			node.queue_free()
	await get_tree().process_frame


func _advance_physics(frame_count: int) -> void:
	for _frame in range(frame_count):
		await get_tree().physics_frame


func _design_screen_size() -> Vector2:
	return Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width")),
		float(ProjectSettings.get_setting("display/window/size/viewport_height"))
	)


func _is_inside_design_screen(position: Vector2, design_size: Vector2) -> bool:
	return (
		position.x >= 0.0
		and position.x <= design_size.x
		and position.y >= 0.0
		and position.y <= design_size.y
	)


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
