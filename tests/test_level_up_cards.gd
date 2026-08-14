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

const EXPECTED_CASE_COUNT: int = 7
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
			if control != null and control.mouse_filter != Control.MOUSE_FILTER_IGNORE:
				offenders.append("Choice%d/%s(filter=%d)" % [index, control.name, control.mouse_filter])
	_record("card_children_do_not_eat_taps", offenders.is_empty(),
		"ok" if offenders.is_empty() else ",".join(offenders))


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
