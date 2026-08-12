extends Node

const EXPECTED_CASE_COUNT: int = 6
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy.tscn")
const HUD_SCENE: PackedScene = preload("res://scenes/hud.tscn")

var _passed: int = 0
var _failed: int = 0
var _skipped: int = 0
var _recorded: int = 0

var _world: Node2D
var _player: Node
var _enemy_container: Node2D
var _hud: Node
var _level_system: Node


func _ready() -> void:
	await _run_suite()


func _run_suite() -> void:
	if not await _setup():
		print("TEST_ERROR setup_failed unable_to_create_hud_fixture")
		print("TEST_ERROR missing_cases expected=%d recorded=%d" % [EXPECTED_CASE_COUNT, _recorded])
		_failed += 1
		_finish()
		return
	await _case_initial_values()
	await _case_damage_updates_bar()
	await _case_experience_and_level_update()
	await _case_kills_are_counted()
	await _case_timer_runs_and_formats()
	await _case_timer_stops_on_death()
	if _recorded != EXPECTED_CASE_COUNT:
		print("TEST_ERROR missing_cases expected=%d recorded=%d" % [EXPECTED_CASE_COUNT, _recorded])
		_failed += 1
	_finish()


func _setup() -> bool:
	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)

	_player = PLAYER_SCENE.instantiate()
	_player.name = "Player"
	_world.add_child(_player)

	_enemy_container = Node2D.new()
	_enemy_container.name = "EnemyContainer"
	_world.add_child(_enemy_container)

	_level_system = _player.get_node_or_null("LevelSystem")
	if _level_system == null:
		return false

	_hud = HUD_SCENE.instantiate()
	_hud.name = "HUD"
	_hud.set("player_path", NodePath("../World/Player"))
	_hud.set("level_system_path", NodePath("../World/Player/LevelSystem"))
	_hud.set("enemy_container_path", NodePath("../World/EnemyContainer"))
	add_child(_hud)
	await get_tree().process_frame
	return is_instance_valid(_hud)


func _case_initial_values() -> void:
	var displayed: Dictionary = _hud.call("get_displayed_values")
	var player_health: float = float(_player.get("health"))
	var displayed_health: float = float(displayed.get("health", -1.0))
	var displayed_level: int = int(displayed.get("level", -1))
	var passed: bool = is_equal_approx(displayed_health, player_health) and displayed_level == 1
	_record_case("initial_values", passed, "health=%.2f player=%.2f level=%d" % [displayed_health, player_health, displayed_level])


func _case_damage_updates_bar() -> void:
	var before: float = float(_player.get("health"))
	var damage: float = maxf(0.01, minf(10.0, before * 0.5))
	_player.call("take_damage", damage)
	await get_tree().process_frame
	var displayed: Dictionary = _hud.call("get_displayed_values")
	var after: float = float(displayed.get("health", -1.0))
	var health_bar: ProgressBar = _hud.get_node("HealthBar") as ProgressBar
	var bar_value: float = health_bar.value
	var passed: bool = is_equal_approx(before - after, damage) and is_equal_approx(bar_value, after)
	_record_case("damage_updates_bar", passed, "before=%.2f after=%.2f damage=%.2f bar=%.2f" % [before, after, damage, bar_value])


func _case_experience_and_level_update() -> void:
	var before_level: int = int(_level_system.get("level"))
	var required: float = float(_level_system.call("required_for_next_level"))
	_level_system.call("add_experience", required + 1.0)
	await get_tree().process_frame
	var displayed: Dictionary = _hud.call("get_displayed_values")
	var current_level: int = int(_level_system.get("level"))
	var current_experience: float = float(_level_system.get("experience"))
	var displayed_level: int = int(displayed.get("level", -1))
	var displayed_experience: float = float(displayed.get("experience", -1.0))
	var passed: bool = current_level > before_level and displayed_level == current_level and is_equal_approx(displayed_experience, current_experience)
	_record_case("experience_and_level_update", passed, "level_before=%d level_after=%d experience=%.2f displayed=%.2f" % [before_level, current_level, current_experience, displayed_experience])


func _case_kills_are_counted() -> void:
	for _index in range(3):
		var enemy: Node = ENEMY_SCENE.instantiate()
		_enemy_container.add_child(enemy)
		await get_tree().physics_frame
		enemy.call("take_damage", 9999.0)
	for _frame in range(2):
		await get_tree().physics_frame
	var killed_count: int = int(_hud.call("get_kill_count"))
	var removed_enemy: Node = ENEMY_SCENE.instantiate()
	_enemy_container.add_child(removed_enemy)
	await get_tree().physics_frame
	removed_enemy.queue_free()
	await get_tree().physics_frame
	var after_removal_count: int = int(_hud.call("get_kill_count"))
	var passed: bool = killed_count == 3 and after_removal_count == 3
	_record_case("kills_are_counted", passed, "after_kills=%d after_removal=%d" % [killed_count, after_removal_count])


func _case_timer_runs_and_formats() -> void:
	var before: float = float(_hud.call("get_elapsed_time"))
	for _frame in range(3):
		await get_tree().process_frame
	var after: float = float(_hud.call("get_elapsed_time"))
	var formatted: String = str(_hud.call("format_elapsed_time", 127.0))
	var passed: bool = after > before and formatted == "2:07"
	_record_case("timer_runs_and_formats", passed, "before=%.4f after=%.4f formatted=%s" % [before, after, formatted])


func _case_timer_stops_on_death() -> void:
	# 앞선 피해 케이스에서 남은 무적 시간을 먼저 없앤다.
	# 그러지 않으면 take_damage 가 무시되어 플레이어가 죽지 않고,
	# "타이머가 멈추지 않는다"는 엉뚱한 실패로 보인다.
	_player.call("advance_invincibility", 10.0)
	_player.call("take_damage", 999999.0)
	await get_tree().process_frame
	var after_death: float = float(_hud.call("get_elapsed_time"))
	for _frame in range(3):
		await get_tree().process_frame
	var after_frames: float = float(_hud.call("get_elapsed_time"))
	# 0 과 0 을 비교해 통과하는 것을 막는다: 타이머가 실제로 돌았어야 한다.
	var passed: bool = after_death > 0.0 and is_equal_approx(after_death, after_frames)
	_record_case("timer_stops_on_death", passed, "after_death=%.4f after_frames=%.4f" % [after_death, after_frames])


func _record_case(case_name: String, passed: bool, detail: String) -> void:
	_recorded += 1
	if passed:
		_passed += 1
		print("TEST_CASE %s PASS %s" % [case_name, detail])
	else:
		_failed += 1
		print("TEST_CASE %s FAIL %s" % [case_name, detail])


func _finish() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
	if is_instance_valid(_hud):
		_hud.queue_free()
	var passed_suite: bool = _passed > 0 and _failed == 0 and _recorded == EXPECTED_CASE_COUNT
	var status: String = "PASS" if passed_suite else "FAIL"
	print("TEST_RESULT %s passed=%d failed=%d skipped=%d" % [status, _passed, _failed, _skipped])
	get_tree().quit(0 if passed_suite else 1)
