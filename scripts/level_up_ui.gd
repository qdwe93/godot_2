extends CanvasLayer

signal upgrade_chosen(id: StringName)

@export var level_system_path: NodePath

var last_choice: StringName = &""
var chosen_history: Array[StringName] = []

var _level_system: Node
var _pending_levels: Array[int] = []
var _choice_ids: Array[StringName] = []


func _ready() -> void:
	_level_system = get_node_or_null(level_system_path)
	if _level_system == null:
		push_error("LevelUpUI: level_system_path did not resolve: %s" % level_system_path)
		visible = false
		process_mode = Node.PROCESS_MODE_DISABLED
		return
	if not _level_system.has_signal(&"leveled_up"):
		push_error("LevelUpUI: resolved level system lacks leveled_up signal: %s" % level_system_path)
		visible = false
		process_mode = Node.PROCESS_MODE_DISABLED
		return
	var connect_error: Error = _level_system.connect(&"leveled_up", Callable(self, "_on_leveled_up"))
	if connect_error != OK:
		push_error("LevelUpUI: failed to connect leveled_up signal (error %d)" % connect_error)
		visible = false
		process_mode = Node.PROCESS_MODE_DISABLED


func _on_leveled_up(new_level: int) -> void:
	_pending_levels.append(new_level)
	if not visible:
		_show_next_level_up()


func _show_next_level_up() -> void:
	while not _pending_levels.is_empty():
		var level_number: int = _pending_levels.pop_front()
		_choice_ids.clear()
		var available: Array[StringName] = _get_available_upgrade_ids()
		for choice_index in range(3):
			var button: Button = get_node("Choices/Choice%d" % choice_index)
			button.visible = false

		if available.is_empty():
			visible = false
			print("LEVELUP_UI_SKIPPED level=%d" % level_number)
			continue

		var choice_count: int = mini(3, available.size())
		for choice_index in range(choice_count):
			var random_index: int = randi_range(0, available.size() - 1)
			var upgrade_id: StringName = available.pop_at(random_index)
			var definition: Dictionary = UpgradeData.get_definition(upgrade_id)
			var upgrade_label: String = str(definition.get("label", str(upgrade_id)))
			_choice_ids.append(upgrade_id)
			var button: Button = get_node("Choices/Choice%d" % choice_index)
			button.text = upgrade_label
			button.visible = true
		visible = true
		get_tree().paused = true
		print("LEVELUP_UI_SHOWN level=%d choices=%s" % [level_number, _choice_text()])
		return

	visible = false
	get_tree().paused = false


func _get_available_upgrade_ids() -> Array[StringName]:
	var available: Array[StringName] = []
	var upgrade_manager: Node = get_tree().get_first_node_in_group("upgrade_manager")
	for upgrade_id in UpgradeData.get_all_ids():
		var definition: Dictionary = UpgradeData.get_definition(upgrade_id)
		var max_level: int = int(definition.get("max_level", 0))
		var current_level: int = 0
		if is_instance_valid(upgrade_manager) and upgrade_manager.has_method("get_level"):
			current_level = int(upgrade_manager.call("get_level", upgrade_id))
		if current_level < max_level:
			available.append(upgrade_id)
	return available


func get_choice_ids() -> Array[StringName]:
	var copied_ids: Array[StringName] = []
	copied_ids.append_array(_choice_ids)
	return copied_ids


func choose(index: int) -> void:
	if not visible or index < 0 or index >= _choice_ids.size():
		push_error("LevelUpUI: invalid choice index %d" % index)
		return
	var chosen_id: StringName = _choice_ids[index]
	last_choice = chosen_id
	chosen_history.append(chosen_id)
	visible = false
	emit_signal(&"upgrade_chosen", chosen_id)
	print("LEVELUP_UI_CHOSEN id=%s queued=%d" % [chosen_id, _pending_levels.size()])
	if _pending_levels.is_empty():
		get_tree().paused = false
	else:
		_show_next_level_up()


func _choice_text() -> String:
	var choice_texts: PackedStringArray = []
	for choice_id in _choice_ids:
		choice_texts.append(str(choice_id))
	return ",".join(choice_texts)


func _on_choice_0_pressed() -> void:
	choose(0)


func _on_choice_1_pressed() -> void:
	choose(1)


func _on_choice_2_pressed() -> void:
	choose(2)
