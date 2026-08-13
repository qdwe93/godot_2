extends Node

const EXPECTED_CASE_COUNT: int = 6
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy.tscn")

var _recorded_cases: int = 0
var _passed_cases: int = 0
var _failed_cases: int = 0
var _skipped_cases: int = 0
var _main: Node = null


func _ready() -> void:
	await _run_tests()


func _run_tests() -> void:
	if MAIN_SCENE == null or ENEMY_SCENE == null:
		print("TEST_ERROR setup_failed required scene resource could not be loaded")
		_finish()
		return

	_main = MAIN_SCENE.instantiate()
	if _main == null:
		print("TEST_ERROR setup_failed main scene could not be instantiated")
		_finish()
		return
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame

	await _case_all_upgrades_are_offerable()
	await _case_required_groups_exist()
	await _case_cross_node_methods_exist()
	await _case_player_child_nodes_exist()
	await _case_required_signals_exist()
	await _case_boss_drops_experience()
	await _dispose_main()
	_finish()


func _case_all_upgrades_are_offerable() -> void:
	var missing_ids: PackedStringArray = []
	var upgrade_manager: Node = get_tree().get_first_node_in_group(&"upgrade_manager")
	var level_up_ui: Node = _main.get_node_or_null("LevelUpUI")
	# 레벨업 UI가 실제로 제안할 수 있는 목록을 직접 뽑는다. 이 조회가 없으면
	# "정의는 있는데 화면에 안 나오는" 버그(산탄·궤도구)를 그대로 통과시킨다.
	var has_testing_accessor: bool = level_up_ui != null and level_up_ui.has_method(&"_get_available_upgrade_ids")
	var offered_ids: Array[StringName] = []
	if has_testing_accessor:
		var candidate_ids: Variant = level_up_ui.call(&"_get_available_upgrade_ids")
		if candidate_ids is Array:
			for candidate_id in candidate_ids:
				offered_ids.append(StringName(candidate_id))
	else:
		missing_ids.append("level_up_ui._get_available_upgrade_ids")
	if upgrade_manager == null:
		missing_ids.append("upgrade_manager")
	for upgrade_id in UpgradeData.get_all_ids():
		var definition: Dictionary = UpgradeData.get_definition(upgrade_id)
		var max_level: int = int(definition.get("max_level", 0))
		var manager_accepts_id: bool = upgrade_manager != null and definition.is_empty() == false
		var ui_offers_id: bool = not has_testing_accessor or offered_ids.has(upgrade_id)
		if definition.is_empty() or max_level < 1 or not manager_accepts_id or not ui_offers_id:
			missing_ids.append(str(upgrade_id))
	var passed: bool = missing_ids.is_empty()
	_record_case("all_upgrades_are_offerable", passed, "missing_ids=%s" % ",".join(missing_ids))
	await get_tree().process_frame


func _case_required_groups_exist() -> void:
	var required_groups: Array[StringName] = [
		&"upgrade_manager",
		&"pickup_spawner",
		&"projectile_container",
		&"screen_shake",
		&"effect_spawner",
	]
	var missing_groups: PackedStringArray = []
	for group_name in required_groups:
		var group_nodes: Array[Node] = get_tree().get_nodes_in_group(group_name)
		if group_nodes.is_empty():
			missing_groups.append(str(group_name))
	var passed: bool = missing_groups.is_empty()
	_record_case("required_groups_exist", passed, "missing_groups=%s" % ",".join(missing_groups))
	await get_tree().process_frame


func _case_cross_node_methods_exist() -> void:
	var requirements: Array[Dictionary] = [
		{"group": &"pickup_spawner", "methods": [&"on_enemy_died"]},
		{"group": &"upgrade_manager", "methods": [&"get_level", &"get_experience_multiplier"]},
		{"group": &"screen_shake", "methods": [&"shake"]},
		{"group": &"effect_spawner", "methods": [&"spawn_hit", &"spawn_death"]},
	]
	var missing_methods: PackedStringArray = []
	for requirement in requirements:
		var group_name: StringName = requirement.get("group", &"")
		var methods: Array = requirement.get("methods", [])
		var group_nodes: Array[Node] = get_tree().get_nodes_in_group(group_name)
		if group_nodes.is_empty():
			for method_name: StringName in methods:
				missing_methods.append("%s.%s" % [group_name, method_name])
			continue
		for method_name: StringName in methods:
			var method_found: bool = false
			for group_node in group_nodes:
				if group_node.has_method(method_name):
					method_found = true
					break
			if not method_found:
				missing_methods.append("%s.%s" % [group_name, method_name])
	var passed: bool = missing_methods.is_empty()
	_record_case("cross_node_methods_exist", passed, "missing_methods=%s" % ",".join(missing_methods))
	await get_tree().process_frame


func _case_player_child_nodes_exist() -> void:
	var player: Node = _main.get_node_or_null("Player")
	var required_paths: Array[String] = [
		"Weapon",
		"Shotgun",
		"Orbital",
		"MagnetArea/CollisionShape2D",
		"LevelSystem",
		"Hurtbox",
	]
	var missing_paths: PackedStringArray = []
	for required_path in required_paths:
		var child_node: Node = player.get_node_or_null(required_path) if player != null else null
		if child_node == null:
			missing_paths.append("Player/%s" % required_path)
	var passed: bool = missing_paths.is_empty()
	_record_case("player_child_nodes_exist", passed, "missing_paths=%s" % ",".join(missing_paths))
	await get_tree().process_frame


func _case_required_signals_exist() -> void:
	var player: Node = _main.get_node_or_null("Player")
	var level_system: Node = player.get_node_or_null("LevelSystem") if player != null else null
	var level_up_ui: Node = _main.get_node_or_null("LevelUpUI")
	var enemy: Node = ENEMY_SCENE.instantiate()
	var missing_signals: PackedStringArray = []
	_check_signal(player, &"health_changed", "Player", missing_signals)
	_check_signal(player, &"died", "Player", missing_signals)
	_check_signal(level_system, &"experience_changed", "Player/LevelSystem", missing_signals)
	_check_signal(level_system, &"leveled_up", "Player/LevelSystem", missing_signals)
	_check_signal(level_up_ui, &"upgrade_chosen", "LevelUpUI", missing_signals)
	_check_signal(enemy, &"died", "Enemy", missing_signals)
	if is_instance_valid(enemy):
		enemy.queue_free()
	var passed: bool = missing_signals.is_empty()
	_record_case("required_signals_exist", passed, "missing_signals=%s" % ",".join(missing_signals))
	await get_tree().process_frame


func _case_boss_drops_experience() -> void:
	var boss_spawner: Node = _main.get_node_or_null("BossSpawner")
	var boss: Node = boss_spawner.call(&"spawn_boss_now") if boss_spawner != null and boss_spawner.has_method(&"spawn_boss_now") else null
	var connection_found: bool = false
	if boss != null and boss.has_signal(&"died"):
		var connections: Array = boss.get_signal_connection_list(&"died")
		for connection in connections:
			var callback: Callable = connection.get("callable", Callable())
			var target: Object = callback.get_object()
			if target is Node and (target as Node).is_in_group(&"pickup_spawner"):
				connection_found = true
				break
	if is_instance_valid(boss):
		boss.queue_free()
	var passed: bool = boss != null and connection_found
	_record_case("boss_drops_experience", passed, "boss_created=%s pickup_connection=%s" % [boss != null, connection_found])
	await get_tree().process_frame


func _check_signal(node: Node, signal_name: StringName, node_name: String, missing_signals: PackedStringArray) -> void:
	if node == null or not node.has_signal(signal_name):
		missing_signals.append("%s.%s" % [node_name, signal_name])


func _dispose_main() -> void:
	get_tree().paused = false
	if is_instance_valid(_main):
		_main.queue_free()
	await get_tree().process_frame
	_main = null


func _record_case(case_name: String, passed: bool, detail: String) -> void:
	_recorded_cases += 1
	if passed:
		_passed_cases += 1
		print("TEST_CASE %s PASS %s" % [case_name, detail])
	else:
		_failed_cases += 1
		print("TEST_CASE %s FAIL %s" % [case_name, detail])


func _finish() -> void:
	get_tree().paused = false
	if _recorded_cases != EXPECTED_CASE_COUNT:
		print("TEST_ERROR missing_cases expected=%d recorded=%d" % [EXPECTED_CASE_COUNT, _recorded_cases])
		_failed_cases += 1
	var succeeded: bool = _passed_cases > 0 and _failed_cases == 0 and _recorded_cases == EXPECTED_CASE_COUNT
	var status: String = "PASS" if succeeded else "FAIL"
	print("TEST_RESULT %s passed=%d failed=%d skipped=%d" % [status, _passed_cases, _failed_cases, _skipped_cases])
	get_tree().quit(0 if succeeded else 1)
