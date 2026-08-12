extends Node


const EXPECTED_CASE_COUNT: int = 6
const ENEMY_SCRIPT: Script = preload("res://scripts/enemy.gd")
const ENEMY_SPAWNER_SCRIPT: Script = preload("res://scripts/enemy_spawner.gd")

var _passed: int = 0
var _failed: int = 0
var _skipped: int = 0
var _recorded: int = 0
var _enemy_scene: PackedScene = null


func _ready() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_enemy_scene = _make_enemy_scene()
	if _enemy_scene == null:
		print("TEST_ERROR setup_failed could_not_build_enemy_scene")
		_finish()
		return
	_test_phase_lookup_boundaries()
	_test_spawn_interval_shortens()
	_test_enemies_per_spawn_grows()
	_test_health_multiplier_reaches_enemy()
	_test_variants_have_right_stats()
	_test_legacy_mode()
	_finish()


func _make_enemy_scene() -> PackedScene:
	var enemy: CharacterBody2D = CharacterBody2D.new()
	enemy.set_script(ENEMY_SCRIPT)
	var sprite: ColorRect = ColorRect.new()
	sprite.name = "Sprite"
	enemy.add_child(sprite)
	sprite.owner = enemy
	var packed_scene: PackedScene = PackedScene.new()
	if packed_scene.pack(enemy) != OK:
		return null
	return packed_scene


func _make_context(use_wave_data: bool) -> Node2D:
	var context: Node2D = Node2D.new()
	add_child(context)
	var container: Node2D = Node2D.new()
	container.name = "EnemyContainer"
	context.add_child(container)
	var target: Node2D = Node2D.new()
	target.name = "Target"
	target.position = Vector2(640.0, 360.0)
	context.add_child(target)
	var spawner: Node = ENEMY_SPAWNER_SCRIPT.new() as Node
	spawner.name = "Spawner"
	spawner.set("enemy_scene", _enemy_scene)
	spawner.set("enemy_container_path", NodePath("../EnemyContainer"))
	spawner.set("target_path", NodePath("../Target"))
	spawner.set("spawn_interval", 1.5)
	spawner.set("max_enemies", 30)
	spawner.set("use_wave_data", use_wave_data)
	context.add_child(spawner)
	return context


func _test_phase_lookup_boundaries() -> void:
	var times: Array[float] = [0.0, 29.9, 30.0, 59.9, 60.0, 300.0]
	var expected: Array[int] = [0, 0, 1, 1, 2, 5]
	var observed: Array[int] = []
	for elapsed_time in times:
		var phase: Dictionary = WaveData.get_phase_for_time(elapsed_time)
		observed.append(int(phase.get("index", -1)))
	_record_case("phase_lookup_boundaries", observed == expected, "indices=%s" % [observed])


func _test_spawn_interval_shortens() -> void:
	var intervals: Array[float] = []
	var decreases: bool = true
	for index in range(WaveData.get_phase_count()):
		var phase: Dictionary = WaveData.PHASES[index]
		intervals.append(float(phase.get("spawn_interval", 0.0)))
		if index > 0 and intervals[index] >= intervals[index - 1]:
			decreases = false
	_record_case("spawn_interval_shortens", decreases, "intervals=%s" % [intervals])


func _test_enemies_per_spawn_grows() -> void:
	var early_context: Node2D = _make_context(true)
	var early_spawner: Node = early_context.get_node("Spawner")
	early_spawner.call("set_elapsed_time_for_testing", 0.0)
	early_spawner.call("trigger_spawn_tick_for_testing")
	var early_count: int = early_context.get_node("EnemyContainer").get_child_count()
	var late_context: Node2D = _make_context(true)
	var late_spawner: Node = late_context.get_node("Spawner")
	late_spawner.call("set_elapsed_time_for_testing", 180.0)
	late_spawner.call("trigger_spawn_tick_for_testing")
	var late_count: int = late_context.get_node("EnemyContainer").get_child_count()
	_record_case("enemies_per_spawn_grows", early_count == 1 and late_count == 3, "early=%d late=%d" % [early_count, late_count])


func _test_health_multiplier_reaches_enemy() -> void:
	var early_context: Node2D = _make_context(true)
	var early_spawner: Node = early_context.get_node("Spawner")
	early_spawner.call("set_elapsed_time_for_testing", 0.0)
	var early_enemy: Node = early_spawner.call("spawn_one") as Node
	var late_context: Node2D = _make_context(true)
	var late_spawner: Node = late_context.get_node("Spawner")
	late_spawner.call("set_elapsed_time_for_testing", 240.0)
	var late_enemy: Node = late_spawner.call("spawn_one") as Node
	if early_enemy == null or late_enemy == null:
		_record_case("health_multiplier_reaches_enemy", false, "early=0.00 late=0.00 multiplier=0.00")
		return
	var early_health: float = float(early_enemy.get("health"))
	var late_health: float = float(late_enemy.get("health"))
	var late_variant_id: StringName = StringName(late_enemy.get("variant_id"))
	var late_type: Dictionary = WaveData.get_enemy_type(late_variant_id)
	var multiplier: float = float(WaveData.get_phase_for_time(240.0).get("health_multiplier", 0.0))
	var expected_late_health: float = float(late_type.get("health", 0.0)) * multiplier
	var health_matches: bool = is_equal_approx(late_health, expected_late_health)
	_record_case("health_multiplier_reaches_enemy", is_equal_approx(early_health, 10.0) and health_matches, "early=%.2f late=%.2f multiplier=%.2f" % [early_health, late_health, multiplier])


func _test_variants_have_right_stats() -> void:
	var context: Node2D = _make_context(true)
	var spawner: Node = context.get_node("Spawner")
	spawner.call("set_elapsed_time_for_testing", 180.0)
	for _index in range(10):
		spawner.call("trigger_spawn_tick_for_testing")
	var container: Node = context.get_node("EnemyContainer")
	var phase_weights: Dictionary = WaveData.get_phase_for_time(180.0).get("weights", {})
	var counts: Dictionary = {&"basic": 0, &"fast": 0, &"tank": 0}
	var stats_match: bool = container.get_child_count() >= 30
	for enemy_index in range(container.get_child_count()):
		var enemy: Node = container.get_child(enemy_index)
		var variant_id: StringName = StringName(enemy.get("variant_id"))
		if not phase_weights.has(variant_id):
			stats_match = false
			continue
		counts[variant_id] = int(counts.get(variant_id, 0)) + 1
		var enemy_type: Dictionary = WaveData.get_enemy_type(variant_id)
		if not is_equal_approx(float(enemy.get("speed")), float(enemy_type.get("speed", 0.0))):
			stats_match = false
		if not is_equal_approx(float(enemy.get("contact_damage")), float(enemy_type.get("contact_damage", 0.0))):
			stats_match = false
	_record_case("variants_have_right_stats", stats_match, "basic=%d fast=%d tank=%d total=%d" % [int(counts[&"basic"]), int(counts[&"fast"]), int(counts[&"tank"]), container.get_child_count()])


func _test_legacy_mode() -> void:
	var context: Node2D = _make_context(false)
	var spawner: Node = context.get_node("Spawner")
	spawner.call("set_elapsed_time_for_testing", 240.0)
	spawner.call("trigger_spawn_tick_for_testing")
	var count: int = context.get_node("EnemyContainer").get_child_count()
	var spawn_timer: Timer = spawner.get_node("SpawnTimer") as Timer
	var interval: float = spawn_timer.wait_time if spawn_timer != null else -1.0
	_record_case("legacy_mode", count == 1 and is_equal_approx(interval, 1.5), "count=%d interval=%.2f" % [count, interval])


func _record_case(case_name: String, passed: bool, detail: String) -> void:
	_recorded += 1
	if passed:
		_passed += 1
		print("TEST_CASE %s PASS %s" % [case_name, detail])
	else:
		_failed += 1
		print("TEST_CASE %s FAIL %s" % [case_name, detail])


func _finish() -> void:
	if _recorded != EXPECTED_CASE_COUNT:
		print("TEST_ERROR missing_cases expected=%d recorded=%d" % [EXPECTED_CASE_COUNT, _recorded])
		_failed += 1
	var overall_passed: bool = _passed > 0 and _failed == 0 and _recorded == EXPECTED_CASE_COUNT
	print("TEST_RESULT %s passed=%d failed=%d skipped=%d" % ["PASS" if overall_passed else "FAIL", _passed, _failed, _skipped])
	get_tree().quit(0 if overall_passed else 1)
