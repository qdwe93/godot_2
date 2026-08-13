extends Node

const EXPECTED_CASE_COUNT: int = 5
const PLAYER_SCRIPT: Script = preload("res://scripts/player.gd")
const LEVEL_UP_UI_SCRIPT: Script = preload("res://scripts/level_up_ui.gd")
# 업그레이드 목록을 여기에 다시 적으면 정의가 늘 때마다 이 테스트가 조용히 낡는다.
# 실제로 산탄·궤도구가 선택 풀에 들어왔을 때 이 하드코딩 때문에 2케이스가 깨졌다.

var _passed: int = 0
var _failed: int = 0
var _skipped: int = 0
var _recorded: int = 0


class TestLevelSystem extends Node:
	signal leveled_up(new_level: int)

	var experience: float = 0.0

	func add_experience(amount: float) -> void:
		experience += amount


class TestUpgradeManager extends Node:
	var _levels: Dictionary = {}

	func apply_upgrade(id: StringName) -> void:
		var current_level: int = get_level(id)
		_levels[id] = current_level + 1

	func get_level(id: StringName) -> int:
		return int(_levels.get(id, 0))

	func get_experience_multiplier() -> float:
		return pow(1.1, float(get_level(&"crown")))


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_case_crown_multiplies_gem_experience()
	_case_no_manager_means_no_scaling()
	_case_maxed_upgrade_disappears()
	_case_two_available_shows_two_buttons()
	_case_no_upgrades_skips_screen()
	_finish()


func _make_player(parent: Node) -> Dictionary:
	var player: CharacterBody2D = PLAYER_SCRIPT.new() as CharacterBody2D
	player.name = "Player"

	var magnet_area: Area2D = Area2D.new()
	magnet_area.name = "MagnetArea"
	player.add_child(magnet_area)

	var hurtbox: Area2D = Area2D.new()
	hurtbox.name = "Hurtbox"
	player.add_child(hurtbox)

	var level_system: TestLevelSystem = TestLevelSystem.new()
	level_system.name = "LevelSystem"
	player.add_child(level_system)
	parent.add_child(player)

	return {"player": player, "level_system": level_system}


func _make_level_up_ui(parent: Node) -> CanvasLayer:
	var level_up_ui: CanvasLayer = LEVEL_UP_UI_SCRIPT.new() as CanvasLayer
	level_up_ui.name = "LevelUpUI"
	level_up_ui.set("level_system_path", NodePath("../Player/LevelSystem"))
	level_up_ui.visible = false

	var choices: Control = Control.new()
	choices.name = "Choices"
	level_up_ui.add_child(choices)
	for choice_index in range(3):
		var button: Button = Button.new()
		button.name = "Choice%d" % choice_index
		choices.add_child(button)
	parent.add_child(level_up_ui)
	return level_up_ui


func _make_manager(parent: Node) -> TestUpgradeManager:
	var manager: TestUpgradeManager = TestUpgradeManager.new()
	manager.name = "UpgradeManager"
	manager.add_to_group("upgrade_manager")
	parent.add_child(manager)
	return manager


func _case_crown_multiplies_gem_experience() -> void:
	var arena: Node = Node.new()
	add_child(arena)
	var player_parts: Dictionary = _make_player(arena)
	var player: Node = player_parts["player"]
	var level_system: TestLevelSystem = player_parts["level_system"]
	var manager: TestUpgradeManager = _make_manager(arena)

	player.call("add_experience", 10.0)
	var base_gain: float = level_system.experience
	level_system.experience = 0.0
	manager.apply_upgrade(&"crown")
	player.call("add_experience", 10.0)
	var crown_gain: float = level_system.experience
	var passed: bool = base_gain > 0.0 and crown_gain > 0.0 and is_equal_approx(crown_gain, base_gain * 1.1)
	_record("crown_multiplies_gem_experience", passed, "base=%.2f crown=%.2f" % [base_gain, crown_gain])
	_dispose(arena)


func _case_no_manager_means_no_scaling() -> void:
	var arena: Node = Node.new()
	add_child(arena)
	var player_parts: Dictionary = _make_player(arena)
	var player: Node = player_parts["player"]
	var level_system: TestLevelSystem = player_parts["level_system"]

	player.call("add_experience", 10.0)
	var granted: float = level_system.experience
	var passed: bool = granted > 0.0 and is_equal_approx(granted, 10.0)
	_record("no_manager_means_no_crash_and_no_scaling", passed, "granted=%.2f errors=0" % granted)
	_dispose(arena)


func _case_maxed_upgrade_disappears() -> void:
	var arena: Node = Node.new()
	add_child(arena)
	_make_player(arena)
	var level_up_ui: CanvasLayer = _make_level_up_ui(arena)
	var manager: TestUpgradeManager = _make_manager(arena)
	var definition: Dictionary = UpgradeData.get_definition(&"magnet")
	var max_level: int = int(definition.get("max_level", 0))
	for level_index in range(max_level):
		manager.apply_upgrade(&"magnet")

	var draw_count: int = 8
	var absent_from_every_draw: bool = max_level > 0
	for draw_index in range(draw_count):
		level_up_ui.call("_on_leveled_up", draw_index + 1)
		var choices: Array[StringName] = level_up_ui.call("get_choice_ids")
		if choices.has(&"magnet"):
			absent_from_every_draw = false
		level_up_ui.visible = false
		get_tree().paused = false
	_record("maxed_upgrade_disappears_from_choices", absent_from_every_draw, "max_level=%d draws=%d" % [max_level, draw_count])
	_dispose(arena)


func _case_two_available_shows_two_buttons() -> void:
	var arena: Node = Node.new()
	add_child(arena)
	_make_player(arena)
	var level_up_ui: CanvasLayer = _make_level_up_ui(arena)
	var manager: TestUpgradeManager = _make_manager(arena)
	for upgrade_id in UpgradeData.get_all_ids():
		if upgrade_id == &"shoes" or upgrade_id == &"heart":
			continue
		var definition: Dictionary = UpgradeData.get_definition(upgrade_id)
		var max_level: int = int(definition.get("max_level", 0))
		for level_index in range(max_level):
			manager.apply_upgrade(upgrade_id)

	level_up_ui.call("_on_leveled_up", 1)
	var choices: Array[StringName] = level_up_ui.call("get_choice_ids")
	var third_button: Button = level_up_ui.get_node("Choices/Choice2") as Button
	var passed: bool = choices.size() == 2 and third_button != null and not third_button.visible
	_record("fewer_than_three_available_shows_fewer_buttons", passed, "choices=%d third_visible=%s" % [choices.size(), str(third_button.visible)])
	_dispose(arena)


func _case_no_upgrades_skips_screen() -> void:
	var arena: Node = Node.new()
	add_child(arena)
	_make_player(arena)
	var level_up_ui: CanvasLayer = _make_level_up_ui(arena)
	var manager: TestUpgradeManager = _make_manager(arena)
	for upgrade_id in UpgradeData.get_all_ids():
		var definition: Dictionary = UpgradeData.get_definition(upgrade_id)
		var max_level: int = int(definition.get("max_level", 0))
		for level_index in range(max_level):
			manager.apply_upgrade(upgrade_id)

	level_up_ui.call("_on_leveled_up", 1)
	var paused: bool = get_tree().paused
	var passed: bool = not paused and not level_up_ui.visible
	_record("zero_available_skips_screen", passed, "paused=%s visible=%s" % [str(paused), str(level_up_ui.visible)])
	_dispose(arena)


func _dispose(arena: Node) -> void:
	get_tree().paused = false
	arena.free()


func _record(case_name: String, passed: bool, detail: String) -> void:
	_recorded += 1
	if passed:
		_passed += 1
		print("TEST_CASE %s PASS %s" % [case_name, detail])
	else:
		_failed += 1
		print("TEST_CASE %s FAIL %s" % [case_name, detail])


func _finish() -> void:
	if _recorded != EXPECTED_CASE_COUNT:
		_failed += 1
		print("TEST_ERROR missing_cases expected=%d recorded=%d" % [EXPECTED_CASE_COUNT, _recorded])
	var result: String = "PASS" if _failed == 0 and _passed > 0 else "FAIL"
	print("TEST_RESULT %s passed=%d failed=%d skipped=%d" % [result, _passed, _failed, _skipped])
	var exit_code: int = 0
	if result == "FAIL":
		exit_code = 1
	get_tree().quit(exit_code)
