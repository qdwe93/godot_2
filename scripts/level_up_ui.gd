extends CanvasLayer

signal upgrade_chosen(id: StringName)

@export var level_system_path: NodePath

const UPGRADE_POOL: Array[Dictionary] = [
	{"id": &"shoes", "label": "신발 - 이동 속도 +10%"},
	{"id": &"heart", "label": "심장 - 최대 HP +20"},
	{"id": &"magnet", "label": "자석 - 수집 범위 +30%"},
	{"id": &"gloves", "label": "장갑 - 공격 쿨다운 -8%"},
	{"id": &"crown", "label": "왕관 - 경험치 획득 +10%"},
]

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
	if _pending_levels.is_empty():
		return
	var level_number: int = _pending_levels.pop_front()
	_choice_ids.clear()
	var available: Array[Dictionary] = UPGRADE_POOL.duplicate()
	for choice_index in range(3):
		var random_index: int = randi_range(0, available.size() - 1)
		var upgrade: Dictionary = available.pop_at(random_index)
		var upgrade_id: StringName = upgrade["id"]
		var upgrade_label: String = upgrade["label"]
		_choice_ids.append(upgrade_id)
		var button: Button = get_node("Choices/Choice%d" % choice_index)
		button.text = upgrade_label
	visible = true
	get_tree().paused = true
	print("LEVELUP_UI_SHOWN level=%d choices=%s" % [level_number, _choice_text()])


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
