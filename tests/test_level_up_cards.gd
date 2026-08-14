extends Node

## M17 — 레벨업 화면을 카드 형태로 바꾸면서 생긴 **관계**를 고정한다.
##
## 사용자가 목표로 준 레퍼런스(docs/REFERENCE_UI.md)의 구조다. 여기서 검사하는 것은
## 픽셀이 아니라 "무엇이 무엇을 따라가는가"다.
##
##   - 카드의 이름·설명은 `UpgradeData` 의 라벨에서 갈라 나온다 (두 벌로 저장하지 않는다)
##   - 별 개수는 그 업그레이드의 `max_level` 이다. 값을 하드코딩하면 밸런스 조정이 막힌다
##   - 채워진 별은 **찍고 난 뒤의 레벨**이다
##   - 슬롯 바는 `UpgradeData` 의 정의에서 만들어진다. 업그레이드를 추가하면 슬롯도 늘어야 한다
##   - 카드 안의 라벨·아이콘이 터치를 먹으면 안 된다 — 이건 에러 없이 조용히 깨지는 종류다

const EXPECTED_CASE_COUNT: int = 17
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const STAR_FULL_PATH: String = "res://assets/ui/star_full.png"

var _passed: int = 0
var _failed: int = 0
var _skipped: int = 0
var _recorded: int = 0
var _main: Node = null
var _ui: Node = null
var _manager: Node = null


func _ready() -> void:
	# 레벨업 UI가 트리를 멈춘 동안에도 입력 결과와 정리를 계속 검사한다.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_main = MAIN_SCENE.instantiate()
	if _main == null:
		print("TEST_ERROR setup_failed main_scene_could_not_instantiate")
		_finish()
		return
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame

	_ui = _main.get_node_or_null("LevelUpUI")
	_manager = _main.get_node_or_null("UpgradeManager")
	if _ui == null or _manager == null:
		print("TEST_ERROR setup_failed level_up_ui_or_upgrade_manager_missing")
		_finish()
		return

	_case_card_splits_name_and_description()
	_case_star_total_matches_max_level()
	_case_stars_show_level_after_pick()
	_case_new_badge_only_for_unowned()
	_case_slot_bar_covers_every_upgrade()
	_case_slot_shows_owned_level()
	_case_card_children_do_not_eat_taps()
	_case_every_upgrade_has_a_loadable_icon()
	await _case_real_input_path_reaches_the_number_keys()
	_case_number_keys_pick_the_matching_card()
	_case_number_keys_do_nothing_while_hidden()
	_case_number_key_past_the_last_choice_is_ignored()
	await _case_first_card_takes_focus()
	_case_confetti_survives_the_pause()
	_case_confetti_is_drawn_and_not_dust()
	_case_confetti_covers_the_screen_width()
	_case_key_badges_match_the_number_keys()

	_main.free()
	_finish()


func _finish() -> void:
	if _recorded != EXPECTED_CASE_COUNT:
		print("TEST_ERROR missing_cases expected=%d recorded=%d" % [EXPECTED_CASE_COUNT, _recorded])
		_failed += 1
	var overall: String = "PASS" if _failed == 0 and _passed > 0 and _recorded == EXPECTED_CASE_COUNT else "FAIL"
	print("TEST_RESULT %s passed=%d failed=%d skipped=%d" % [overall, _passed, _failed, _skipped])
	get_tree().quit(0 if overall == "PASS" else 1)


func _card(index: int) -> Button:
	return _ui.get_node_or_null("Choices/Choice%d" % index) as Button


func _fill(index: int, upgrade_id: StringName) -> void:
	_ui.call(&"_fill_card", index, upgrade_id)


func _acquire(upgrade_id: StringName) -> void:
	_manager.call(&"_on_upgrade_chosen", upgrade_id)


func _filled_star_count(index: int) -> int:
	var stars: Node = _card(index).get_node_or_null("Body/Stars")
	if stars == null:
		return -1
	var filled: int = 0
	for child in stars.get_children():
		var star: TextureRect = child as TextureRect
		if star != null and star.texture != null and star.texture.resource_path == STAR_FULL_PATH:
			filled += 1
	return filled


func _total_star_count(index: int) -> int:
	var stars: Node = _card(index).get_node_or_null("Body/Stars")
	return stars.get_child_count() if stars != null else -1


## 이름과 설명이 라벨 하나에서 갈라져 나오는가.
func _case_card_splits_name_and_description() -> void:
	var offenders: PackedStringArray = []
	for upgrade_id in UpgradeData.get_all_ids():
		_fill(0, upgrade_id)
		var label: String = str(UpgradeData.get_definition(upgrade_id).get("label", ""))
		var name_text: String = (_card(0).get_node("Body/Name") as Label).text
		var description_text: String = (_card(0).get_node("Body/Desc") as Label).text
		if name_text.is_empty() or description_text.is_empty():
			offenders.append("%s(빈칸)" % upgrade_id)
		elif name_text + " - " + description_text != label:
			offenders.append("%s(%s|%s)" % [upgrade_id, name_text, description_text])
	_record("card_splits_name_and_description", offenders.is_empty(),
		"검사 %d종 %s" % [UpgradeData.get_all_ids().size(),
			"ok" if offenders.is_empty() else ",".join(offenders)])


## 별 개수가 그 업그레이드의 max_level 과 같은가. **정의에서 읽어 온다.**
func _case_star_total_matches_max_level() -> void:
	var offenders: PackedStringArray = []
	var seen_totals: PackedStringArray = []
	for upgrade_id in UpgradeData.get_all_ids():
		_fill(0, upgrade_id)
		var expected: int = UpgradeData.get_max_level(upgrade_id)
		var actual: int = _total_star_count(0)
		seen_totals.append("%s=%d" % [upgrade_id, actual])
		if actual != expected:
			offenders.append("%s(%d!=%d)" % [upgrade_id, actual, expected])
	_record("star_total_matches_max_level", offenders.is_empty(),
		" ".join(seen_totals) if offenders.is_empty() else ",".join(offenders))


## 채워진 별이 "찍고 난 뒤의 레벨"인가.
func _case_stars_show_level_after_pick() -> void:
	var upgrade_id: StringName = &"blade"
	_fill(0, upgrade_id)
	var at_zero: int = _filled_star_count(0)

	_acquire(upgrade_id)
	_fill(0, upgrade_id)
	var at_one: int = _filled_star_count(0)

	_acquire(upgrade_id)
	_fill(0, upgrade_id)
	var at_two: int = _filled_star_count(0)

	_record("stars_show_level_after_pick", at_zero == 1 and at_one == 2 and at_two == 3,
		"레벨0->%d 레벨1->%d 레벨2->%d (각각 1,2,3 이어야 한다)" % [at_zero, at_one, at_two])


## New! 는 아직 한 번도 안 찍은 것에만 붙는가.
func _case_new_badge_only_for_unowned() -> void:
	var owned_id: StringName = &"blade"      # 앞 케이스에서 이미 2레벨이다
	var fresh_id: StringName = &"crown"

	_fill(0, fresh_id)
	var fresh_visible: bool = (_card(0).get_node("NewBadge") as Label).visible
	_fill(0, owned_id)
	var owned_visible: bool = (_card(0).get_node("NewBadge") as Label).visible

	_record("new_badge_only_for_unowned", fresh_visible and not owned_visible,
		"미획득=%s 보유중=%s" % [str(fresh_visible).to_lower(), str(owned_visible).to_lower()])


## 슬롯 바가 모든 업그레이드를 **빠짐없이 한 번씩** 담는가.
## 씬에 칸을 하드코딩하면 업그레이드를 추가해도 슬롯이 안 늘어나는데 에러는 안 난다.
func _case_slot_bar_covers_every_upgrade() -> void:
	_ui.call(&"_refresh_slot_bar")
	var slot_names: PackedStringArray = []
	for row_name in ["Slots/WeaponRow", "Slots/PassiveRow"]:
		var row: Node = _ui.get_node_or_null(row_name)
		if row == null:
			_record("slot_bar_covers_every_upgrade", false, "%s 없음" % row_name)
			return
		for child in row.get_children():
			slot_names.append(child.name)

	var missing: PackedStringArray = []
	for upgrade_id in UpgradeData.get_all_ids():
		if not slot_names.has(String(upgrade_id)):
			missing.append(String(upgrade_id))
	var duplicated: bool = slot_names.size() != UpgradeData.get_all_ids().size()

	_record("slot_bar_covers_every_upgrade", missing.is_empty() and not duplicated,
		"슬롯 %d개 / 업그레이드 %d종 %s" % [slot_names.size(), UpgradeData.get_all_ids().size(),
			"ok" if missing.is_empty() and not duplicated else "빠짐=" + ",".join(missing)])


## 보유한 슬롯만 레벨 숫자를 달고 있는가.
func _case_slot_shows_owned_level() -> void:
	_acquire(&"shotgun")
	_ui.call(&"_refresh_slot_bar")

	var shotgun_slot: Node = _ui.get_node_or_null("Slots/WeaponRow/shotgun")
	var orbital_slot: Node = _ui.get_node_or_null("Slots/WeaponRow/orbital")
	if shotgun_slot == null or orbital_slot == null:
		_record("slot_shows_owned_level", false, "무기 슬롯을 못 찾았다")
		return

	var owned_label: Label = shotgun_slot.get_node_or_null("Level") as Label
	var unowned_label: Label = orbital_slot.get_node_or_null("Level") as Label
	var owned_text: String = owned_label.text if owned_label != null else "<없음>"

	_record("slot_shows_owned_level",
		owned_label != null and owned_text == "1" and unowned_label == null,
		"보유(산탄)=%s 미보유(궤도구)=%s" % [owned_text, "없음" if unowned_label == null else "있음"])


## 카드 안의 라벨·아이콘이 터치를 먹지 않는가.
##
## 이건 **에러 없이 조용히 깨지는** 종류다. 라벨 하나가 mouse_filter 를 STOP 으로
## 두고 있으면 그 위를 누른 손가락은 버튼에 닿지 않는다. 화면은 멀쩡해 보이고
## "가끔 안 눌린다"가 된다.
func _case_card_children_do_not_eat_taps() -> void:
	var offenders: PackedStringArray = []
	for index in range(3):
		var card: Button = _card(index)
		if card == null:
			offenders.append("Choice%d(없음)" % index)
			continue
		for node in _descendants(card):
			var control: Control = node as Control
			# STOP 만 실제로 터치를 삼킨다. PASS 는 부모까지 흘려보내므로 무해하다.
			# 무해한 설정까지 실패로 만들면 나중에 이 테스트가 방해만 된다.
			if control != null and control.mouse_filter == Control.MOUSE_FILTER_STOP:
				offenders.append("Choice%d/%s(filter=%d)" % [index, control.name, control.mouse_filter])
	_record("card_children_do_not_eat_taps", offenders.is_empty(),
		"ok" if offenders.is_empty() else ",".join(offenders))


## 아이콘이 **실제로 카드에 올라가는가.**
##
## 경로만 정의해 두고 배선이 끊긴 채로 두는 실수를 이 프로젝트에서 세 번 했다
## (산탄·궤도구 미노출, spawn_hit 호출처 0건, 보스 드랍 메서드 이름 불일치).
## 오타 하나면 카드 한가운데가 조용히 비어 있게 된다 — 에러는 안 난다.
func _case_every_upgrade_has_a_loadable_icon() -> void:
	var offenders: PackedStringArray = []
	for upgrade_id in UpgradeData.get_all_ids():
		var path: String = UpgradeData.get_icon_path(upgrade_id)
		if path.is_empty():
			offenders.append("%s(경로없음)" % upgrade_id)
			continue
		if not ResourceLoader.exists(path):
			offenders.append("%s(파일없음 %s)" % [upgrade_id, path])
			continue
		_fill(0, upgrade_id)
		var icon: TextureRect = _card(0).get_node_or_null("Body/Icon") as TextureRect
		if icon == null or icon.texture == null:
			offenders.append("%s(카드에 안 올라감)" % upgrade_id)
	_record("every_upgrade_has_a_loadable_icon", offenders.is_empty(),
		"검사 %d종 %s" % [UpgradeData.get_all_ids().size(),
			"ok" if offenders.is_empty() else ",".join(offenders)])


## Viewport 에 넣은 실제 입력이 _unhandled_key_input 까지 도달하는가.
## 테스트 훅만 부르면 핸들러 등록 자체가 빠진 결함을 잡지 못한다.
func _case_real_input_path_reaches_the_number_keys() -> void:
	var choice_ids: Array[StringName] = _show_level_up_for_testing()
	if choice_ids.is_empty():
		_record("real_input_path_reaches_the_number_keys", false, "choices=0 화면을 띄우지 못했다")
		_hide_level_up_for_testing()
		return
	var expected_id: StringName = choice_ids[0]
	var history_before: int = _chosen_history_size()
	_ui.set(&"last_choice", &"")
	get_viewport().push_input(_number_key_event(1))
	await get_tree().process_frame
	var last_choice: StringName = StringName(_ui.get(&"last_choice"))
	var history_after: int = _chosen_history_size()
	var reached: bool = last_choice == expected_id and history_after == history_before + 1
	var detail: String = "display=%s choices=%d expected=%s last=%s history=%d->%d" % [DisplayServer.get_name(), choice_ids.size(), expected_id, last_choice, history_before, history_after]
	# 헤드리스에서 SKIP 으로 빠지는 도피로를 두지 마라. `push_input` 은 헤드리스에서
	# **동작한다** (측정했다). 도피로가 있으면 배선이 진짜로 끊겼을 때 —
	# `_unhandled_key_input` 이라는 가상 함수 이름을 잘못 적는 실수는 에러가 안 난다 —
	# 케이스가 FAIL 이 아니라 SKIP 으로 내려앉아 스위트가 초록불을 준다.
	# 실제로 고장 주입에서 그렇게 놓쳤다.
	_record("real_input_path_reaches_the_number_keys", reached, detail)
	_hide_level_up_for_testing()


func _case_number_keys_pick_the_matching_card() -> void:
	var choice_ids: Array[StringName] = _show_level_up_for_testing()
	if choice_ids.size() < 2:
		_record("number_keys_pick_the_matching_card", false, "choices=%d 두 번째 선택지 없음" % choice_ids.size())
		_hide_level_up_for_testing()
		return
	var expected_id: StringName = choice_ids[1]
	_ui.set(&"last_choice", &"")
	_ui.call(&"feed_key_event_for_testing", _number_key_event(2))
	var last_choice: StringName = StringName(_ui.get(&"last_choice"))
	_record("number_keys_pick_the_matching_card", last_choice == expected_id,
		"choices=%s expected_index=1 expected=%s last=%s" % [choice_ids, expected_id, last_choice])
	_hide_level_up_for_testing()


func _case_number_keys_do_nothing_while_hidden() -> void:
	_hide_level_up_for_testing()
	var history_before: int = _chosen_history_size()
	var signal_counts: Array[int] = [0]
	var signal_counter: Callable = func(_upgrade_id: StringName) -> void:
		signal_counts[0] += 1
	_ui.connect(&"upgrade_chosen", signal_counter)
	_ui.call(&"feed_key_event_for_testing", _number_key_event(1))
	var history_after: int = _chosen_history_size()
	if _ui.is_connected(&"upgrade_chosen", signal_counter):
		_ui.disconnect(&"upgrade_chosen", signal_counter)
	_record("number_keys_do_nothing_while_hidden",
		history_after == history_before and signal_counts[0] == 0,
		"visible=%s history=%d->%d signals=%d" % [bool(_ui.get(&"visible")), history_before, history_after, signal_counts[0]])


func _case_number_key_past_the_last_choice_is_ignored() -> void:
	var isolated_main: Node = MAIN_SCENE.instantiate()
	if isolated_main == null:
		_record("number_key_past_the_last_choice_is_ignored", false,
			"선택지 2개용 메인 씬을 만들지 못함")
		return

	_manager.remove_from_group(&"upgrade_manager")
	add_child(isolated_main)
	var level_up_ui: Node = isolated_main.get_node_or_null("LevelUpUI")
	var manager: Node = isolated_main.get_node_or_null("UpgradeManager")
	if level_up_ui == null or manager == null:
		_record("number_key_past_the_last_choice_is_ignored", false,
			"선택지 2개용 UI 또는 업그레이드 매니저를 찾지 못함")
		_dispose_level_up_fixture(isolated_main)
		return

	for upgrade_id in UpgradeData.get_all_ids():
		if upgrade_id == &"shoes" or upgrade_id == &"heart":
			continue
		var definition: Dictionary = UpgradeData.get_definition(upgrade_id)
		var max_level: int = int(definition.get("max_level", 0))
		for level_index in range(max_level):
			manager.call(&"_on_upgrade_chosen", upgrade_id)

	level_up_ui.call(&"_on_leveled_up", 1)
	var choice_values: Variant = level_up_ui.call(&"get_choice_ids")
	var choice_count: int = choice_values.size() if choice_values is Array else -1
	if choice_count != 2:
		_record_skip("number_key_past_the_last_choice_is_ignored",
			"선택지를 2개로 만들지 못함 choices=%d" % choice_count)
		_dispose_level_up_fixture(isolated_main)
		return

	var history_value: Variant = level_up_ui.get(&"chosen_history")
	var history_before: int = history_value.size() if history_value is Array else -1
	var signal_counts: Array[int] = [0]
	var signal_counter: Callable = func(_upgrade_id: StringName) -> void:
		signal_counts[0] += 1
	level_up_ui.connect(&"upgrade_chosen", signal_counter)
	level_up_ui.call(&"feed_key_event_for_testing", _number_key_event(3))
	history_value = level_up_ui.get(&"chosen_history")
	var history_after: int = history_value.size() if history_value is Array else -1
	var stayed_visible: bool = bool(level_up_ui.get(&"visible"))
	if level_up_ui.is_connected(&"upgrade_chosen", signal_counter):
		level_up_ui.disconnect(&"upgrade_chosen", signal_counter)
	_record("number_key_past_the_last_choice_is_ignored",
		history_after == history_before and signal_counts[0] == 0 and stayed_visible,
		"choices=%d pressed=3 history=%d->%d signals=%d visible=%s" % [choice_count, history_before, history_after, signal_counts[0], stayed_visible])
	_dispose_level_up_fixture(isolated_main)


func _case_first_card_takes_focus() -> void:
	var choice_ids: Array[StringName] = _show_level_up_for_testing()
	await get_tree().process_frame
	var first_card: Button = _ui.get_node_or_null("Choices/Choice0") as Button
	var focused: bool = first_card != null and first_card.has_focus()
	_record("first_card_takes_focus", not choice_ids.is_empty() and focused,
		"choices=%d card_found=%s focused=%s" % [choice_ids.size(), first_card != null, focused])
	_hide_level_up_for_testing()


func _case_confetti_survives_the_pause() -> void:
	var confetti: CPUParticles2D = _ui.get_node_or_null("Confetti") as CPUParticles2D
	var choice_ids: Array[StringName] = _show_level_up_for_testing()
	var mode: int = confetti.process_mode if confetti != null else -1
	var emitting_while_shown: bool = confetti != null and confetti.emitting
	var paused_while_shown: bool = get_tree().paused
	if not choice_ids.is_empty():
		_ui.call(&"choose", 0)
	var emitting_after_choice: bool = confetti != null and confetti.emitting
	_record("confetti_survives_the_pause",
		confetti != null and mode == Node.PROCESS_MODE_ALWAYS and paused_while_shown and emitting_while_shown and not emitting_after_choice,
		"found=%s mode=%d expected_mode=%d paused=%s shown_emitting=%s after_choice_emitting=%s choices=%d" % [confetti != null, mode, Node.PROCESS_MODE_ALWAYS, paused_while_shown, emitting_while_shown, emitting_after_choice, choice_ids.size()])
	_hide_level_up_for_testing()


func _case_confetti_is_drawn_and_not_dust() -> void:
	var confetti: CPUParticles2D = _ui.get_node_or_null("Confetti") as CPUParticles2D
	var texture: Texture2D = confetti.texture if confetti != null else null
	var width: int = texture.get_width() if texture != null else -1
	var height: int = texture.get_height() if texture != null else -1
	var has_ramp: bool = confetti != null and confetti.color_initial_ramp != null
	_record("confetti_is_drawn_and_not_dust",
		confetti != null and texture != null and has_ramp and width != height,
		"found=%s texture=%s size=%dx%d ramp=%s" % [confetti != null, texture != null, width, height, has_ramp])


func _case_confetti_covers_the_screen_width() -> void:
	var confetti: CPUParticles2D = _ui.get_node_or_null("Confetti") as CPUParticles2D
	var arena_size: Vector2 = Arena.get_size(_ui)
	var emission_width: float = confetti.emission_rect_extents.x * 2.0 if confetti != null else -1.0
	_record("confetti_covers_the_screen_width",
		confetti != null and emission_width >= arena_size.x,
		"emission_width=%.1f arena_width=%.1f extents_x=%.1f" % [emission_width, arena_size.x, confetti.emission_rect_extents.x if confetti != null else -1.0])


func _case_key_badges_match_the_number_keys() -> void:
	var offenders: PackedStringArray = []
	var observed: PackedStringArray = []
	for index: int in range(3):
		var badge: Label = _ui.get_node_or_null("Choices/Choice%d/KeyBadge" % index) as Label
		var expected_text: String = str(index + 1)
		var actual_text: String = badge.text if badge != null else "<없음>"
		var mouse_filter: int = badge.mouse_filter if badge != null else -1
		observed.append("%d:%s/filter=%d" % [index, actual_text, mouse_filter])
		if badge == null or actual_text != expected_text or mouse_filter != Control.MOUSE_FILTER_IGNORE:
			offenders.append("Choice%d(expected=%s actual=%s filter=%d)" % [index, expected_text, actual_text, mouse_filter])
	_record("key_badges_match_the_number_keys", offenders.is_empty(),
		"badges=[%s] offenders=[%s]" % [",".join(observed), ",".join(offenders)])


func _show_level_up_for_testing() -> Array[StringName]:
	_ui.call(&"_on_leveled_up", _chosen_history_size() + 2)
	var choice_values: Variant = _ui.call(&"get_choice_ids")
	var choice_ids: Array[StringName] = []
	if choice_values is Array:
		for value: Variant in choice_values:
			choice_ids.append(StringName(value))
	return choice_ids


func _hide_level_up_for_testing() -> void:
	_ui.set(&"visible", false)
	var confetti: CPUParticles2D = _ui.get_node_or_null("Confetti") as CPUParticles2D
	if confetti != null:
		confetti.emitting = false
	get_tree().paused = false


func _dispose_level_up_fixture(isolated_main: Node) -> void:
	get_tree().paused = false
	if is_instance_valid(isolated_main):
		isolated_main.free()
	if is_instance_valid(_manager) and not _manager.is_in_group(&"upgrade_manager"):
		_manager.add_to_group(&"upgrade_manager")


func _chosen_history_size() -> int:
	var history_value: Variant = _ui.get(&"chosen_history")
	return history_value.size() if history_value is Array else -1


func _number_key_event(choice_number: int) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.pressed = true
	event.echo = false
	match choice_number:
		1:
			event.keycode = KEY_1
		2:
			event.keycode = KEY_2
		3:
			event.keycode = KEY_3
	return event


func _descendants(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child in node.get_children():
		found.append(child)
		found.append_array(_descendants(child))
	return found


func _record(case_name: String, ok: bool, detail: String) -> void:
	_recorded += 1
	if ok:
		_passed += 1
		print("TEST_CASE %s PASS %s" % [case_name, detail])
	else:
		_failed += 1
		print("TEST_CASE %s FAIL %s" % [case_name, detail])


func _record_skip(case_name: String, detail: String) -> void:
	_recorded += 1
	_skipped += 1
	print("TEST_CASE %s SKIP %s" % [case_name, detail])
