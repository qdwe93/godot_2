extends Node

const EXPECTED_CASE_COUNT: int = 5
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy.tscn")
const PROJECTILE_SCRIPT: Script = preload("res://scripts/projectile.gd")
const HIT_EFFECT_SCENE: PackedScene = preload("res://scenes/hit_effect.tscn")
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
	if ENEMY_SCENE == null or PROJECTILE_SCRIPT == null or HIT_EFFECT_SCENE == null or EFFECT_SPAWNER_SCRIPT == null or HUD_SCENE == null:
		print("TEST_ERROR setup_failed required feedback resource could not be loaded")
		_finish()
		return
	await _case_projectile_spawns_hit_effect()
	await _case_enemy_flashes_on_hit()
	await _case_enemy_flash_restores_colour()
	await _case_hud_enters_danger_state()
	await _case_hud_leaves_danger_state()
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
	var before_count: int = effects.get_child_count()
	projectile.call(&"_on_body_entered", enemy)
	var after_count: int = effects.get_child_count()
	_record_case("projectile_spawns_hit_effect", after_count == before_count + 1, "before=%d after=%d" % [before_count, after_count])
	await _dispose(fixture)


func _case_enemy_flashes_on_hit() -> void:
	var enemy: CharacterBody2D = ENEMY_SCENE.instantiate() as CharacterBody2D
	enemy.process_mode = DISABLED_PROCESS_MODE
	add_child(enemy)
	var sprite: ColorRect = enemy.get_node_or_null("Sprite") as ColorRect
	var base_colour: Color = sprite.color if sprite != null else Color.WHITE
	enemy.call(&"take_damage", 1.0)
	var current_colour: Color = sprite.color if sprite != null else base_colour
	var flashing: bool = bool(enemy.call(&"is_hit_flashing"))
	_record_case("enemy_flashes_on_hit", flashing and current_colour != base_colour, "flashing=%s" % flashing)
	await _dispose(enemy)


func _case_enemy_flash_restores_colour() -> void:
	var enemy: CharacterBody2D = ENEMY_SCENE.instantiate() as CharacterBody2D
	enemy.process_mode = DISABLED_PROCESS_MODE
	add_child(enemy)
	var sprite: ColorRect = enemy.get_node_or_null("Sprite") as ColorRect
	enemy.call(&"take_damage", 1.0)
	enemy.call(&"_physics_process", 0.07)
	var restored_colour: Color = sprite.color if sprite != null else Color.WHITE
	var base_colour: Color = enemy.call(&"get_base_sprite_color")
	var flashing: bool = bool(enemy.call(&"is_hit_flashing"))
	_record_case("enemy_flash_restores_colour", not flashing and restored_colour == base_colour, "flashing=%s" % flashing)
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
