extends Node

## M12b에서 새로 생긴 성장 경로를 검사한다.
##
## 검사 대상은 세 가지다.
##   1. 칼날(blade)이 **세 무기 모두**의 피해를 올리는가
##   2. 산탄·궤도구가 레벨로 자라는가 (예전에는 max_level = 1이라 한 번 얻으면 끝이었다)
##   3. 적 종류별 젬 값이 실제로 떨어지는 젬에 도달하는가
##
## 수치를 하드코딩하지 않는다. 기대값은 전부 `UpgradeData`/`WaveData`의 정의에서
## 읽어 계산한다. 그래야 튜닝이 테스트를 깨뜨리지 않는다 (devlog 014 7절).

const EXPECTED_CASE_COUNT: int = 6
const EPSILON: float = 0.0001
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const LEVEL_UP_UI_SCENE: PackedScene = preload("res://scenes/level_up_ui.tscn")
const UPGRADE_MANAGER_SCRIPT: Script = preload("res://scripts/upgrade_manager.gd")
const ENEMY_SPAWNER_SCRIPT: Script = preload("res://scripts/enemy_spawner.gd")
const PICKUP_SPAWNER_SCRIPT: Script = preload("res://scripts/pickup_spawner.gd")
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy.tscn")
const GEM_SCENE: PackedScene = preload("res://scenes/xp_gem.tscn")

var _passed: int = 0
var _failed: int = 0
var _skipped: int = 0
var _recorded: int = 0
var _setup_error: bool = false


func _ready() -> void:
	await get_tree().process_frame
	_case_blade_scales_every_weapon()
	if _setup_error:
		return
	_case_blade_compounds_from_base()
	if _setup_error:
		return
	_case_shotgun_levels_add_pellets()
	if _setup_error:
		return
	_case_orbital_levels_scale_damage()
	if _setup_error:
		return
	_case_weapons_can_exceed_level_one()
	# await 를 빼면 이 케이스는 기록되기 전에 _ready 가 끝나 버린다.
	await _case_gem_value_reaches_the_gem()
	if _setup_error:
		return

	if _recorded != EXPECTED_CASE_COUNT:
		print("TEST_ERROR missing_cases expected=%d recorded=%d" % [EXPECTED_CASE_COUNT, _recorded])
		_failed += 1
	var overall: String = "PASS" if _failed == 0 and _passed > 0 and _recorded == EXPECTED_CASE_COUNT else "FAIL"
	print("TEST_RESULT %s passed=%d failed=%d skipped=%d" % [overall, _passed, _failed, _skipped])
	get_tree().quit(0 if overall == "PASS" else 1)


# --- 픽스처 -----------------------------------------------------------------

func _make_fixture() -> Dictionary:
	var fixture_root: Node = Node.new()
	fixture_root.name = &"PowerFixture"
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

	return {"root": fixture_root, "player": player, "ui": level_up_ui, "manager": manager}


func _fixture_is_valid(fixture: Dictionary) -> bool:
	var player: Node = fixture.get("player") as Node
	var manager: Node = fixture.get("manager") as Node
	if player == null or manager == null:
		_setup_failed("could not construct the player/manager fixture")
		return false
	if bool(manager.get("_is_disabled")):
		_setup_failed("UpgradeManager disabled itself during fixture setup")
		return false
	for child_name in ["Weapon", "Shotgun", "Orbital"]:
		if player.get_node_or_null(child_name) == null:
			_setup_failed("player fixture is missing %s" % child_name)
			return false
	return true


func _emit(fixture: Dictionary, id: StringName, times: int = 1) -> void:
	var level_up_ui: Node = fixture.get("ui") as Node
	for _index in range(times):
		level_up_ui.emit_signal(&"upgrade_chosen", id)


func _finish(fixture: Dictionary) -> void:
	var fixture_root: Node = fixture.get("root") as Node
	if fixture_root != null:
		fixture_root.free()


# --- 케이스 -----------------------------------------------------------------

## 칼날은 주무기·산탄·궤도구 **셋 다** 올려야 한다.
## 하나만 올리면 그 무기만 자라고 나머지는 죽은 선택지가 된다.
func _case_blade_scales_every_weapon() -> void:
	var fixture: Dictionary = _make_fixture()
	if not _fixture_is_valid(fixture):
		return
	var player: Node = fixture["player"]
	var weapon: Node = player.get_node("Weapon")
	var shotgun: Node = player.get_node("Shotgun")
	var orbital: Node = player.get_node("Orbital")

	var base_weapon: float = float(weapon.get(&"projectile_damage"))
	var base_shotgun: float = float(shotgun.get(&"projectile_damage"))
	var base_orbital: float = float(orbital.get(&"damage"))
	var multiplier: float = float(UpgradeData.get_definition(&"blade").get("multiplier", 1.0))

	_emit(fixture, &"blade")

	var weapon_ok: bool = is_equal_approx(float(weapon.get(&"projectile_damage")), base_weapon * multiplier)
	var shotgun_ok: bool = is_equal_approx(float(shotgun.get(&"projectile_damage")), base_shotgun * multiplier)
	# 궤도구는 칼날 배율과 궤도구 레벨(최소 1)이 함께 곱해진다.
	var orbital_ok: bool = is_equal_approx(float(orbital.get(&"damage")), base_orbital * multiplier)

	_record("blade_scales_every_weapon", weapon_ok and shotgun_ok and orbital_ok,
		"mult=%.4f weapon=%.4f/%.4f shotgun=%.4f/%.4f orbital=%.4f/%.4f" % [
			multiplier,
			float(weapon.get(&"projectile_damage")), base_weapon * multiplier,
			float(shotgun.get(&"projectile_damage")), base_shotgun * multiplier,
			float(orbital.get(&"damage")), base_orbital * multiplier])
	_finish(fixture)


## 반복 선택은 **기본값 기준 거듭제곱**이어야 한다. 현재값에 곱하면 부동소수 오차가
## 쌓이고, 다른 업그레이드가 끼어들면 순서에 따라 결과가 달라진다.
func _case_blade_compounds_from_base() -> void:
	var fixture: Dictionary = _make_fixture()
	if not _fixture_is_valid(fixture):
		return
	var weapon: Node = (fixture["player"] as Node).get_node("Weapon")
	var base_damage: float = float(weapon.get(&"projectile_damage"))
	var definition: Dictionary = UpgradeData.get_definition(&"blade")
	var multiplier: float = float(definition.get("multiplier", 1.0))
	var levels: int = mini(3, int(definition.get("max_level", 0)))

	_emit(fixture, &"blade", levels)

	var expected: float = base_damage * pow(multiplier, levels)
	var actual: float = float(weapon.get(&"projectile_damage"))
	_record("blade_compounds_from_base", is_equal_approx(actual, expected),
		"levels=%d base=%.4f expected=%.4f actual=%.4f" % [levels, base_damage, expected, actual])
	_finish(fixture)


## 산탄은 레벨마다 탄이 늘어야 한다.
func _case_shotgun_levels_add_pellets() -> void:
	var fixture: Dictionary = _make_fixture()
	if not _fixture_is_valid(fixture):
		return
	var shotgun: Node = (fixture["player"] as Node).get_node("Shotgun")
	var base_pellets: int = int(shotgun.get(&"pellet_count"))
	var definition: Dictionary = UpgradeData.get_definition(&"shotgun")
	var per_level: int = int(definition.get("pellets_per_level", 0))
	var max_level: int = int(definition.get("max_level", 1))

	_emit(fixture, &"shotgun", max_level)

	var expected: int = base_pellets + per_level * (max_level - 1)
	var actual: int = int(shotgun.get(&"pellet_count"))
	# per_level 이 0이면 성장이 없다는 뜻이므로 그것 자체가 실패다.
	_record("shotgun_levels_add_pellets", per_level > 0 and actual == expected,
		"per_level=%d max_level=%d base=%d expected=%d actual=%d" % [per_level, max_level, base_pellets, expected, actual])
	_finish(fixture)


## 궤도구는 레벨 수만큼 피해가 커져야 한다.
func _case_orbital_levels_scale_damage() -> void:
	var fixture: Dictionary = _make_fixture()
	if not _fixture_is_valid(fixture):
		return
	var orbital: Node = (fixture["player"] as Node).get_node("Orbital")
	var base_damage: float = float(orbital.get(&"damage"))
	var max_level: int = int(UpgradeData.get_definition(&"orbital").get("max_level", 1))

	_emit(fixture, &"orbital", max_level)

	var expected: float = base_damage * float(max_level)
	var actual: float = float(orbital.get(&"damage"))
	_record("orbital_levels_scale_damage", max_level > 1 and is_equal_approx(actual, expected),
		"max_level=%d base=%.4f expected=%.4f actual=%.4f" % [max_level, base_damage, expected, actual])
	_finish(fixture)


## 무기가 정말 2레벨 이상 갈 수 있는지를 정의에서 직접 본다.
## M12a 이전에는 둘 다 max_level = 1이라 얻는 즉시 성장이 끝났다.
func _case_weapons_can_exceed_level_one() -> void:
	var offenders: PackedStringArray = []
	for weapon_id: StringName in [&"shotgun", &"orbital"]:
		if int(UpgradeData.get_definition(weapon_id).get("max_level", 0)) <= 1:
			offenders.append(String(weapon_id))
	_record("weapons_can_exceed_level_one", offenders.is_empty(),
		"stuck_at_one=%s" % ("none" if offenders.is_empty() else ",".join(offenders)))


## 젬 값이 적 종류에서 실제 젬 노드까지 도달하는지 본다.
## 스포너가 bind()로 실어 보내므로, 연결이 끊기면 조용히 1.0으로 떨어진다.
func _case_gem_value_reaches_the_gem() -> void:
	var context: Node2D = Node2D.new()
	add_child(context)
	var enemy_container: Node2D = Node2D.new()
	enemy_container.name = &"EnemyContainer"
	context.add_child(enemy_container)
	var gem_container: Node2D = Node2D.new()
	gem_container.name = &"GemContainer"
	context.add_child(gem_container)
	var target: Node2D = Node2D.new()
	target.name = &"Target"
	context.add_child(target)

	var pickup_spawner: Node = PICKUP_SPAWNER_SCRIPT.new()
	pickup_spawner.name = &"PickupSpawner"
	pickup_spawner.set(&"gem_scene", GEM_SCENE)
	pickup_spawner.set(&"gem_container_path", NodePath("../GemContainer"))
	context.add_child(pickup_spawner)

	var spawner: Node = ENEMY_SPAWNER_SCRIPT.new()
	spawner.name = &"Spawner"
	spawner.set(&"enemy_scene", ENEMY_SCENE)
	spawner.set(&"enemy_container_path", NodePath("../EnemyContainer"))
	spawner.set(&"target_path", NodePath("../Target"))
	spawner.set(&"pickup_spawner_path", NodePath("../PickupSpawner"))
	spawner.set(&"use_wave_data", true)
	context.add_child(spawner)

	# 값이 가장 큰 적 종류를 정의에서 찾아, 그 종류가 나오는 페이즈로 시계를 맞춘다.
	var richest_id: StringName = &"basic"
	var richest_value: float = -1.0
	for variant_id: StringName in WaveData.ENEMY_TYPES:
		var value: float = float(WaveData.get_enemy_type(variant_id).get("gem_value", 1.0))
		if value > richest_value:
			richest_value = value
			richest_id = variant_id

	var phase_time: float = -1.0
	for phase: Dictionary in WaveData.PHASES:
		if (phase.get("weights", {}) as Dictionary).has(richest_id):
			phase_time = float(phase.get("start_time", 0.0))
	if phase_time < 0.0:
		_record("gem_value_reaches_the_gem", false, "no_phase_spawns=%s" % richest_id)
		context.free()
		return

	# 원하는 종류가 나올 때까지 뽑는다. 종류 선택은 가중 무작위다.
	var enemy: Node = null
	for _attempt in range(200):
		spawner.call(&"set_elapsed_time_for_testing", phase_time)
		var candidate: Node = spawner.call(&"spawn_one") as Node
		if candidate == null:
			continue
		if StringName(candidate.get(&"variant_id")) == richest_id:
			enemy = candidate
			break
		candidate.free()
	if enemy == null:
		_record("gem_value_reaches_the_gem", false, "could_not_spawn=%s" % richest_id)
		context.free()
		return

	enemy.emit_signal(&"died", Vector2.ZERO)
	await get_tree().process_frame
	await get_tree().process_frame

	var dropped_value: float = -1.0
	if gem_container.get_child_count() > 0:
		dropped_value = float(gem_container.get_child(0).get(&"value"))
	_record("gem_value_reaches_the_gem", is_equal_approx(dropped_value, richest_value),
		"variant=%s expected=%.2f dropped=%.2f gems=%d" % [richest_id, richest_value, dropped_value, gem_container.get_child_count()])
	context.free()


# --- 기록 -------------------------------------------------------------------

func _setup_failed(what: String) -> void:
	print("TEST_ERROR setup_failed %s" % what)
	_setup_error = true
	get_tree().quit(1)


func _record(case_name: String, ok: bool, detail: String) -> void:
	_recorded += 1
	if ok:
		_passed += 1
		print("TEST_CASE %s PASS %s" % [case_name, detail])
	else:
		_failed += 1
		print("TEST_CASE %s FAIL %s" % [case_name, detail])
