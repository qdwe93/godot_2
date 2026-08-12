extends Node

const EXPECTED_CASE_COUNT: int = 5

var _recorded: int = 0
var _passed: int = 0
var _failed: int = 0
var _skipped: int = 0

var _fixture: Node
var _level_system: Node
var _ui: CanvasLayer


func _ready() -> void:
	await get_tree().process_frame
	_run_tests()


func _run_tests() -> void:
	_case_level_up_pauses_tree()
	_case_three_distinct_choices()
	_case_ui_processes_while_paused()
	_case_choosing_resumes_game()
	_case_consecutive_level_ups_queue()
	if _recorded != EXPECTED_CASE_COUNT:
		print("TEST_ERROR missing_cases expected=%d recorded=%d" % [EXPECTED_CASE_COUNT, _recorded])
		_failed += 1
	var result: String = "PASS" if _failed == 0 and _passed > 0 else "FAIL"
	print("TEST_RESULT %s passed=%d failed=%d skipped=%d" % [result, _passed, _failed, _skipped])
	get_tree().paused = false
	get_tree().quit(0 if result == "PASS" else 1)


func _setup_fixture() -> bool:
	_clear_fixture()
	get_tree().paused = false
	var player_scene: PackedScene = ResourceLoader.load("res://scenes/player.tscn", "PackedScene") as PackedScene
	var ui_scene: PackedScene = ResourceLoader.load("res://scenes/level_up_ui.tscn", "PackedScene") as PackedScene
	if player_scene == null:
		print("TEST_ERROR setup_failed missing_player_scene")
		return false
	if ui_scene == null:
		print("TEST_ERROR setup_failed missing_level_up_ui_scene")
		return false
	_fixture = Node.new()
	_fixture.name = "Fixture"
	add_child(_fixture)
	var player: Node = player_scene.instantiate()
	player.name = "Player"
	_fixture.add_child(player)
	_level_system = player.get_node_or_null("LevelSystem")
	if _level_system == null or not _level_system.has_method(&"add_experience"):
		print("TEST_ERROR setup_failed missing_level_system")
		_clear_fixture()
		return false
	_ui = ui_scene.instantiate() as CanvasLayer
	if _ui == null:
		print("TEST_ERROR setup_failed invalid_level_up_ui")
		_clear_fixture()
		return false
	_ui.set(&"level_system_path", NodePath("../Player/LevelSystem"))
	_fixture.add_child(_ui)
	if not _ui.has_signal(&"upgrade_chosen"):
		print("TEST_ERROR setup_failed level_up_ui_not_loaded")
		_clear_fixture()
		return false
	return true


func _clear_fixture() -> void:
	if _fixture != null:
		remove_child(_fixture)
		_fixture.queue_free()
	_fixture = null
	_level_system = null
	_ui = null


func _case_level_up_pauses_tree() -> void:
	if not _setup_fixture():
		_record("level_up_pauses_tree", false, "setup_failed")
		return
	_level_system.call(&"add_experience", 10.0)
	var level_reached: int = int(_level_system.get(&"level"))
	var passed: bool = get_tree().paused and _ui.visible
	_record("level_up_pauses_tree", passed, "level=%d paused=%s visible=%s" % [level_reached, get_tree().paused, _ui.visible])
	_clear_fixture()


func _case_three_distinct_choices() -> void:
	if not _setup_fixture():
		_record("three_distinct_choices", false, "setup_failed")
		return
	_level_system.call(&"add_experience", 10.0)
	var ids: Array[StringName] = _choice_ids()
	var seen: Dictionary = {}
	for choice_id in ids:
		seen[choice_id] = true
	var passed: bool = ids.size() == 3 and seen.size() == 3
	_record("three_distinct_choices", passed, "count=%d unique=%d ids=%s" % [ids.size(), seen.size(), _ids_text(ids)])
	get_tree().paused = false
	_clear_fixture()


func _case_ui_processes_while_paused() -> void:
	if not _setup_fixture():
		_record("ui_processes_while_paused", false, "setup_failed")
		return
	_level_system.call(&"add_experience", 10.0)
	var observed_mode: int = _ui.process_mode
	var was_paused: bool = get_tree().paused
	_ui.call(&"choose", 0)
	var recorded_choice: StringName = StringName(_ui.get(&"last_choice"))
	var runs_while_paused: bool = observed_mode == Node.PROCESS_MODE_WHEN_PAUSED or observed_mode == Node.PROCESS_MODE_ALWAYS
	var passed: bool = runs_while_paused and was_paused and not _ui.visible and recorded_choice != &""
	_record("ui_processes_while_paused", passed, "process_mode=%d paused_before=%s chosen=%s" % [observed_mode, was_paused, recorded_choice])
	_clear_fixture()


func _case_choosing_resumes_game() -> void:
	if not _setup_fixture():
		_record("choosing_resumes_game", false, "setup_failed")
		return
	_level_system.call(&"add_experience", 10.0)
	_ui.call(&"choose", 0)
	var history: Array = _ui.get(&"chosen_history")
	var chosen_id: StringName = StringName(_ui.get(&"last_choice"))
	var passed: bool = not _ui.visible and not get_tree().paused and history.size() == 1
	_record("choosing_resumes_game", passed, "id=%s history=%d paused=%s" % [chosen_id, history.size(), get_tree().paused])
	_clear_fixture()


func _case_consecutive_level_ups_queue() -> void:
	if not _setup_fixture():
		_record("consecutive_level_ups_queue", false, "setup_failed")
		return
	_level_system.call(&"add_experience", 30.0)
	var initially_visible: bool = _ui.visible
	var initially_paused: bool = get_tree().paused
	_ui.call(&"choose", 0)
	var queue_after_first: int = _pending_count()
	var paused_after_first: bool = get_tree().paused
	var visible_after_first: bool = _ui.visible
	_ui.call(&"choose", 0)
	var queue_after_second: int = _pending_count()
	var paused_after_second: bool = get_tree().paused
	var visible_after_second: bool = _ui.visible
	_ui.call(&"choose", 0)
	var queue_after_third: int = _pending_count()
	var passed: bool = initially_visible and initially_paused and visible_after_first and paused_after_first and visible_after_second and paused_after_second and not _ui.visible and not get_tree().paused and queue_after_first == 1 and queue_after_second == 0 and queue_after_third == 0
	_record("consecutive_level_ups_queue", passed, "screens=3 queue_after= %d/%d/%d" % [queue_after_first, queue_after_second, queue_after_third])
	_clear_fixture()


func _choice_ids() -> Array[StringName]:
	var raw_ids: Array = _ui.call(&"get_choice_ids")
	var ids: Array[StringName] = []
	for raw_id in raw_ids:
		ids.append(StringName(raw_id))
	return ids


func _pending_count() -> int:
	var pending_levels: Array = _ui.get(&"_pending_levels")
	return pending_levels.size()


func _ids_text(ids: Array[StringName]) -> String:
	var values: PackedStringArray = []
	for choice_id in ids:
		values.append(str(choice_id))
	return ",".join(values)


func _record(case_name: String, passed: bool, detail: String) -> void:
	_recorded += 1
	if passed:
		_passed += 1
		print("TEST_CASE %s PASS %s" % [case_name, detail])
	else:
		_failed += 1
		print("TEST_CASE %s FAIL %s" % [case_name, detail])
