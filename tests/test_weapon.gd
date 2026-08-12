extends Node2D


const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const PROJECTILE_SCENE := preload("res://scenes/projectile.tscn")
const WEAPON_SCRIPT := preload("res://scripts/weapon.gd")
const HIT_MAX_FRAMES := 60
const MISS_LIFETIME := 0.1
const MISS_EXTRA_FRAMES := 3
const GROWTH_COOLDOWN := 0.25
const GROWTH_SECONDS := 5.0
const GROWTH_BOUND := 20

var passed_count := 0
var failed_count := 0
var skipped_count := 0


func _ready() -> void:
	await _test_no_enemies_no_shot()
	await _test_nearest_target_chosen()
	await _test_out_of_range_not_targeted()
	await _test_in_range_boundary()
	await _test_hit_damages_and_kills()
	await _test_miss_despawns()
	await _test_no_unbounded_growth()

	var all_passed := failed_count == 0
	print(
		"TEST_RESULT %s passed=%d failed=%d skipped=%d"
		% [_verdict(all_passed), passed_count, failed_count, skipped_count]
	)
	get_tree().quit(0 if all_passed else 1)


func _test_no_enemies_no_shot() -> void:
	var setup := _create_setup(3600.0, 5.0)
	var weapon := setup["weapon"] as Node2D
	var container := setup["projectile_container"] as Node2D
	var projectile := weapon.call("try_fire") as Node
	var child_count := container.get_child_count()
	_record_case(
		"no_enemies_no_shot",
		projectile == null and child_count == 0,
		"projectile_is_null=%s child_count=%d" % [projectile == null, child_count]
	)
	await _free_setup(setup)


func _test_nearest_target_chosen() -> void:
	var setup := _create_setup(3600.0, 5.0)
	var player := setup["player"] as Node2D
	var weapon := setup["weapon"] as Node
	var enemy_container := setup["enemy_container"] as Node2D
	var enemy_a := _create_enemy(enemy_container, player.global_position + Vector2(300.0, 0.0))
	var enemy_b := _create_enemy(enemy_container, player.global_position + Vector2(40.0, 0.0))
	var enemy_c := _create_enemy(enemy_container, player.global_position + Vector2(180.0, 0.0))
	var distance_a := player.global_position.distance_to(enemy_a.global_position)
	var distance_b := player.global_position.distance_to(enemy_b.global_position)
	var distance_c := player.global_position.distance_to(enemy_c.global_position)
	var chosen := weapon.call("find_nearest_enemy") as Node2D
	var chosen_name := chosen.name if chosen != null else &"none"
	_record_case(
		"nearest_target_chosen",
		chosen == enemy_b,
		"distance_a=%.3f distance_b=%.3f distance_c=%.3f chosen=%s"
		% [distance_a, distance_b, distance_c, chosen_name]
	)
	await _free_setup(setup)


func _test_out_of_range_not_targeted() -> void:
	var setup := _create_setup(3600.0, 5.0)
	var player := setup["player"] as Node2D
	var weapon := setup["weapon"] as Node2D
	var enemy_container := setup["enemy_container"] as Node2D
	var container := setup["projectile_container"] as Node2D
	var enemy := _create_enemy(
		enemy_container,
		player.global_position + Vector2(900.0, 0.0)
	)
	var distance := weapon.global_position.distance_to(enemy.global_position)
	var attack_range: float = weapon.get("attack_range")
	var chosen := weapon.call("find_nearest_enemy") as Node2D
	var projectile := weapon.call("try_fire") as Node
	var child_count := container.get_child_count()
	_record_case(
		"out_of_range_not_targeted",
		chosen == null and projectile == null and child_count == 0,
		(
			"distance=%.3f attack_range=%.3f target_is_null=%s "
			+ "projectile_is_null=%s child_count=%d"
		)
		% [distance, attack_range, chosen == null, projectile == null, child_count]
	)
	await _free_setup(setup)


func _test_in_range_boundary() -> void:
	var setup := _create_setup(3600.0, 5.0)
	var player := setup["player"] as Node2D
	var weapon := setup["weapon"] as Node2D
	var enemy_container := setup["enemy_container"] as Node2D
	var attack_range: float = weapon.get("attack_range")
	var enemy := _create_enemy(
		enemy_container,
		player.global_position + Vector2(attack_range, 0.0)
	)
	var distance := weapon.global_position.distance_to(enemy.global_position)
	var chosen := weapon.call("find_nearest_enemy") as Node2D
	_record_case(
		"in_range_boundary",
		chosen == enemy,
		"distance=%.3f attack_range=%.3f targeted=%s"
		% [distance, attack_range, chosen == enemy]
	)
	await _free_setup(setup)


func _test_hit_damages_and_kills() -> void:
	var setup := _create_setup(3600.0, 10.0)
	var player := setup["player"] as Node2D
	var weapon := setup["weapon"] as Node
	var enemy_container := setup["enemy_container"] as Node2D
	var enemy := _create_enemy(
		enemy_container,
		player.global_position + Vector2(80.0, 0.0),
		10.0,
		player
	)
	var projectile := weapon.call("try_fire") as Node
	var shot_created := projectile != null
	var frames_elapsed := 0

	while frames_elapsed < HIT_MAX_FRAMES:
		await get_tree().physics_frame
		frames_elapsed += 1
		if not is_instance_valid(enemy) and not is_instance_valid(projectile):
			break

	var enemy_valid := is_instance_valid(enemy)
	var projectile_valid := is_instance_valid(projectile)
	_record_case(
		"hit_damages_and_kills",
		shot_created and not enemy_valid and not projectile_valid,
		(
			"frames_elapsed=%d enemy_valid=%s projectile_valid=%s "
			+ "max_health=10.000 damage=10.000 hits_needed=1"
		)
		% [frames_elapsed, enemy_valid, projectile_valid]
	)
	await _free_setup(setup)


func _test_miss_despawns() -> void:
	var setup := _create_setup(3600.0, 5.0)
	var container := setup["projectile_container"] as Node2D
	var projectile := PROJECTILE_SCENE.instantiate() as Area2D
	projectile.set("lifetime", MISS_LIFETIME)
	container.add_child(projectile)
	projectile.call("launch", Vector2(100.0, 100.0), Vector2.UP)
	var frames_to_advance := (
		ceili(MISS_LIFETIME * float(Engine.physics_ticks_per_second))
		+ MISS_EXTRA_FRAMES
	)
	await _advance_physics(frames_to_advance)
	var projectile_valid := is_instance_valid(projectile)
	_record_case(
		"miss_despawns",
		not projectile_valid,
		"lifetime=%.3f frames_advanced=%d projectile_valid=%s"
		% [MISS_LIFETIME, frames_to_advance, projectile_valid]
	)
	await _free_setup(setup)


func _test_no_unbounded_growth() -> void:
	var setup := _create_setup(GROWTH_COOLDOWN, 5.0)
	var player := setup["player"] as Node2D
	var enemy_container := setup["enemy_container"] as Node2D
	var container := setup["projectile_container"] as Node2D
	_create_enemy(
		enemy_container,
		player.global_position + Vector2(300.0, 0.0),
		10000.0
	)
	var frame_count := ceili(GROWTH_SECONDS * float(Engine.physics_ticks_per_second))
	var peak_count := 0

	for _frame in range(frame_count):
		await get_tree().physics_frame
		peak_count = maxi(peak_count, container.get_child_count())

	var final_count := container.get_child_count()
	_record_case(
		"no_unbounded_growth",
		peak_count < GROWTH_BOUND,
		"peak_count=%d final_count=%d bound=%d seconds=%.3f cooldown=%.3f"
		% [peak_count, final_count, GROWTH_BOUND, GROWTH_SECONDS, GROWTH_COOLDOWN]
	)
	await _free_setup(setup)


func _create_setup(cooldown: float, projectile_damage: float) -> Dictionary:
	var player := Node2D.new()
	player.name = "Player"
	player.position = Vector2(200.0, 200.0)
	add_child(player)

	var enemy_container := Node2D.new()
	enemy_container.name = "EnemyContainer"
	add_child(enemy_container)

	var projectile_container := Node2D.new()
	projectile_container.name = "ProjectileContainer"
	projectile_container.add_to_group("projectile_container")
	add_child(projectile_container)

	var weapon := WEAPON_SCRIPT.new()
	weapon.name = "Weapon"
	weapon.set("cooldown", cooldown)
	weapon.set("projectile_scene", PROJECTILE_SCENE)
	weapon.set("projectile_damage", projectile_damage)
	player.add_child(weapon)

	return {
		"player": player,
		"enemy_container": enemy_container,
		"projectile_container": projectile_container,
		"weapon": weapon,
	}


func _create_enemy(
	container: Node2D,
	spawn_position: Vector2,
	max_health: float = 10.0,
	target: Node2D = null
) -> CharacterBody2D:
	var enemy := ENEMY_SCENE.instantiate() as CharacterBody2D
	enemy.set("max_health", max_health)
	enemy.set("target", target)
	container.add_child(enemy)
	enemy.global_position = spawn_position
	enemy.add_to_group("enemies")
	return enemy


func _free_setup(setup: Dictionary) -> void:
	for key: String in ["projectile_container", "enemy_container", "player"]:
		var node := setup[key] as Node
		if is_instance_valid(node):
			node.queue_free()
	await get_tree().process_frame


func _advance_physics(frame_count: int) -> void:
	for _frame in range(frame_count):
		await get_tree().physics_frame


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
