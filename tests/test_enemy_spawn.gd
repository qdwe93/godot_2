extends Node2D


const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const ENEMY_SPAWNER_SCRIPT := preload("res://scripts/enemy_spawner.gd")
const EXPECTED_CASE_COUNT := 4
const PERIODIC_INTERVAL := 0.1
const PERIODIC_FRAMES := 30
const OFFSCREEN_SPAWN_COUNT := 20
const CHASE_FRAMES := 30
const CHASE_TOLERANCE := 0.1
const CAP_INTERVAL := 0.05
const CAP_VALUE := 5
const CAP_FRAMES := 90
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

	await _test_periodic_spawning()
	await _test_spawn_position_offscreen()
	await _test_enemies_chase_player()
	await _test_max_enemies_cap()

	_finish_suite()


func _validate_dependencies() -> String:
	if PLAYER_SCENE == null:
		return "player scene did not load"
	if ENEMY_SCENE == null:
		return "enemy scene did not load"
	if ENEMY_SPAWNER_SCRIPT == null:
		return "enemy spawner script did not load"
	var player_node: Node = PLAYER_SCENE.instantiate()
	if not player_node is CharacterBody2D:
		player_node.free()
		return "player scene root is not CharacterBody2D"
	if player_node.get_script() == null or not player_node.has_method("_physics_process"):
		player_node.free()
		return "player script did not load with _physics_process()"
	var weapon_node: Node = player_node.get_node_or_null("Weapon")
	if weapon_node == null or weapon_node.get_script() == null:
		player_node.free()
		return "player Weapon script did not load"
	if not weapon_node.has_method("try_fire"):
		player_node.free()
		return "player Weapon is missing try_fire()"
	var projectile_scene_value: Variant = weapon_node.get("projectile_scene")
	if not projectile_scene_value is PackedScene:
		player_node.free()
		return "player Weapon projectile scene did not load"
	var projectile_node: Node = (projectile_scene_value as PackedScene).instantiate()
	if projectile_node.get_script() == null or not projectile_node.has_method("launch"):
		projectile_node.free()
		player_node.free()
		return "projectile script did not load with launch()"
	projectile_node.free()
	player_node.free()

	var enemy_node: Node = ENEMY_SCENE.instantiate()
	if not enemy_node is CharacterBody2D:
		enemy_node.free()
		return "enemy scene root is not CharacterBody2D"
	if enemy_node.get_script() == null or not enemy_node.has_method("_physics_process"):
		enemy_node.free()
		return "enemy script did not load with _physics_process()"
	enemy_node.free()

	var spawner_node: Node = ENEMY_SPAWNER_SCRIPT.new() as Node
	if spawner_node == null or spawner_node.get_script() == null:
		if spawner_node != null:
			spawner_node.free()
		return "enemy spawner script did not load"
	if not spawner_node.has_method("spawn_one"):
		spawner_node.free()
		return "enemy spawner is missing spawn_one()"
	spawner_node.free()
	return ""


func _finish_suite() -> void:
	var recorded_count := passed_count + failed_count + skipped_count
	var has_all_cases := recorded_count == EXPECTED_CASE_COUNT
	if not has_all_cases:
		print(
			"TEST_ERROR missing_cases expected=%d recorded=%d"
			% [EXPECTED_CASE_COUNT, recorded_count]
		)
	var all_passed := passed_count > 0 and failed_count == 0 and has_all_cases
	print(
		"TEST_RESULT %s passed=%d failed=%d skipped=%d"
		% [_verdict(all_passed), passed_count, failed_count, skipped_count]
	)
	get_tree().quit(0 if all_passed else 1)


func _test_periodic_spawning() -> void:
	var setup := _create_setup(PERIODIC_INTERVAL, 30)
	var container: Node2D = setup["container"] as Node2D

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
	var spawner: Node = setup["spawner"] as Node
	var design_screen_size := _design_screen_size()
	var screen_center := design_screen_size / 2.0
	var inside_count := 0
	var minimum_center_distance := INF

	for _spawn_index in range(OFFSCREEN_SPAWN_COUNT):
		var enemy: Node2D = spawner.call("spawn_one") as Node2D
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
		inside_count == 0 and minimum_center_distance > MEASUREMENT_EPSILON,
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
	var player: CharacterBody2D = setup["player"] as CharacterBody2D
	var spawner: Node = setup["spawner"] as Node
	player.global_position = _design_screen_size() / 2.0
	var enemy: CharacterBody2D = spawner.call("spawn_one") as CharacterBody2D

	if enemy == null:
		_record_case(
			"enemies_chase_player",
			false,
			"enemy_spawned=false initial_distance=0.000 final_distance=0.000 expected_delta=0.000"
		)
		await _free_setup(setup)
		return

	var initial_distance := enemy.global_position.distance_to(player.global_position)
	var enemy_speed: float = float(enemy.get("speed"))
	var expected_delta := (
		enemy_speed * CHASE_FRAMES / float(Engine.physics_ticks_per_second)
	)
	await _advance_physics(CHASE_FRAMES)
	var final_distance := enemy.global_position.distance_to(player.global_position)
	var actual_delta := initial_distance - final_distance
	var tolerance := expected_delta * CHASE_TOLERANCE
	var passed := (
		initial_distance > MEASUREMENT_EPSILON
		and expected_delta > MEASUREMENT_EPSILON
		and actual_delta > MEASUREMENT_EPSILON
		and final_distance < initial_distance
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
	var container: Node2D = setup["container"] as Node2D
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
	var projectile_container := Node2D.new()
	projectile_container.name = "ProjectileContainer"
	projectile_container.add_to_group("projectile_container")
	add_child(projectile_container)

	var player := PLAYER_SCENE.instantiate() as CharacterBody2D
	player.name = "Player"
	add_child(player)

	var container := Node2D.new()
	container.name = "EnemyContainer"
	add_child(container)

	var spawner: Node = ENEMY_SPAWNER_SCRIPT.new() as Node
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
		"projectile_container": projectile_container,
		"spawner": spawner,
	}


func _free_setup(setup: Dictionary) -> void:
	for key: String in ["spawner", "container", "player", "projectile_container"]:
		var node: Node = setup[key] as Node
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
