extends Node

const EXPECTED_CASE_COUNT: int = 6
const HIT_EFFECT_SCENE: PackedScene = preload("res://scenes/hit_effect.tscn")
const EFFECT_SPAWNER_SCRIPT: Script = preload("res://scripts/effect_spawner.gd")
const SCREEN_SHAKE_SCRIPT: Script = preload("res://scripts/screen_shake.gd")
const DISABLED_PROCESS_MODE: int = 4

var _recorded_cases: int = 0
var _passed_cases: int = 0
var _failed_cases: int = 0
var _skipped_cases: int = 0


class TestEnemy extends Node2D:
	signal died(enemy_position: Vector2)

	func kill() -> void:
		died.emit(global_position)


func _ready() -> void:
	await _run_tests()


func _run_tests() -> void:
	if HIT_EFFECT_SCENE == null or EFFECT_SPAWNER_SCRIPT == null or SCREEN_SHAKE_SCRIPT == null:
		print("TEST_ERROR setup_failed required effect resource could not be loaded")
		_finish()
		return

	await _case_hit_effect_frees_itself()
	await _case_effect_advances_frames()
	await _case_enemy_death_spawns_in_container()
	await _case_death_effect_scales_with_enemy()
	await _case_shake_displaces_and_restores()
	await _case_shake_does_not_stack()
	_finish()


func _case_hit_effect_frees_itself() -> void:
	var host: Node = Node.new()
	add_child(host)
	var effect: Sprite2D = HIT_EFFECT_SCENE.instantiate() as Sprite2D
	effect.process_mode = DISABLED_PROCESS_MODE
	host.add_child(effect)

	var frames_advanced: int = 0
	var last_frame: int = effect.frame
	for step in range(30):
		if effect.is_queued_for_deletion():
			break
		effect.call(&"_process", 1.0 / 40.0)
		frames_advanced += 1
		if not effect.is_queued_for_deletion():
			last_frame = effect.frame

	await get_tree().process_frame
	var freed: bool = not is_instance_valid(effect)
	var passed: bool = freed and frames_advanced > 0 and last_frame > 0
	_record_case("hit_effect_frees_itself", passed, "frames_advanced=%d last_frame=%d" % [frames_advanced, last_frame])
	await _dispose(host)


func _case_effect_advances_frames() -> void:
	var host: Node = Node.new()
	add_child(host)
	var effect: Sprite2D = HIT_EFFECT_SCENE.instantiate() as Sprite2D
	effect.process_mode = DISABLED_PROCESS_MODE
	host.add_child(effect)

	var first_frame: int = effect.frame
	for step in range(3):
		effect.call(&"_process", 1.0 / 40.0)
	var last_frame: int = effect.frame
	var passed: bool = first_frame == 0 and last_frame > first_frame and last_frame > 0
	_record_case("effect_advances_frames", passed, "first_frame=%d last_frame=%d" % [first_frame, last_frame])
	await _dispose(host)


func _case_enemy_death_spawns_in_container() -> void:
	var fixture: Node = Node.new()
	add_child(fixture)
	var effects: Node = Node.new()
	effects.name = "Effects"
	fixture.add_child(effects)
	var enemies: Node = Node.new()
	enemies.name = "Enemies"
	fixture.add_child(enemies)
	var spawner: Node = EFFECT_SPAWNER_SCRIPT.new()
	spawner.name = "EffectSpawner"
	spawner.set("hit_effect_scene", HIT_EFFECT_SCENE)
	spawner.set("effect_container_path", NodePath("../Effects"))
	spawner.set("enemy_container_path", NodePath("../Enemies"))
	spawner.process_mode = DISABLED_PROCESS_MODE
	fixture.add_child(spawner)

	var enemy: TestEnemy = TestEnemy.new()
	enemy.position = Vector2(24.0, 12.0)
	enemies.add_child(enemy)
	enemy.kill()
	await get_tree().process_frame

	var effect_count: int = effects.get_child_count()
	var enemy_effect_count: int = enemy.get_child_count()
	var passed: bool = effect_count == 1 and enemy_effect_count == 0
	_record_case("enemy_death_spawns_in_container", passed, "container_effects=%d enemy_effects=%d" % [effect_count, enemy_effect_count])
	await _dispose(fixture)


func _case_death_effect_scales_with_enemy() -> void:
	var fixture: Node = Node.new()
	add_child(fixture)
	var effects: Node = Node.new()
	effects.name = "Effects"
	fixture.add_child(effects)
	var enemies: Node = Node.new()
	enemies.name = "Enemies"
	fixture.add_child(enemies)
	var spawner: Node = EFFECT_SPAWNER_SCRIPT.new()
	spawner.set("hit_effect_scene", HIT_EFFECT_SCENE)
	spawner.set("effect_container_path", NodePath("../Effects"))
	spawner.set("enemy_container_path", NodePath("../Enemies"))
	spawner.process_mode = DISABLED_PROCESS_MODE
	fixture.add_child(spawner)

	var small_effect: Sprite2D = spawner.call(&"spawn_death", Vector2.ZERO, 1.0) as Sprite2D
	var large_effect: Sprite2D = spawner.call(&"spawn_death", Vector2.ZERO, 3.0) as Sprite2D
	var small_scale: float = small_effect.scale.x if small_effect != null else 0.0
	var large_scale: float = large_effect.scale.x if large_effect != null else 0.0
	var passed: bool = small_scale > 0.0 and large_scale > small_scale
	_record_case("death_effect_scales_with_enemy", passed, "small_scale=%.2f large_scale=%.2f" % [small_scale, large_scale])
	await _dispose(fixture)


func _case_shake_displaces_and_restores() -> void:
	var fixture: Node = Node.new()
	add_child(fixture)
	var target: Node2D = Node2D.new()
	target.name = "WorldRoot"
	target.position = Vector2(120.0, 64.0)
	fixture.add_child(target)
	var shake_node: Node = SCREEN_SHAKE_SCRIPT.new()
	shake_node.set("target_path", NodePath("../WorldRoot"))
	shake_node.process_mode = DISABLED_PROCESS_MODE
	fixture.add_child(shake_node)

	var origin: Vector2 = target.position
	shake_node.call(&"shake")
	shake_node.call(&"_physics_process", 0.03)
	shake_node.call(&"_physics_process", 0.03)
	var displacement: float = target.position.distance_to(origin)
	for step in range(5):
		shake_node.call(&"_physics_process", 0.03)
	var final_delta: float = target.position.distance_to(origin)
	var passed: bool = displacement > 0.0 and final_delta == 0.0
	_record_case("shake_displaces_and_restores", passed, "displacement=%.4f final_delta=%.4f" % [displacement, final_delta])
	await _dispose(fixture)


func _case_shake_does_not_stack() -> void:
	var fixture: Node = Node.new()
	add_child(fixture)
	var target: Node2D = Node2D.new()
	target.name = "WorldRoot"
	target.position = Vector2(10.0, 20.0)
	fixture.add_child(target)
	var shake_node: Node = SCREEN_SHAKE_SCRIPT.new()
	shake_node.set("target_path", NodePath("../WorldRoot"))
	shake_node.process_mode = DISABLED_PROCESS_MODE
	fixture.add_child(shake_node)

	var origin: Vector2 = target.position
	shake_node.call(&"shake")
	shake_node.call(&"_physics_process", 0.05)
	shake_node.call(&"shake")
	var elapsed_frames: int = 0
	while bool(shake_node.call(&"is_shaking")) and elapsed_frames < 4:
		shake_node.call(&"_physics_process", 0.05)
		elapsed_frames += 1
	var final_delta: float = target.position.distance_to(origin)
	var ended: bool = not bool(shake_node.call(&"is_shaking"))
	var passed: bool = elapsed_frames > 0 and elapsed_frames <= 4 and ended and final_delta == 0.0
	_record_case("shake_does_not_stack", passed, "elapsed_frames=%d final_delta=%.4f" % [elapsed_frames, final_delta])
	await _dispose(fixture)


func _record_case(case_name: String, passed: bool, detail: String) -> void:
	_recorded_cases += 1
	if passed:
		_passed_cases += 1
		print("TEST_CASE %s PASS %s" % [case_name, detail])
	else:
		_failed_cases += 1
		print("TEST_CASE %s FAIL %s" % [case_name, detail])


func _dispose(node: Node) -> void:
	if is_instance_valid(node):
		node.queue_free()
	await get_tree().process_frame


func _finish() -> void:
	if _recorded_cases != EXPECTED_CASE_COUNT:
		print("TEST_ERROR missing_cases expected=%d recorded=%d" % [EXPECTED_CASE_COUNT, _recorded_cases])
		_failed_cases += 1
	var succeeded: bool = _passed_cases > 0 and _failed_cases == 0 and _recorded_cases == EXPECTED_CASE_COUNT
	var status: String = "PASS" if succeeded else "FAIL"
	print("TEST_RESULT %s passed=%d failed=%d skipped=%d" % [status, _passed_cases, _failed_cases, _skipped_cases])
	get_tree().quit(0 if succeeded else 1)
