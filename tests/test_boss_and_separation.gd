extends Node


const EXPECTED_CASE_COUNT: int = 6
const ENEMY_SCRIPT: Script = preload("res://scripts/enemy.gd")
const BOSS_SPAWNER_SCRIPT: Script = preload("res://scripts/boss_spawner.gd")
const EPSILON: float = 0.01

var _passed: int = 0
var _failed: int = 0
var _skipped: int = 0


func _ready() -> void:
	call_deferred("_run_suite")


func _run_suite() -> void:
	if ENEMY_SCRIPT == null or BOSS_SPAWNER_SCRIPT == null:
		print("TEST_ERROR setup_failed required script could not be loaded")
		_finish_with_failure()
		return

	await _case_boss_spawns_exactly_once()
	await _case_boss_stats_are_applied()
	await _case_boss_spawns_off_screen()
	await _case_overlapping_enemies_push_apart()
	await _case_separation_keeps_chasing()
	await _case_separation_can_be_disabled()

	var recorded: int = _passed + _failed + _skipped
	if recorded != EXPECTED_CASE_COUNT:
		print("TEST_ERROR missing_cases expected=" + str(EXPECTED_CASE_COUNT) + " recorded=" + str(recorded))
		_finish_with_failure()
		return
	var overall_pass: bool = _failed == 0 and _passed > 0
	print("TEST_RESULT " + ("PASS" if overall_pass else "FAIL") + " passed=" + str(_passed) + " failed=" + str(_failed) + " skipped=" + str(_skipped))
	get_tree().quit(0 if overall_pass else 1)


func _case_boss_spawns_exactly_once() -> void:
	var world: Node2D = Node2D.new()
	var container: Node2D = Node2D.new()
	container.name = "EnemyContainer"
	var target: Node2D = Node2D.new()
	target.name = "Target"
	target.global_position = Vector2(640.0, 360.0)
	world.add_child(container)
	world.add_child(target)
	var spawner: Node = _make_boss_spawner(0.03, container, target)
	world.add_child(spawner)
	add_child(world)
	await _wait_physics_frames(12)
	var first_count: int = _count_bosses(container)
	var spawned: bool = bool(spawner.call("has_spawned"))
	await _wait_physics_frames(180)
	var later_count: int = _count_bosses(container)
	_record_case("boss_spawns_exactly_once", first_count == 1 and later_count == 1 and spawned, "first=" + str(first_count) + " later=" + str(later_count) + " spawned=" + str(spawned))
	await _free_world(world)


func _case_boss_stats_are_applied() -> void:
	var world: Node2D = Node2D.new()
	var container: Node2D = Node2D.new()
	container.name = "EnemyContainer"
	var target: Node2D = Node2D.new()
	target.name = "Target"
	world.add_child(container)
	world.add_child(target)
	var spawner: Node = _make_boss_spawner(300.0, container, target)
	spawner.set("boss_health", 321.0)
	spawner.set("boss_speed", 47.0)
	spawner.set("boss_contact_damage", 19.0)
	spawner.set("boss_scale", 2.5)
	world.add_child(spawner)
	add_child(world)
	var boss: Node = spawner.call("spawn_boss_now")
	await get_tree().process_frame
	var observed_health: float = -1.0
	var observed_speed: float = -1.0
	var observed_damage: float = -1.0
	var observed_scale: float = -1.0
	if boss != null and is_instance_valid(boss):
		observed_health = float(boss.get("health"))
		observed_speed = float(boss.get("speed"))
		observed_damage = float(boss.get("contact_damage"))
		var boss_body: Node2D = boss as Node2D
		if boss_body != null:
			observed_scale = boss_body.scale.x
	var correct: bool = is_equal_approx(observed_health, 321.0) and is_equal_approx(observed_speed, 47.0) and is_equal_approx(observed_damage, 19.0) and is_equal_approx(observed_scale, 2.5)
	_record_case("boss_stats_are_applied", correct, "health=" + str(observed_health) + " configured=321.0 speed=" + str(observed_speed) + " damage=" + str(observed_damage) + " scale=" + str(observed_scale))
	await _free_world(world)


func _case_boss_spawns_off_screen() -> void:
	var world: Node2D = Node2D.new()
	var container: Node2D = Node2D.new()
	container.name = "EnemyContainer"
	var target: Node2D = Node2D.new()
	target.name = "Target"
	world.add_child(container)
	world.add_child(target)
	var spawner: Node = _make_boss_spawner(300.0, container, target)
	world.add_child(spawner)
	add_child(world)
	var boss: Node = spawner.call("spawn_boss_now")
	await get_tree().process_frame
	var viewport_width: float = float(ProjectSettings.get_setting("display/window/size/viewport_width"))
	var viewport_height: float = float(ProjectSettings.get_setting("display/window/size/viewport_height"))
	var design_size: Vector2 = Vector2(viewport_width, viewport_height)
	var design_rect: Rect2 = Rect2(Vector2.ZERO, design_size)
	var boss_position: Vector2 = Vector2.ZERO
	if boss is Node2D:
		var boss_body: Node2D = boss
		boss_position = boss_body.global_position
	var distance_from_centre: float = boss_position.distance_to(design_size / 2.0)
	_record_case("boss_spawns_off_screen", boss != null and not design_rect.has_point(boss_position), "distance_from_centre=" + str(distance_from_centre))
	await _free_world(world)


func _case_overlapping_enemies_push_apart() -> void:
	var world: Node2D = Node2D.new()
	var target: Node2D = Node2D.new()
	target.global_position = Vector2(1000.0, 500.0)
	world.add_child(target)
	var enemy_scene: PackedScene = _make_enemy_scene()
	var first: CharacterBody2D = _make_separating_enemy(enemy_scene, target, Vector2(0.0, 0.0), 1.0)
	var second: CharacterBody2D = _make_separating_enemy(enemy_scene, target, Vector2(1.0, 0.0), 1.0)
	world.add_child(first)
	world.add_child(second)
	add_child(world)
	var before: float = first.global_position.distance_to(second.global_position)
	await _wait_physics_frames(80)
	var after: float = first.global_position.distance_to(second.global_position)
	_record_case("overlapping_enemies_push_apart", after > before and after >= 26.0 * 0.45, "before=" + str(before) + " after=" + str(after))
	await _free_world(world)


func _case_separation_keeps_chasing() -> void:
	var world: Node2D = Node2D.new()
	var target: Node2D = Node2D.new()
	target.global_position = Vector2(700.0, 400.0)
	world.add_child(target)
	var enemy_scene: PackedScene = _make_enemy_scene()
	var enemies: Array[CharacterBody2D] = []
	var positions: Array[Vector2] = [Vector2(-8.0, -4.0), Vector2(8.0, -4.0), Vector2(0.0, 0.0), Vector2(-4.0, 8.0), Vector2(5.0, 7.0)]
	for enemy_position in positions:
		var enemy: CharacterBody2D = _make_separating_enemy(enemy_scene, target, enemy_position, 1.0)
		enemies.append(enemy)
		world.add_child(enemy)
	add_child(world)
	var before: float = _average_distance_to_target(enemies, target)
	await _wait_physics_frames(120)
	var after: float = _average_distance_to_target(enemies, target)
	_record_case("separation_keeps_chasing", after < before, "average_before=" + str(before) + " average_after=" + str(after))
	await _free_world(world)


func _case_separation_can_be_disabled() -> void:
	var world: Node2D = Node2D.new()
	var target: Node2D = Node2D.new()
	target.global_position = Vector2(1000.0, 500.0)
	world.add_child(target)
	var enemy_scene: PackedScene = _make_enemy_scene()
	var first: CharacterBody2D = _make_separating_enemy(enemy_scene, target, Vector2.ZERO, 0.0)
	var second: CharacterBody2D = _make_separating_enemy(enemy_scene, target, Vector2.ZERO, 0.0)
	world.add_child(first)
	world.add_child(second)
	add_child(world)
	var before: float = first.global_position.distance_to(second.global_position)
	await _wait_physics_frames(40)
	var after: float = first.global_position.distance_to(second.global_position)
	var delta: float = absf(after - before)
	_record_case("separation_can_be_disabled", delta <= EPSILON, "distance_delta=" + str(delta))
	await _free_world(world)


func _make_boss_spawner(spawn_delay: float, container: Node2D, target: Node2D) -> Node:
	var spawner: Node = Node.new()
	spawner.set_script(BOSS_SPAWNER_SCRIPT)
	spawner.set("enemy_scene", _make_enemy_scene())
	spawner.set("spawn_time", spawn_delay)
	spawner.set("enemy_container_path", NodePath("../EnemyContainer"))
	spawner.set("target_path", NodePath("../Target"))
	return spawner


func _make_enemy_scene() -> PackedScene:
	var prototype: CharacterBody2D = CharacterBody2D.new()
	prototype.set_script(ENEMY_SCRIPT)
	var sprite: ColorRect = ColorRect.new()
	sprite.name = "Sprite"
	sprite.size = Vector2(16.0, 16.0)
	sprite.position = Vector2(-8.0, -8.0)
	prototype.add_child(sprite)
	sprite.owner = prototype
	var scene: PackedScene = PackedScene.new()
	var pack_result: Error = scene.pack(prototype)
	if pack_result != OK:
		print("TEST_ERROR setup_failed enemy test scene pack error=" + str(pack_result))
		prototype.free()
		return null
	prototype.free()
	return scene


func _make_separating_enemy(scene: PackedScene, target: Node2D, enemy_position: Vector2, weight: float) -> CharacterBody2D:
	var enemy: CharacterBody2D = scene.instantiate() as CharacterBody2D
	enemy.global_position = enemy_position
	enemy.set("target", target)
	enemy.set("speed", 60.0)
	enemy.set("separation_radius", 26.0)
	enemy.set("separation_weight", weight)
	enemy.set("separation_update_interval", 1)
	enemy.set("separation_max_neighbours", 12)
	enemy.add_to_group(&"enemies")
	return enemy


func _count_bosses(container: Node) -> int:
	var count: int = 0
	for child in container.get_children():
		if StringName(child.get("variant_id")) == &"boss":
			count += 1
	return count


func _average_distance_to_target(enemies: Array[CharacterBody2D], target: Node2D) -> float:
	if enemies.is_empty():
		return 0.0
	var total: float = 0.0
	for enemy in enemies:
		total += enemy.global_position.distance_to(target.global_position)
	return total / float(enemies.size())


func _wait_physics_frames(frame_count: int) -> void:
	for frame_index in range(frame_count):
		await get_tree().physics_frame


func _free_world(world: Node) -> void:
	if is_instance_valid(world):
		world.queue_free()
	await get_tree().process_frame


func _record_case(case_name: String, did_pass: bool, detail: String) -> void:
	if did_pass:
		_passed += 1
		print("TEST_CASE " + case_name + " PASS " + detail)
	else:
		_failed += 1
		print("TEST_CASE " + case_name + " FAIL " + detail)


func _finish_with_failure() -> void:
	var recorded: int = _passed + _failed + _skipped
	if recorded != EXPECTED_CASE_COUNT:
		print("TEST_ERROR missing_cases expected=" + str(EXPECTED_CASE_COUNT) + " recorded=" + str(recorded))
	print("TEST_RESULT FAIL passed=" + str(_passed) + " failed=" + str(maxi(1, _failed)) + " skipped=" + str(_skipped))
	get_tree().quit(1)
