extends Node2D


const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const EXPECTED_CASE_COUNT := 5
const CONTACT_DAMAGE := 5.0
const DEFAULT_INVINCIBILITY := 0.5
const TEST_INVINCIBILITY := 0.25
const CONTACT_TIMEOUT_FRAMES := 8
const BLOCKED_FRAMES := 4
const DEATH_ENEMY_COUNT := 3
const DEATH_SURVIVAL_FRAMES := 6
const MEASUREMENT_EPSILON := 0.001

var passed_count := 0
var failed_count := 0
var skipped_count := 0
var _death_signal_count := 0


func _ready() -> void:
	var setup_error: String = _validate_dependencies()
	if not setup_error.is_empty():
		print("TEST_ERROR setup_failed %s" % setup_error)
		get_tree().quit(1)
		return

	await _test_contact_deals_damage()
	await _test_invincibility_and_resume()
	await _test_death_at_zero()
	await _test_enemies_survive_player_death()

	_finish_suite()


func _validate_dependencies() -> String:
	if PLAYER_SCENE == null:
		return "player scene did not load"
	if ENEMY_SCENE == null:
		return "enemy scene did not load"
	var player_node: Node = PLAYER_SCENE.instantiate()
	if not player_node is CharacterBody2D:
		player_node.free()
		return "player scene root is not CharacterBody2D"
	if player_node.get_script() == null:
		player_node.free()
		return "player script did not load"
	if not player_node.has_method("take_damage"):
		player_node.free()
		return "player is missing take_damage()"
	if not player_node.has_method("advance_invincibility"):
		player_node.free()
		return "player is missing advance_invincibility()"
	if not player_node.get_node_or_null("Hurtbox") is Area2D:
		player_node.free()
		return "player Hurtbox Area2D is missing"
	player_node.free()

	var enemy_node: Node = ENEMY_SCENE.instantiate()
	if not enemy_node is CharacterBody2D:
		enemy_node.free()
		return "enemy scene root is not CharacterBody2D"
	if enemy_node.get_script() == null or not ("contact_damage" in enemy_node):
		enemy_node.free()
		return "enemy script did not load with contact_damage"
	enemy_node.free()
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


func _test_contact_deals_damage() -> void:
	var setup := _create_setup(DEFAULT_INVINCIBILITY)
	var player: CharacterBody2D = setup["player"] as CharacterBody2D
	var container: Node2D = setup["enemy_container"] as Node2D
	var before: float = float(player.get("health"))
	var enemy := _create_enemy(container, player, player.global_position, CONTACT_DAMAGE)

	var hit_frame: int = await _wait_for_damage(player, before, CONTACT_TIMEOUT_FRAMES)
	var after: float = float(player.get("health"))
	var enemy_damage: float = float(enemy.get("contact_damage"))
	var expected := before - enemy_damage
	_record_case(
		"contact_deals_damage",
		hit_frame <= CONTACT_TIMEOUT_FRAMES
		and enemy_damage > MEASUREMENT_EPSILON
		and before - after > MEASUREMENT_EPSILON
		and is_equal_approx(after, expected),
		(
			"before=%.3f after=%.3f contact_damage=%.3f "
			+ "frame_to_hit=%d timeout_frames=%d"
		)
		% [before, after, enemy_damage, hit_frame, CONTACT_TIMEOUT_FRAMES]
	)
	await _free_setup(setup)


func _test_invincibility_and_resume() -> void:
	var setup := _create_setup(TEST_INVINCIBILITY)
	var player: CharacterBody2D = setup["player"] as CharacterBody2D
	var container: Node2D = setup["enemy_container"] as Node2D
	var initial_health: float = float(player.get("health"))
	_create_enemy(container, player, player.global_position, CONTACT_DAMAGE)

	var first_hit_frames: int = await _wait_for_damage(
		player,
		initial_health,
		CONTACT_TIMEOUT_FRAMES
	)
	var health_after_first: float = float(player.get("health"))
	await _advance_physics(BLOCKED_FRAMES)
	var health_inside_window: float = float(player.get("health"))
	_record_case(
		"invincibility_blocks_repeat_damage",
		CONTACT_DAMAGE > MEASUREMENT_EPSILON
		and first_hit_frames <= CONTACT_TIMEOUT_FRAMES
		and is_equal_approx(health_after_first, initial_health - CONTACT_DAMAGE)
		and is_equal_approx(health_inside_window, health_after_first),
		(
			"frames_to_first_hit=%d frames_advanced=%d invincibility_window=%.3f "
			+ "health=%.3f"
		)
		% [first_hit_frames, BLOCKED_FRAMES, TEST_INVINCIBILITY, health_inside_window]
	)

	var resume_timeout := (
		ceili(TEST_INVINCIBILITY * float(Engine.physics_ticks_per_second))
		+ CONTACT_TIMEOUT_FRAMES
	)
	var resume_frames: int = await _wait_for_damage(
		player,
		health_after_first,
		resume_timeout
	)
	var health_after_second: float = float(player.get("health"))
	_record_case(
		"damage_resumes_after_invincibility",
		resume_frames <= resume_timeout
		and is_equal_approx(health_after_second, initial_health - CONTACT_DAMAGE * 2.0),
		(
			"frames_advanced=%d invincibility_window=%.3f before=%.3f after=%.3f "
			+ "expected=%.3f"
		)
		% [
			BLOCKED_FRAMES + resume_frames,
			TEST_INVINCIBILITY,
			health_after_first,
			health_after_second,
			initial_health - CONTACT_DAMAGE * 2.0,
		]
	)
	await _free_setup(setup)


func _test_death_at_zero() -> void:
	var setup := _create_setup(DEFAULT_INVINCIBILITY)
	var player: CharacterBody2D = setup["player"] as CharacterBody2D
	_death_signal_count = 0
	player.connect(
		&"died",
		func() -> void:
			_death_signal_count += 1
	)
	player.set("health", CONTACT_DAMAGE)
	player.call("take_damage", CONTACT_DAMAGE)
	var health_at_death: float = float(player.get("health"))
	player.call("advance_invincibility", DEFAULT_INVINCIBILITY + 0.1)
	player.call("take_damage", CONTACT_DAMAGE)
	var health_after_extra_damage: float = float(player.get("health"))

	_record_case(
		"death_at_zero",
		is_equal_approx(health_at_death, 0.0)
		and is_equal_approx(health_after_extra_damage, 0.0)
		and _death_signal_count == 1,
		"health=%.3f health_after_extra_damage=%.3f signal_count=%d"
		% [health_at_death, health_after_extra_damage, _death_signal_count]
	)
	await _free_setup(setup)


func _test_enemies_survive_player_death() -> void:
	var setup := _create_setup(DEFAULT_INVINCIBILITY)
	var player: CharacterBody2D = setup["player"] as CharacterBody2D
	var container: Node2D = setup["enemy_container"] as Node2D
	var enemies: Array[Node] = []

	for enemy_index in range(DEATH_ENEMY_COUNT):
		var enemy_position := player.global_position + Vector2(500.0 + enemy_index * 20.0, 0.0)
		enemies.append(_create_enemy(container, player, enemy_position, CONTACT_DAMAGE))

	var before_count := _count_valid(enemies)
	player.set("health", 1.0)
	player.call("take_damage", 1.0)
	await _advance_physics(DEATH_SURVIVAL_FRAMES)
	var after_count := _count_valid(enemies)
	var completed_without_error := true

	_record_case(
		"enemies_survive_player_death",
		is_instance_valid(player)
		and before_count == DEATH_ENEMY_COUNT
		and after_count == before_count
		and completed_without_error,
		"enemy_count_before=%d enemy_count_after=%d frames_advanced=%d completed_without_error=%s"
		% [before_count, after_count, DEATH_SURVIVAL_FRAMES, completed_without_error]
	)
	await _free_setup(setup)


func _create_setup(invincibility_window: float) -> Dictionary:
	var player := PLAYER_SCENE.instantiate() as CharacterBody2D
	player.name = "Player"
	player.set("invincibility_time", invincibility_window)
	player.collision_layer = 0
	player.collision_mask = 0
	player.global_position = _design_screen_size() / 2.0
	var weapon := player.get_node_or_null("Weapon")
	if weapon != null:
		weapon.set("cooldown", 3600.0)
	add_child(player)

	var enemy_container := Node2D.new()
	enemy_container.name = "EnemyContainer"
	add_child(enemy_container)

	return {
		"player": player,
		"enemy_container": enemy_container,
	}


func _create_enemy(
	container: Node2D,
	player: CharacterBody2D,
	spawn_position: Vector2,
	contact_damage: float
) -> CharacterBody2D:
	var enemy := ENEMY_SCENE.instantiate() as CharacterBody2D
	enemy.set("speed", 0.0)
	enemy.set("contact_damage", contact_damage)
	enemy.set("target", player)
	container.add_child(enemy)
	enemy.global_position = spawn_position
	enemy.add_to_group("enemies")
	return enemy


func _wait_for_damage(
	player: CharacterBody2D,
	starting_health: float,
	maximum_frames: int
) -> int:
	for frame_number in range(1, maximum_frames + 1):
		await get_tree().physics_frame
		if float(player.get("health")) < starting_health:
			return frame_number
	return maximum_frames + 1


func _count_valid(nodes: Array[Node]) -> int:
	var valid_count := 0
	for node: Node in nodes:
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			valid_count += 1
	return valid_count


func _free_setup(setup: Dictionary) -> void:
	for key: String in ["enemy_container", "player"]:
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
