extends Node

const EXPECTED_CASE_COUNT: int = 8
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const PLAYER_SCRIPT: Script = preload("res://scripts/player.gd")
const PROJECTILE_SCRIPT: Script = preload("res://scripts/projectile.gd")
const HIT_EFFECT_SCENE: PackedScene = preload("res://scenes/hit_effect.tscn")
const HIT_EFFECT_SCRIPT: Script = preload("res://scripts/hit_effect.gd")
const EFFECT_SPAWNER_SCRIPT: Script = preload("res://scripts/effect_spawner.gd")
const HUD_SCENE: PackedScene = preload("res://scenes/hud.tscn")
const DISABLED_PROCESS_MODE: int = 4

var _recorded_cases: int = 0
var _passed_cases: int = 0
var _failed_cases: int = 0
var _skipped_cases: int = 0


class TestPlayer extends Node:
	signal health_changed(current: float, maximum: float)
	signal died()

	var health: float = 100.0
	var max_health: float = 100.0

	func set_health(current: float) -> void:
		health = current
		health_changed.emit(health, max_health)


class TestLevelSystem extends Node:
	signal experience_changed(current: float, required: float, level: int)

	var experience: float = 0.0
	var level: int = 1

	func required_for_next_level() -> float:
		return 10.0


func _ready() -> void:
	await _run_tests()


func _run_tests() -> void:
	if ENEMY_SCENE == null or PLAYER_SCENE == null or PROJECTILE_SCRIPT == null or HIT_EFFECT_SCENE == null or EFFECT_SPAWNER_SCRIPT == null or HUD_SCENE == null:
		print("TEST_ERROR setup_failed required feedback resource could not be loaded")
		_finish()
		return
	await _case_projectile_spawns_hit_effect()
	await _case_enemy_flashes_on_hit()
	await _case_enemy_flash_restores_colour()
	await _case_hud_enters_danger_state()
	await _case_hud_leaves_danger_state()
	await _case_invincibility_blinks_the_sprite()
	await _case_invincibility_restores_alpha_exactly()
	await _case_danger_blink_does_not_fight_invincibility()
	_finish()


func _case_projectile_spawns_hit_effect() -> void:
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
	var enemy: CharacterBody2D = ENEMY_SCENE.instantiate() as CharacterBody2D
	enemies.add_child(enemy)
	var projectile: Area2D = PROJECTILE_SCRIPT.new() as Area2D
	fixture.add_child(projectile)
	# 이펙트 컨테이너의 **자식 수**를 세면 안 된다. M18에서 같은 명중이 피해 숫자도
	# 함께 만들면서 자식이 2개가 됐고, 이 케이스가 "명중 이펙트가 안 생겼다"는
	# 엉뚱한 실패로 바뀌었다. 세어야 하는 것은 **명중 이펙트가 생겼는가**다.
	var before_count: int = _count_hit_effects(effects)
	projectile.call(&"_on_body_entered", enemy)
	var after_count: int = _count_hit_effects(effects)
	_record_case("projectile_spawns_hit_effect", after_count == before_count + 1, "before=%d after=%d" % [before_count, after_count])
	await _dispose(fixture)


func _count_hit_effects(container: Node) -> int:
	var found: int = 0
	for child in container.get_children():
		if child.get_script() == HIT_EFFECT_SCRIPT:
			found += 1
	return found


func _case_enemy_flashes_on_hit() -> void:
	var enemy: CharacterBody2D = ENEMY_SCENE.instantiate() as CharacterBody2D
	enemy.process_mode = DISABLED_PROCESS_MODE
	add_child(enemy)
	# M15에서 스프라이트가 텍스처가 되면서 "색을 흰색으로 바꿨다 되돌리기"를 못 쓰게 됐다.
	# modulate 는 곱셈이라 색을 더 밝게 만들 수 없기 때문이다. 지금은 같은 그림을
	# 흰색으로 칠한 Flash 오버레이의 알파를 올린다. 그래서 검사 대상도 알파다.
	var flash: Sprite2D = enemy.get_node_or_null("Flash") as Sprite2D
	var alpha_before: float = flash.self_modulate.a if flash != null else -1.0
	enemy.call(&"take_damage", 1.0)
	var alpha_after: float = flash.self_modulate.a if flash != null else -1.0
	var flashing: bool = bool(enemy.call(&"is_hit_flashing"))
	_record_case("enemy_flashes_on_hit", flash != null and flashing and alpha_after > alpha_before,
		"flashing=%s alpha_before=%.2f alpha_after=%.2f" % [flashing, alpha_before, alpha_after])
	await _dispose(enemy)


func _case_enemy_flash_restores_colour() -> void:
	var enemy: CharacterBody2D = ENEMY_SCENE.instantiate() as CharacterBody2D
	enemy.process_mode = DISABLED_PROCESS_MODE
	add_child(enemy)
	var flash: Sprite2D = enemy.get_node_or_null("Flash") as Sprite2D
	enemy.call(&"take_damage", 1.0)
	enemy.call(&"_physics_process", 0.07)
	var restored_alpha: float = flash.self_modulate.a if flash != null else -1.0
	var flashing: bool = bool(enemy.call(&"is_hit_flashing"))
	_record_case("enemy_flash_restores_colour", flash != null and not flashing and is_zero_approx(restored_alpha),
		"flashing=%s restored_alpha=%.2f" % [flashing, restored_alpha])
	await _dispose(enemy)


func _case_hud_enters_danger_state() -> void:
	var fixture: Node = _create_hud_fixture()
	var player: TestPlayer = fixture.get_node("Player") as TestPlayer
	var hud: CanvasLayer = fixture.get_node("HUD") as CanvasLayer
	player.set_health(20.0)
	var danger_state: bool = bool(hud.call(&"is_danger_state"))
	var danger_alpha: float = float(hud.call(&"get_danger_alpha"))
	_record_case("hud_enters_danger_state", danger_state and danger_alpha > 0.0, "state=%s alpha=%.3f" % [danger_state, danger_alpha])
	await _dispose(fixture)


func _case_hud_leaves_danger_state() -> void:
	var fixture: Node = _create_hud_fixture()
	var player: TestPlayer = fixture.get_node("Player") as TestPlayer
	var hud: CanvasLayer = fixture.get_node("HUD") as CanvasLayer
	player.set_health(20.0)
	player.set_health(100.0)
	var danger_state: bool = bool(hud.call(&"is_danger_state"))
	var danger_alpha: float = float(hud.call(&"get_danger_alpha"))
	_record_case("hud_leaves_danger_state", not danger_state and danger_alpha == 0.0, "state=%s alpha=%.3f" % [danger_state, danger_alpha])
	await _dispose(fixture)


func _case_invincibility_blinks_the_sprite() -> void:
	var player: CharacterBody2D = PLAYER_SCENE.instantiate() as CharacterBody2D
	player.set(&"health_regen", 0.0)
	add_child(player)
	player.call(&"take_damage", 1.0)

	var observed_alphas: Array[float] = []
	var sample_limit: int = _invincibility_sample_limit(player)
	var sampled_frames: int = 0
	for _sample_index: int in range(sample_limit):
		if not bool(player.get(&"is_invincible")):
			break
		await get_tree().physics_frame
		sampled_frames += 1
		_append_unique_alpha(observed_alphas, float(player.call(&"get_sprite_alpha")))
	var minimum_alpha: float = _minimum_alpha(observed_alphas)
	_record_case("invincibility_blinks_the_sprite",
		observed_alphas.size() >= 2 and minimum_alpha < 1.0,
		"samples=%d limit=%d distinct=%d values=%s minimum=%.3f" % [sampled_frames, sample_limit, observed_alphas.size(), observed_alphas, minimum_alpha])
	await _dispose(player)


func _case_invincibility_restores_alpha_exactly() -> void:
	var player: CharacterBody2D = PLAYER_SCENE.instantiate() as CharacterBody2D
	player.set(&"health_regen", 0.0)
	add_child(player)
	player.call(&"take_damage", 1.0)

	var saw_dim_alpha: bool = false
	var minimum_alpha: float = 1.0
	for _sample_index: int in range(_invincibility_sample_limit(player)):
		if not bool(player.get(&"is_invincible")):
			break
		await get_tree().physics_frame
		var alpha: float = float(player.call(&"get_sprite_alpha"))
		minimum_alpha = minf(minimum_alpha, alpha)
		if alpha < 1.0:
			saw_dim_alpha = true
			break
	var invincibility_time: float = float(player.get(&"invincibility_time"))
	player.call(&"advance_invincibility", invincibility_time + 1.0)
	var restored_alpha: float = float(player.call(&"get_sprite_alpha"))
	var still_invincible: bool = bool(player.get(&"is_invincible"))
	_record_case("invincibility_restores_alpha_exactly",
		saw_dim_alpha and not still_invincible and restored_alpha == 1.0,
		"saw_dim=%s minimum=%.3f invincible=%s restored=%.9f" % [saw_dim_alpha, minimum_alpha, still_invincible, restored_alpha])
	await _dispose(player)


func _case_danger_blink_does_not_fight_invincibility() -> void:
	var player: CharacterBody2D = PLAYER_SCENE.instantiate() as CharacterBody2D
	player.set(&"health_regen", 0.0)
	add_child(player)
	var maximum_health: float = float(player.get(&"max_health"))
	var player_constants: Dictionary = PLAYER_SCRIPT.get_script_constant_map()
	var danger_ratio: float = float(player_constants.get(&"DANGER_HEALTH_RATIO", 0.0))
	var target_health: float = maximum_health * danger_ratio * 0.5
	player.call(&"take_damage", maximum_health - target_health)

	var sprite_alphas: Array[float] = []
	var danger_alphas: Array[float] = []
	_append_unique_alpha(sprite_alphas, float(player.call(&"get_sprite_alpha")))
	_append_unique_alpha(danger_alphas, float(player.call(&"get_danger_overlay_alpha")))
	var sample_limit: int = _invincibility_sample_limit(player)
	for _sample_index: int in range(sample_limit):
		if not bool(player.get(&"is_invincible")):
			break
		await get_tree().physics_frame
		_append_unique_alpha(sprite_alphas, float(player.call(&"get_sprite_alpha")))
		_append_unique_alpha(danger_alphas, float(player.call(&"get_danger_overlay_alpha")))
	var actual_ratio: float = float(player.get(&"health")) / maximum_health
	_record_case("danger_blink_does_not_fight_invincibility",
		actual_ratio <= danger_ratio and sprite_alphas.size() >= 2 and danger_alphas.size() >= 2,
		"ratio=%.3f threshold=%.3f sprite_distinct=%d values=%s danger_distinct=%d values=%s" % [actual_ratio, danger_ratio, sprite_alphas.size(), sprite_alphas, danger_alphas.size(), danger_alphas])
	await _dispose(player)


func _invincibility_sample_limit(player: Node) -> int:
	var invincibility_time: float = float(player.get(&"invincibility_time"))
	return maxi(4, ceili(invincibility_time * float(Engine.physics_ticks_per_second)) + 4)


func _append_unique_alpha(values: Array[float], alpha: float) -> void:
	if not values.has(alpha):
		values.append(alpha)


func _minimum_alpha(values: Array[float]) -> float:
	var minimum: float = INF
	for alpha: float in values:
		minimum = minf(minimum, alpha)
	return minimum


func _create_hud_fixture() -> Node:
	var fixture: Node = Node.new()
	add_child(fixture)
	var player: TestPlayer = TestPlayer.new()
	player.name = "Player"
	fixture.add_child(player)
	var level_system: TestLevelSystem = TestLevelSystem.new()
	level_system.name = "LevelSystem"
	fixture.add_child(level_system)
	var enemies: Node = Node.new()
	enemies.name = "Enemies"
	fixture.add_child(enemies)
	var hud: CanvasLayer = HUD_SCENE.instantiate() as CanvasLayer
	hud.name = "HUD"
	hud.set("player_path", NodePath("../Player"))
	hud.set("level_system_path", NodePath("../LevelSystem"))
	hud.set("enemy_container_path", NodePath("../Enemies"))
	hud.process_mode = DISABLED_PROCESS_MODE
	fixture.add_child(hud)
	return fixture


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
