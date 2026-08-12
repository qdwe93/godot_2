extends Node

const EXPECTED_CASE_COUNT: int = 5
const EPSILON: float = 0.0001
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const LEVEL_UP_UI_SCENE: PackedScene = preload("res://scenes/level_up_ui.tscn")
const UPGRADE_MANAGER_SCRIPT: Script = preload("res://scripts/upgrade_manager.gd")

var _passed: int = 0
var _failed: int = 0
var _skipped: int = 0
var _recorded: int = 0
var _setup_error: bool = false


func _ready() -> void:
	# Fixtures are built here instead of relying on main.tscn, keeping this test
	# independent of gameplay spawners. Each upgrade is sent through the real
	# LevelUpUI.upgrade_chosen signal connection.
	await get_tree().process_frame
	_case_shoes_once()
	if _setup_error:
		return
	_case_shoes_compound_from_base()
	if _setup_error:
		return
	_case_heart_heals()
	if _setup_error:
		return
	_case_gloves_updates_live_timer()
	if _setup_error:
		return
	_case_magnet_does_not_mutate_shared_shape()
	if _setup_error:
		return

	if _recorded != EXPECTED_CASE_COUNT:
		print("TEST_ERROR missing_cases expected=%d recorded=%d" % [EXPECTED_CASE_COUNT, _recorded])
		_failed += 1

	var overall: String = "PASS" if _failed == 0 and _passed > 0 and _recorded == EXPECTED_CASE_COUNT else "FAIL"
	print("TEST_RESULT %s passed=%d failed=%d skipped=%d" % [overall, _passed, _failed, _skipped])
	get_tree().quit(0 if overall == "PASS" else 1)


func _make_fixture() -> Dictionary:
	var fixture_root: Node = Node.new()
	fixture_root.name = &"UpgradeFixture"
	add_child(fixture_root)

	var player: Node = PLAYER_SCENE.instantiate()
	player.name = &"Player"
	fixture_root.add_child(player)

	var level_up_ui: Node = LEVEL_UP_UI_SCENE.instantiate()
	level_up_ui.name = &"LevelUpUI"
	level_up_ui.set(&"level_system_path", NodePath("../Player/LevelSystem"))
	fixture_root.add_child(level_up_ui)

	var manager: Node = UPGRADE_MANAGER_SCRIPT.new()
	manager.name = &"UpgradeManager"
	manager.set(&"level_up_ui_path", NodePath("../LevelUpUI"))
	manager.set(&"player_path", NodePath("../Player"))
	fixture_root.add_child(manager)

	return {
		"root": fixture_root,
		"player": player,
		"ui": level_up_ui,
		"manager": manager,
	}


func _fixture_is_valid(fixture: Dictionary, needs_timer: bool = false) -> bool:
	var player: Node = fixture.get("player") as Node
	var level_up_ui: Node = fixture.get("ui") as Node
	var manager: Node = fixture.get("manager") as Node
	if player == null or level_up_ui == null or manager == null:
		_setup_failed("could not construct player, LevelUpUI, and UpgradeManager fixture")
		return false
	if not level_up_ui.has_signal(&"upgrade_chosen"):
		_setup_failed("LevelUpUI lacks upgrade_chosen signal")
		return false
	if bool(manager.get("_is_disabled")):
		_setup_failed("UpgradeManager disabled itself during fixture setup")
		return false
	if player.get_node_or_null("Weapon") == null or player.get_node_or_null("MagnetArea/CollisionShape2D") == null:
		_setup_failed("player fixture is missing Weapon or MagnetArea/CollisionShape2D")
		return false
	if needs_timer and player.get_node_or_null("Weapon/CooldownTimer") == null:
		_setup_failed("Weapon/CooldownTimer is missing")
		return false
	return true


func _setup_failed(what: String) -> void:
	print("TEST_ERROR setup_failed %s" % what)
	_setup_error = true
	get_tree().quit(1)


func _emit_upgrade(fixture: Dictionary, id: StringName) -> void:
	var level_up_ui: Node = fixture.get("ui") as Node
	level_up_ui.emit_signal(&"upgrade_chosen", id)


func _finish_fixture(fixture: Dictionary) -> void:
	var fixture_root: Node = fixture.get("root") as Node
	if fixture_root != null:
		fixture_root.free()


func _case_shoes_once() -> void:
	var fixture: Dictionary = _make_fixture()
	if not _fixture_is_valid(fixture):
		return
	var player: Node = fixture.get("player") as Node
	var base_speed: float = float(player.get(&"speed"))
	_emit_upgrade(fixture, &"shoes")
	var actual_speed: float = float(player.get(&"speed"))
	var expected_speed: float = base_speed * 1.10
	var ok: bool = _matches_nonzero_baseline(base_speed, expected_speed, actual_speed)
	_record("shoes_multiplies_speed_exactly", ok, "base=%.4f expected=%.4f actual=%.4f" % [base_speed, expected_speed, actual_speed])
	_finish_fixture(fixture)


func _case_shoes_compound_from_base() -> void:
	var fixture: Dictionary = _make_fixture()
	if not _fixture_is_valid(fixture):
		return
	var player: Node = fixture.get("player") as Node
	var base_speed: float = float(player.get(&"speed"))
	for _count in range(3):
		_emit_upgrade(fixture, &"shoes")
	var actual_speed: float = float(player.get(&"speed"))
	var expected_speed: float = base_speed * pow(1.10, 3)
	var ok: bool = _matches_nonzero_baseline(base_speed, expected_speed, actual_speed)
	_record("repeated_picks_compound_from_base", ok, "base=%.4f expected=%.4f actual=%.4f" % [base_speed, expected_speed, actual_speed])
	_finish_fixture(fixture)


func _case_heart_heals() -> void:
	var fixture: Dictionary = _make_fixture()
	if not _fixture_is_valid(fixture):
		return
	var player: Node = fixture.get("player") as Node
	var base_max_health: float = float(player.get(&"max_health"))
	var base_health: float = float(player.get(&"health"))
	_emit_upgrade(fixture, &"heart")
	_emit_upgrade(fixture, &"heart")
	var actual_max_health: float = float(player.get(&"max_health"))
	var actual_health: float = float(player.get(&"health"))
	var expected_max_health: float = base_max_health + 40.0
	var expected_health: float = minf(base_health + 40.0, expected_max_health)
	var max_ok: bool = _matches_nonzero_baseline(base_max_health, expected_max_health, actual_max_health)
	var health_ok: bool = _matches_nonzero_baseline(base_health, expected_health, actual_health)
	_record("heart_raises_max_hp_and_heals", max_ok and health_ok, "base_max=%.4f actual_max=%.4f base_health=%.4f actual_health=%.4f" % [base_max_health, actual_max_health, base_health, actual_health])
	_finish_fixture(fixture)


func _case_gloves_updates_live_timer() -> void:
	var fixture: Dictionary = _make_fixture()
	if not _fixture_is_valid(fixture, true):
		return
	var player: Node = fixture.get("player") as Node
	var weapon: Node = player.get_node_or_null("Weapon")
	var cooldown_timer: Timer = weapon.get_node_or_null("CooldownTimer") as Timer
	var base_cooldown: float = float(weapon.get(&"cooldown"))
	_emit_upgrade(fixture, &"gloves")
	_emit_upgrade(fixture, &"gloves")
	var actual_cooldown: float = float(weapon.get(&"cooldown"))
	var actual_wait_time: float = cooldown_timer.wait_time
	var expected_cooldown: float = base_cooldown * pow(0.92, 2)
	var cooldown_ok: bool = _matches_nonzero_baseline(base_cooldown, expected_cooldown, actual_cooldown)
	var timer_ok: bool = _matches_nonzero_baseline(base_cooldown, expected_cooldown, actual_wait_time)
	_record("gloves_updates_cooldown_and_live_timer", cooldown_ok and timer_ok, "base=%.4f expected=%.4f cooldown=%.4f timer_wait=%.4f" % [base_cooldown, expected_cooldown, actual_cooldown, actual_wait_time])
	_finish_fixture(fixture)


func _case_magnet_does_not_mutate_shared_shape() -> void:
	var fixture: Dictionary = _make_fixture()
	if not _fixture_is_valid(fixture):
		return
	var fixture_root: Node = fixture.get("root") as Node
	var first_player: Node = fixture.get("player") as Node
	var second_player: Node = PLAYER_SCENE.instantiate()
	second_player.name = &"SecondPlayer"
	fixture_root.add_child(second_player)

	var first_shape: CircleShape2D = _get_magnet_shape(first_player)
	var second_shape: CircleShape2D = _get_magnet_shape(second_player)
	if first_shape == null or second_shape == null:
		_setup_failed("one of the player magnet shapes is not a CircleShape2D")
		return
	var base_radius: float = first_shape.radius
	var second_base_radius: float = second_shape.radius
	_emit_upgrade(fixture, &"magnet")
	var first_radius: float = first_shape.radius
	var second_radius: float = second_shape.radius
	var expected_first_radius: float = base_radius * 1.30
	var first_ok: bool = _matches_nonzero_baseline(base_radius, expected_first_radius, first_radius)
	var second_ok: bool = _matches_nonzero_baseline(second_base_radius, second_base_radius, second_radius)
	_record("magnet_scales_private_radius_only", first_ok and second_ok, "base=%.4f expected_first=%.4f first=%.4f second=%.4f" % [base_radius, expected_first_radius, first_radius, second_radius])
	_finish_fixture(fixture)


func _get_magnet_shape(player: Node) -> CircleShape2D:
	var collision: CollisionShape2D = player.get_node_or_null("MagnetArea/CollisionShape2D") as CollisionShape2D
	if collision == null:
		return null
	return collision.shape as CircleShape2D


func _matches_nonzero_baseline(baseline: float, expected: float, measured: float) -> bool:
	if is_zero_approx(baseline) and is_zero_approx(measured):
		return false
	return absf(expected - measured) <= EPSILON


func _record(case_name: String, ok: bool, detail: String) -> void:
	_recorded += 1
	if ok:
		_passed += 1
		print("TEST_CASE %s PASS %s" % [case_name, detail])
	else:
		_failed += 1
		print("TEST_CASE %s FAIL %s" % [case_name, detail])
