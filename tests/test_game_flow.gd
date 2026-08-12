extends Node

const EXPECTED_CASE_COUNT: int = 6

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const HUD_SCENE: PackedScene = preload("res://scenes/hud.tscn")
const FLOW_SCENE: PackedScene = preload("res://scenes/game_flow.tscn")
const LEVEL_UP_UI_SCENE: PackedScene = preload("res://scenes/level_up_ui.tscn")

var passed: int = 0
var failed: int = 0
var skipped: int = 0
var recorded_cases: int = 0


func _ready() -> void:
	await _run_suite()


func _run_suite() -> void:
	var setup: Dictionary = await _build_flow()
	if setup.is_empty():
		print("TEST_ERROR setup_failed initial_flow")
		_finish()
		return
	var flow: Variant = setup["flow"]

	_record("title_pauses_at_startup", flow.is_title_visible() and get_tree().paused,
		"title_visible=%s paused=%s" % [flow.is_title_visible(), get_tree().paused])

	flow.start_game()
	_record("starting_unpauses", not flow.is_title_visible() and not get_tree().paused,
		"title_visible=%s paused=%s" % [flow.is_title_visible(), get_tree().paused])

	var player: Variant = setup["player"]
	var hud: Variant = setup["hud"]
	var expected_kills: int = int(hud.call("get_kill_count"))
	player.call("advance_invincibility", 10.0)
	player.call("take_damage", 99999.0)
	await get_tree().process_frame
	var result_label: Variant = flow.get_node("GameOverPanel/ResultLabel")
	var result: String = str(result_label.get("text"))
	_record("death_shows_summary", flow.is_game_over_visible() and get_tree().paused and not result.is_empty() and result.contains(str(expected_kills)),
		"game_over_visible=%s paused=%s kills=%d result=%s" % [flow.is_game_over_visible(), get_tree().paused, expected_kills, result.replace("\n", " | ")])

	flow.reload_on_restart = false
	flow.restart()
	_record("restart_unpauses_before_reload", not get_tree().paused,
		"paused=%s reload_on_restart=%s" % [get_tree().paused, flow.reload_on_restart])
	await _cleanup(setup)

	var auto_setup: Dictionary = await _build_flow()
	if auto_setup.is_empty():
		print("TEST_ERROR setup_failed auto_play_flow")
		_finish()
		return
	var auto_flow: Variant = auto_setup["flow"]
	auto_flow.enable_auto_play()
	_record("auto_play_skips_title", not auto_flow.is_title_visible() and not get_tree().paused,
		"title_visible=%s paused=%s" % [auto_flow.is_title_visible(), get_tree().paused])

	var level_up_ui: Variant = auto_setup["level_up_ui"]
	var history_before_value: Variant = level_up_ui.get("chosen_history")
	var history_before: int = history_before_value.size() if history_before_value is Array else 0
	var level_up_triggered: bool = _trigger_level_up(auto_setup["player"])
	# 경험치를 한 번에 많이 주면 레벨업이 여러 번 대기열에 쌓이고,
	# 하나를 고르면 곧바로 다음 화면이 뜬다. 대기열이 빌 때까지 프레임을 진행한다.
	if level_up_triggered:
		# 자동 선택은 프레임당 1회이고, 업그레이드가 전부 상한에 도달할 때까지
		# 대기열이 남는다. 넉넉히 돌린다.
		for _frame in range(300):
			await get_tree().process_frame
			if not bool(level_up_ui.get("visible")):
				break
	var history_after_value: Variant = level_up_ui.get("chosen_history")
	var history_after: int = history_after_value.size() if history_after_value is Array else 0
	var chosen_id: Variant = "none"
	if history_after > 0:
		chosen_id = history_after_value[history_after - 1]
	var level_up_visible: bool = bool(level_up_ui.get("visible"))
	_record("auto_play_picks_upgrade", level_up_triggered and history_after > history_before and not level_up_visible,
		"triggered=%s chosen_id=%s history_length=%d visible=%s" % [level_up_triggered, str(chosen_id), history_after, level_up_visible])
	await _cleanup(auto_setup)
	_finish()


func _build_flow() -> Dictionary:
	get_tree().paused = false
	var player: Variant = PLAYER_SCENE.instantiate()
	var hud: Variant = HUD_SCENE.instantiate()
	var level_up_ui: Variant = LEVEL_UP_UI_SCENE.instantiate()
	var flow: Variant = FLOW_SCENE.instantiate()
	if player == null or hud == null or level_up_ui == null or flow == null:
		return {}
	player.name = "Player"
	hud.name = "HUD"
	level_up_ui.name = "LevelUpUI"
	flow.name = "GameFlow"
	_set_export_if_present(hud, &"player_path", NodePath("../Player"))
	_set_export_if_present(hud, &"player_node_path", NodePath("../Player"))
	_set_export_if_present(level_up_ui, &"player_path", NodePath("../Player"))
	_set_export_if_present(level_up_ui, &"player_node_path", NodePath("../Player"))
	_set_export_if_present(level_up_ui, &"level_system_path", NodePath("../Player/LevelSystem"))
	# HUD의 나머지 경로도 채운다. 비워두면 push_error 잡음이 나고
	# 결과 요약의 '도달 레벨'이 0으로 표시된다.
	_set_export_if_present(hud, &"level_system_path", NodePath("../Player/LevelSystem"))
	_set_export_if_present(hud, &"enemy_container_path", NodePath("../EnemyContainer"))
	var enemy_container := Node2D.new()
	enemy_container.name = "EnemyContainer"
	add_child(enemy_container)
	add_child(player)
	add_child(hud)
	add_child(level_up_ui)
	# Assign exported paths before GameFlow enters the tree and runs _ready().
	flow.player_path = NodePath("../Player")
	flow.hud_path = NodePath("../HUD")
	flow.level_up_ui_path = NodePath("../LevelUpUI")
	add_child(flow)
	await get_tree().process_frame
	return {"player": player, "hud": hud, "level_up_ui": level_up_ui, "flow": flow}


func _set_export_if_present(target: Variant, property_name: StringName, value: Variant) -> void:
	for property_info: Dictionary in target.get_property_list():
		if property_info.get("name") == property_name:
			target.set(property_name, value)
			return


func _trigger_level_up(player: Variant) -> bool:
	var method_names: Array[StringName] = [&"gain_experience", &"add_experience", &"add_xp", &"gain_xp"]
	for method_name: StringName in method_names:
		if player.has_method(method_name):
			player.call(method_name, 99999)
			return true
	var level_system: Variant = player.get_node_or_null("LevelSystem")
	if level_system == null:
		level_system = player.get_node_or_null("Level")
	if level_system != null:
		for method_name: StringName in method_names:
			if level_system.has_method(method_name):
				level_system.call(method_name, 99999)
				return true
	return false


func _cleanup(setup: Dictionary) -> void:
	get_tree().paused = false
	for child_name: StringName in [&"flow", &"level_up_ui", &"hud", &"player"]:
		var child: Variant = setup.get(child_name)
		if is_instance_valid(child):
			child.queue_free()
	await get_tree().process_frame


func _record(case_name: String, success: bool, detail: String) -> void:
	recorded_cases += 1
	if success:
		passed += 1
		print("TEST_CASE %s PASS %s" % [case_name, detail])
	else:
		failed += 1
		print("TEST_CASE %s FAIL %s" % [case_name, detail])


func _record_skip(case_name: String, detail: String) -> void:
	recorded_cases += 1
	skipped += 1
	print("TEST_CASE %s SKIP %s" % [case_name, detail])


func _finish() -> void:
	get_tree().paused = false
	if recorded_cases != EXPECTED_CASE_COUNT:
		print("TEST_ERROR missing_cases expected=%d recorded=%d" % [EXPECTED_CASE_COUNT, recorded_cases])
		failed += 1
	var success: bool = failed == 0 and passed > 0
	print("TEST_RESULT %s passed=%d failed=%d skipped=%d" % ["PASS" if success else "FAIL", passed, failed, skipped])
	get_tree().quit(0 if success else 1)
