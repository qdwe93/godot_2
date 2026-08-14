extends CanvasLayer

## 레벨업 선택 화면.
##
## M17에서 "가로 버튼 3줄"에서 **카드 3장 + 보유 슬롯 바**로 바꿨다. 사용자가
## 목표로 준 레퍼런스(docs/REFERENCE_UI.md)의 구조다. 카드에는 이름·아이콘·설명과
## 함께 **별 등급**이 붙는데, 이게 백로그에 오래 있던 "레벨업 버튼이 현재 레벨을
## 안 보여준다"를 해결한다. 별은 **찍고 난 뒤의 레벨**을 보여준다 — 지금 이 선택이
## 나를 어디까지 올려 주는지가 알고 싶은 것이기 때문이다.
##
## 슬롯 바는 `UpgradeData` 의 **정의 순서 그대로** 코드에서 만든다. 씬에 칸을
## 하드코딩하면 업그레이드를 추가해도 슬롯이 안 늘어나는데 에러는 안 난다.

signal upgrade_chosen(id: StringName)

@export var level_system_path: NodePath

const STAR_SIZE: Vector2 = Vector2(28.0, 28.0)
const SLOT_SIZE: Vector2 = Vector2(48.0, 48.0)
const STAR_FULL_PATH: String = "res://assets/ui/star_full.png"
const STAR_EMPTY_PATH: String = "res://assets/ui/star_empty.png"
const SLOT_EMPTY_PATH: String = "res://assets/ui/slot_empty.png"

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
			_choice_ids.append(upgrade_id)
			_fill_card(choice_index, upgrade_id)
		_refresh_slot_bar()
		visible = true
		Audio.play_sfx(&"level_up")
		get_tree().paused = true
		print("LEVELUP_UI_SHOWN level=%d choices=%s" % [level_number, _choice_text()])
		return

	visible = false
	get_tree().paused = false


## 카드 한 장을 채운다.
func _fill_card(choice_index: int, upgrade_id: StringName) -> void:
	var button: Button = get_node("Choices/Choice%d" % choice_index)
	var current_level: int = get_upgrade_level(upgrade_id)
	var max_level: int = UpgradeData.get_max_level(upgrade_id)

	var name_label: Label = button.get_node_or_null("Body/Name") as Label
	if name_label != null:
		name_label.text = UpgradeData.get_display_name(upgrade_id)
	var description_label: Label = button.get_node_or_null("Body/Desc") as Label
	if description_label != null:
		description_label.text = UpgradeData.get_description(upgrade_id)
	var icon: TextureRect = button.get_node_or_null("Body/Icon") as TextureRect
	if icon != null:
		icon.texture = _load_texture(UpgradeData.get_icon_path(upgrade_id))
	var new_badge: Label = button.get_node_or_null("NewBadge") as Label
	if new_badge != null:
		# 아직 한 번도 안 찍은 것만 New. 레퍼런스와 같은 의미다.
		new_badge.visible = current_level <= 0

	# 별은 "찍고 난 뒤"의 레벨을 보여준다.
	_fill_stars(button.get_node_or_null("Body/Stars") as HBoxContainer,
		mini(current_level + 1, max_level), max_level)

	# 텍스트 버튼 시절의 잔재를 지운다. 남겨 두면 카드 위에 라벨이 겹쳐 나온다.
	button.text = ""
	button.visible = true


func _fill_stars(container: HBoxContainer, filled: int, total: int) -> void:
	if container == null:
		return
	_clear_children(container)
	for index in range(maxi(total, 0)):
		var star: TextureRect = TextureRect.new()
		star.custom_minimum_size = STAR_SIZE
		star.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		star.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		star.mouse_filter = Control.MOUSE_FILTER_IGNORE
		star.texture = _load_texture(STAR_FULL_PATH if index < filled else STAR_EMPTY_PATH)
		container.add_child(star)


## 보유 스킬 슬롯 바. 무기와 강화를 따로 줄지어 지금 빌드가 한눈에 보이게 한다.
##
## 업그레이드가 8종까지 늘었는데 "내가 뭘 갖고 있더라"를 볼 방법이 화면에 전혀
## 없었다. 레벨업 순간이 그걸 보여주기 가장 좋은 자리다.
func _refresh_slot_bar() -> void:
	_fill_slot_row(get_node_or_null("Slots/WeaponRow") as HBoxContainer,
		UpgradeData.get_ids_in_category(UpgradeData.CATEGORY_WEAPON))
	_fill_slot_row(get_node_or_null("Slots/PassiveRow") as HBoxContainer,
		UpgradeData.get_ids_in_category(UpgradeData.CATEGORY_PASSIVE))


func _fill_slot_row(row: HBoxContainer, upgrade_ids: Array[StringName]) -> void:
	if row == null:
		return
	_clear_children(row)
	for upgrade_id in upgrade_ids:
		var level: int = get_upgrade_level(upgrade_id)
		var slot: TextureRect = TextureRect.new()
		slot.name = String(upgrade_id)
		slot.custom_minimum_size = SLOT_SIZE
		slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 안 가진 것은 빈 칸으로 둔다. 아이콘을 흐리게 보여 주면 "가진 것"과
		# 헷갈리는데, 슬롯 바가 답해야 하는 질문은 오직 "뭘 가졌나"다.
		slot.texture = _load_texture(UpgradeData.get_icon_path(upgrade_id) if level > 0 else SLOT_EMPTY_PATH)
		row.add_child(slot)

		if level > 0:
			var level_label: Label = Label.new()
			level_label.name = "Level"
			level_label.text = str(level)
			level_label.add_theme_font_size_override(&"font_size", 18)
			level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			# 앵커 프리셋 대신 위치를 직접 준다. 슬롯 크기가 고정이라 이게 더 단순하고,
			# 값을 외워 쓰지 않아도 된다 (CLAUDE.md — enum 값을 기억으로 쓰지 말 것).
			level_label.position = Vector2(SLOT_SIZE.x - 16.0, SLOT_SIZE.y - 22.0)
			slot.add_child(level_label)


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.free()


## 업그레이드 매니저가 아직 없거나(테스트 픽스처) 사라졌어도 0을 돌려준다.
func get_upgrade_level(upgrade_id: StringName) -> int:
	var upgrade_manager: Node = get_tree().get_first_node_in_group("upgrade_manager")
	if is_instance_valid(upgrade_manager) and upgrade_manager.has_method("get_level"):
		return int(upgrade_manager.call("get_level", upgrade_id))
	return 0


## 없는 경로에 load() 를 부르면 에러가 stderr 로 나가 테스트 출력이 더러워진다.
func _load_texture(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _get_available_upgrade_ids() -> Array[StringName]:
	var available: Array[StringName] = []
	for upgrade_id in UpgradeData.get_all_ids():
		if get_upgrade_level(upgrade_id) < UpgradeData.get_max_level(upgrade_id):
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
