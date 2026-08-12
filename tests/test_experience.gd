extends Node

const EXPECTED_CASE_COUNT: int = 5
const FRAME_LIMIT: int = 90
const EPSILON: float = 0.01

var passed: int = 0
var failed: int = 0
var skipped: int = 0
var recorded: int = 0

var player_scene: PackedScene = null
var enemy_scene: PackedScene = null
var gem_scene: PackedScene = null
var pickup_spawner_script: Script = null
var level_system_script: Script = null


func _ready() -> void:
	if not _validate_dependencies():
		get_tree().quit(1)
		return
	await _run_cases()
	if recorded != EXPECTED_CASE_COUNT:
		failed += 1
		print("TEST_ERROR missing_cases expected=%d recorded=%d" % [EXPECTED_CASE_COUNT, recorded])
	var result: String = "PASS" if failed == 0 and passed > 0 else "FAIL"
	print("TEST_RESULT %s passed=%d failed=%d skipped=%d" % [result, passed, failed, skipped])
	get_tree().quit(0 if result == "PASS" else 1)


func _validate_dependencies() -> bool:
	var player_resource: Resource = load("res://scenes/player.tscn")
	var enemy_resource: Resource = load("res://scenes/enemy.tscn")
	var gem_resource: Resource = load("res://scenes/xp_gem.tscn")
	var pickup_spawner_resource: Resource = load("res://scripts/pickup_spawner.gd")
	var level_system_resource: Resource = load("res://scripts/level_system.gd")
	player_scene = player_resource as PackedScene
	enemy_scene = enemy_resource as PackedScene
	gem_scene = gem_resource as PackedScene
	pickup_spawner_script = pickup_spawner_resource as Script
	level_system_script = level_system_resource as Script
	if player_scene == null:
		print("TEST_ERROR setup_failed player_scene missing")
		return false
	if enemy_scene == null:
		print("TEST_ERROR setup_failed enemy_scene missing")
		return false
	if gem_scene == null:
		print("TEST_ERROR setup_failed gem_scene missing")
		return false
	if pickup_spawner_script == null or level_system_script == null:
		print("TEST_ERROR setup_failed required script missing")
		return false
	return true


func _run_cases() -> void:
	await _case_death_drops_gem()
	await _case_out_of_range_gem_does_not_move()
	await _case_in_range_gem_is_collected()
	_case_level_curve()
	_case_multiple_levels_from_one_grant()


func _case_death_drops_gem() -> void:
	var container: Node2D = Node2D.new()
	var spawner: Node = pickup_spawner_script.new()
	spawner.set("gem_scene", gem_scene)
	spawner.set("gem_container_path", NodePath("../PickupContainer"))
	container.name = "PickupContainer"
	add_child(container)
	add_child(spawner)
	await get_tree().process_frame

	var enemy: Node2D = enemy_scene.instantiate() as Node2D
	enemy.global_position = Vector2(123.0, 45.0)
	add_child(enemy)
	var died_signal: Signal = enemy.get("died")
	died_signal.connect(Callable(spawner, "on_enemy_died"))
	var expected_position: Vector2 = enemy.global_position
	enemy.call("take_damage", 9999.0)
	await get_tree().process_frame

	var gem_count: int = container.get_child_count()
	var position_delta: float = -1.0
	if gem_count == 1 and container.get_child(0) is Node2D:
		position_delta = (container.get_child(0) as Node2D).global_position.distance_to(expected_position)
	var ok: bool = gem_count == 1 and position_delta <= EPSILON
	_case_result("death_drops_gem", ok, "gem_count=%d position_delta=%.3f" % [gem_count, position_delta])
	if is_instance_valid(enemy):
		enemy.queue_free()
	if is_instance_valid(spawner):
		spawner.queue_free()
	if is_instance_valid(container):
		container.queue_free()
	await get_tree().process_frame


func _case_out_of_range_gem_does_not_move() -> void:
	var player: Node2D = player_scene.instantiate() as Node2D
	var gem: Node2D = gem_scene.instantiate() as Node2D
	player.global_position = Vector2.ZERO
	gem.global_position = Vector2(500.0, 0.0)
	add_child(player)
	add_child(gem)
	var baseline_distance: float = gem.global_position.distance_to(player.global_position)
	var start_position: Vector2 = gem.global_position
	for _frame: int in 12:
		await get_tree().physics_frame
	var displacement: float = gem.global_position.distance_to(start_position)
	var measured_distance: float = gem.global_position.distance_to(player.global_position)
	var gem_target: Variant = gem.get("target")
	var ok: bool = baseline_distance > 0.0 and measured_distance > 0.0 and displacement <= EPSILON and gem_target == null
	_case_result("out_of_range_gem_does_not_move", ok, "distance=%.3f displacement=%.3f" % [measured_distance, displacement])
	if is_instance_valid(gem):
		gem.queue_free()
	if is_instance_valid(player):
		player.queue_free()
	await get_tree().process_frame


func _case_in_range_gem_is_collected() -> void:
	var player: Node2D = player_scene.instantiate() as Node2D
	var gem: Node2D = gem_scene.instantiate() as Node2D
	player.global_position = Vector2.ZERO
	gem.global_position = Vector2(50.0, 0.0)
	add_child(player)
	add_child(gem)
	var level_system: Node = player.get_node_or_null("LevelSystem")
	var before: float = float(level_system.get("experience")) if level_system != null else -1.0
	var frames_taken: int = -1
	for frame in range(FRAME_LIMIT):
		await get_tree().physics_frame
		if not is_instance_valid(gem):
			frames_taken = frame + 1
			break
	var after: float = float(level_system.get("experience")) if level_system != null else -1.0
	var ok: bool = before >= 0.0 and after > before and frames_taken > 0
	_case_result("in_range_gem_is_collected", ok, "frames=%d experience_before=%.3f experience_after=%.3f" % [frames_taken, before, after])
	if is_instance_valid(gem):
		gem.queue_free()
	if is_instance_valid(player):
		player.queue_free()
	await get_tree().process_frame


func _case_level_curve() -> void:
	var level_system: Node = level_system_script.new()
	level_system.call("add_experience", 5.0)
	var first_level: int = int(level_system.get("level"))
	var first_experience: float = float(level_system.get("experience"))
	var first_ok: bool = first_level == 2 and is_zero_approx(first_experience)
	var first_detail: String = "after_5 level=%d remainder=%.3f" % [first_level, first_experience]
	level_system.call("add_experience", 9.0)
	var second_level: int = int(level_system.get("level"))
	var second_experience: float = float(level_system.get("experience"))
	var second_ok: bool = second_level == 3 and is_equal_approx(second_experience, 1.0)
	var second_detail: String = "after_9 level=%d remainder=%.3f" % [second_level, second_experience]
	_case_result("level_curve", first_ok and second_ok, "%s %s" % [first_detail, second_detail])
	if is_instance_valid(level_system):
		level_system.free()


func _case_multiple_levels_from_one_grant() -> void:
	var level_system: Node = level_system_script.new()
	var level_up_count: Array[int] = [0]
	var level_up_signal: Signal = level_system.get("leveled_up")
	level_up_signal.connect(func(_new_level: int) -> void: level_up_count[0] += 1)
	level_system.call("add_experience", 30.0)
	var reached_level: int = int(level_system.get("level"))
	var remainder: float = float(level_system.get("experience"))
	var ok: bool = reached_level == 4 and is_equal_approx(remainder, 6.0) and level_up_count[0] == 3
	_case_result("multiple_levels_from_one_grant", ok, "level=%d remainder=%.3f level_up_signals=%d" % [reached_level, remainder, level_up_count[0]])
	if is_instance_valid(level_system):
		level_system.free()


func _case_result(case_name: String, ok: bool, detail: String) -> void:
	recorded += 1
	if ok:
		passed += 1
		print("TEST_CASE %s PASS %s" % [case_name, detail])
	else:
		failed += 1
		print("TEST_CASE %s FAIL %s" % [case_name, detail])
