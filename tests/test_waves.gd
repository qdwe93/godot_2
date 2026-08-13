extends Node


const EXPECTED_CASE_COUNT: int = 8
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
	_test_phase_start_times_strictly_increase()
	_test_all_phases_reachable()
	_test_phase_boundaries_are_exclusive()
	_test_difficulty_curve_is_monotonic()
	_test_phase_weights_reference_real_variants()
	_test_health_multiplier_reaches_enemy()
	_test_variants_have_right_stats()
	_test_legacy_mode()
	_finish()


func _make_enemy_scene() -> PackedScene:
	var enemy: CharacterBody2D = CharacterBody2D.new()
	enemy.set_script(ENEMY_SCRIPT)
	var sprite: Polygon2D = Polygon2D.new()
	sprite.name = "Sprite"
	enemy.add_child(sprite)
	sprite.owner = enemy
	var outline: Line2D = Line2D.new()
	outline.name = "Outline"
	outline.closed = true
	enemy.add_child(outline)
	outline.owner = enemy
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


func _test_phase_start_times_strictly_increase() -> void:
	if WaveData.PHASES.is_empty():
		_record_case("phase_start_times_strictly_increase", false, "broken_at=0 phases_empty")
		return
	var first_phase: Dictionary = WaveData.PHASES[0]
	var previous_start: float = float(first_phase.get("start_time", 0.0))
	for index in range(1, WaveData.PHASES.size()):
		var phase: Dictionary = WaveData.PHASES[index]
		var current_start: float = float(phase.get("start_time", 0.0))
		if current_start <= previous_start:
			_record_case("phase_start_times_strictly_increase", false, "broken_at=%d prev=%.2f curr=%.2f" % [index, previous_start, current_start])
			return
		previous_start = current_start
	_record_case("phase_start_times_strictly_increase", true, "phase_count=%d" % WaveData.PHASES.size())


func _test_all_phases_reachable() -> void:
	if WaveData.PHASES.is_empty():
		_record_case("all_phases_reachable", false, "broken_at=0 phases_empty")
		return
	for index in range(WaveData.PHASES.size()):
		var phase: Dictionary = WaveData.PHASES[index]
		var start_time: float = float(phase.get("start_time", 0.0))
		var observed_index: int = WaveData.get_phase_index_for_time(start_time)
		if observed_index != index:
			_record_case("all_phases_reachable", false, "broken_at=%d start=%.2f observed=%d" % [index, start_time, observed_index])
			return
	_record_case("all_phases_reachable", true, "phase_count=%d" % WaveData.PHASES.size())


func _test_phase_boundaries_are_exclusive() -> void:
	if WaveData.PHASES.is_empty():
		_record_case("phase_boundaries_are_exclusive", false, "broken_at=0 phases_empty")
		return
	var zero_index: int = WaveData.get_phase_index_for_time(0.0)
	var negative_index: int = WaveData.get_phase_index_for_time(-0.01)
	if zero_index != 0 or negative_index != 0:
		_record_case("phase_boundaries_are_exclusive", false, "broken_at=0 zero=%d negative=%d" % [zero_index, negative_index])
		return
	for index in range(1, WaveData.PHASES.size()):
		var phase: Dictionary = WaveData.PHASES[index]
		var start_time: float = float(phase.get("start_time", 0.0))
		var observed_index: int = WaveData.get_phase_index_for_time(start_time - 0.01)
		if observed_index != index - 1:
			_record_case("phase_boundaries_are_exclusive", false, "broken_at=%d start=%.2f expected=%d observed=%d" % [index, start_time, index - 1, observed_index])
			return
	_record_case("phase_boundaries_are_exclusive", true, "phase_count=%d" % WaveData.PHASES.size())


func _test_difficulty_curve_is_monotonic() -> void:
	if WaveData.PHASES.size() < 2:
		_record_case("difficulty_curve_is_monotonic", false, "broken_at=0 phase_count=%d" % WaveData.PHASES.size())
		return
	var first_phase: Dictionary = WaveData.PHASES[0]
	var previous_interval: float = float(first_phase.get("spawn_interval", 0.0))
	var previous_max_enemies: int = int(first_phase.get("max_enemies", 0))
	var previous_health_multiplier: float = float(first_phase.get("health_multiplier", 0.0))
	var previous_enemies_per_spawn: int = int(first_phase.get("enemies_per_spawn", 0))
	for index in range(1, WaveData.PHASES.size()):
		var phase: Dictionary = WaveData.PHASES[index]
		var current_interval: float = float(phase.get("spawn_interval", 0.0))
		var current_max_enemies: int = int(phase.get("max_enemies", 0))
		var current_health_multiplier: float = float(phase.get("health_multiplier", 0.0))
		var current_enemies_per_spawn: int = int(phase.get("enemies_per_spawn", 0))
		if current_interval > previous_interval:
			_record_case("difficulty_curve_is_monotonic", false, "broken_at=%d field=spawn_interval prev=%.2f curr=%.2f" % [index, previous_interval, current_interval])
			return
		if current_max_enemies < previous_max_enemies:
			_record_case("difficulty_curve_is_monotonic", false, "broken_at=%d field=max_enemies prev=%d curr=%d" % [index, previous_max_enemies, current_max_enemies])
			return
		if current_health_multiplier < previous_health_multiplier:
			_record_case("difficulty_curve_is_monotonic", false, "broken_at=%d field=health_multiplier prev=%.2f curr=%.2f" % [index, previous_health_multiplier, current_health_multiplier])
			return
		if current_enemies_per_spawn < previous_enemies_per_spawn:
			_record_case("difficulty_curve_is_monotonic", false, "broken_at=%d field=enemies_per_spawn prev=%d curr=%d" % [index, previous_enemies_per_spawn, current_enemies_per_spawn])
			return
		previous_interval = current_interval
		previous_max_enemies = current_max_enemies
		previous_health_multiplier = current_health_multiplier
		previous_enemies_per_spawn = current_enemies_per_spawn
	var last_phase: Dictionary = WaveData.PHASES[WaveData.PHASES.size() - 1]
	var last_interval: float = float(last_phase.get("spawn_interval", 0.0))
	var last_health_multiplier: float = float(last_phase.get("health_multiplier", 0.0))
	var first_interval: float = float(first_phase.get("spawn_interval", 0.0))
	var first_health_multiplier: float = float(first_phase.get("health_multiplier", 0.0))
	if last_interval >= first_interval:
		_record_case("difficulty_curve_is_monotonic", false, "broken_at=%d field=spawn_interval first=%.2f last=%.2f" % [WaveData.PHASES.size() - 1, first_interval, last_interval])
		return
	if last_health_multiplier <= first_health_multiplier:
		_record_case("difficulty_curve_is_monotonic", false, "broken_at=%d field=health_multiplier first=%.2f last=%.2f" % [WaveData.PHASES.size() - 1, first_health_multiplier, last_health_multiplier])
		return
	_record_case("difficulty_curve_is_monotonic", true, "phase_count=%d" % WaveData.PHASES.size())


func _test_phase_weights_reference_real_variants() -> void:
	var index: int = 0
	for phase: Dictionary in WaveData.PHASES:
		var weights: Dictionary = phase.get("weights", {})
		var total_weight: int = 0
		for variant_key in weights:
			var variant_id: StringName = StringName(variant_key)
			var weight: int = int(weights.get(variant_key, 0))
			if not WaveData.ENEMY_TYPES.has(variant_id):
				_record_case("phase_weights_reference_real_variants", false, "broken_at=%d variant=%s missing_enemy_type" % [index, variant_id])
				return
			total_weight += weight
		if total_weight <= 0:
			_record_case("phase_weights_reference_real_variants", false, "broken_at=%d total_weight=%d" % [index, total_weight])
			return
		index += 1
	if index == 0:
		_record_case("phase_weights_reference_real_variants", false, "broken_at=0 phases_empty")
		return
	_record_case("phase_weights_reference_real_variants", true, "phase_count=%d" % index)


func _test_health_multiplier_reaches_enemy() -> void:
	if WaveData.PHASES.is_empty():
		_record_case("health_multiplier_reaches_enemy", false, "broken_at=0 phases_empty")
		return
	var first_phase: Dictionary = WaveData.PHASES[0]
	var last_phase_index: int = WaveData.PHASES.size() - 1
	var last_phase: Dictionary = WaveData.PHASES[last_phase_index]
	var first_start_time: float = float(first_phase.get("start_time", 0.0))
	var last_start_time: float = float(last_phase.get("start_time", 0.0))
	var early_context: Node2D = _make_context(true)
	var early_spawner: Node = early_context.get_node("Spawner")
	early_spawner.call("set_elapsed_time_for_testing", first_start_time)
	var early_enemy: Node = early_spawner.call("spawn_one") as Node
	var late_context: Node2D = _make_context(true)
	var late_spawner: Node = late_context.get_node("Spawner")
	late_spawner.call("set_elapsed_time_for_testing", last_start_time)
	var late_enemy: Node = late_spawner.call("spawn_one") as Node
	if early_enemy == null or late_enemy == null:
		_record_case("health_multiplier_reaches_enemy", false, "broken_at=%d early_present=%s late_present=%s" % [last_phase_index, early_enemy != null, late_enemy != null])
		return
	var early_variant_id: StringName = StringName(early_enemy.get("variant_id"))
	var late_variant_id: StringName = StringName(late_enemy.get("variant_id"))
	var early_type: Dictionary = WaveData.get_enemy_type(early_variant_id)
	var late_type: Dictionary = WaveData.get_enemy_type(late_variant_id)
	var early_multiplier: float = float(WaveData.get_phase_for_time(first_start_time).get("health_multiplier", 0.0))
	var late_multiplier: float = float(WaveData.get_phase_for_time(last_start_time).get("health_multiplier", 0.0))
	var expected_early_health: float = float(early_type.get("health", 0.0)) * early_multiplier
	var expected_late_health: float = float(late_type.get("health", 0.0)) * late_multiplier
	var early_health: float = float(early_enemy.get("health"))
	var late_health: float = float(late_enemy.get("health"))
	var health_matches: bool = is_equal_approx(early_health, expected_early_health) and is_equal_approx(late_health, expected_late_health)
	_record_case("health_multiplier_reaches_enemy", health_matches, "first_health=%.2f first_multiplier=%.2f last_health=%.2f last_multiplier=%.2f" % [early_health, early_multiplier, late_health, late_multiplier])


func _test_variants_have_right_stats() -> void:
	var required_variant_ids: Array[StringName] = [&"basic", &"fast", &"tank"]
	var phase_index: int = -1
	var selected_phase: Dictionary = {}
	for index in range(WaveData.PHASES.size()):
		var candidate_phase: Dictionary = WaveData.PHASES[index]
		var candidate_weights: Dictionary = candidate_phase.get("weights", {})
		var includes_all_variants: bool = true
		for variant_id: StringName in required_variant_ids:
			if not candidate_weights.has(variant_id):
				includes_all_variants = false
				break
		if includes_all_variants:
			phase_index = index
			selected_phase = candidate_phase
			break
	if phase_index < 0:
		_record_case("variants_have_right_stats", false, "broken_at=-1 missing_required_variants")
		return
	var phase_start_time: float = float(selected_phase.get("start_time", 0.0))
	var context: Node2D = _make_context(true)
	var spawner: Node = context.get_node("Spawner")
	spawner.call("set_elapsed_time_for_testing", phase_start_time)
	spawner.call("trigger_spawn_tick_for_testing")
	var container: Node = context.get_node("EnemyContainer")
	var phase_weights: Dictionary = WaveData.get_phase_for_time(phase_start_time).get("weights", {})
	var counts: Dictionary = {&"basic": 0, &"fast": 0, &"tank": 0}
	var stats_match: bool = container.get_child_count() > 0
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
	_record_case("variants_have_right_stats", stats_match, "phase=%d basic=%d fast=%d tank=%d total=%d" % [phase_index, int(counts[&"basic"]), int(counts[&"fast"]), int(counts[&"tank"]), container.get_child_count()])


func _test_legacy_mode() -> void:
	if WaveData.PHASES.is_empty():
		_record_case("legacy_mode", false, "broken_at=0 phases_empty")
		return
	var last_phase: Dictionary = WaveData.PHASES[WaveData.PHASES.size() - 1]
	var last_start_time: float = float(last_phase.get("start_time", 0.0))
	var context: Node2D = _make_context(false)
	var spawner: Node = context.get_node("Spawner")
	var configured_interval: float = float(spawner.get("spawn_interval"))
	spawner.call("set_elapsed_time_for_testing", last_start_time)
	spawner.call("trigger_spawn_tick_for_testing")
	var count: int = context.get_node("EnemyContainer").get_child_count()
	var spawn_timer: Timer = spawner.get_node("SpawnTimer") as Timer
	var interval: float = spawn_timer.wait_time if spawn_timer != null else -1.0
	_record_case("legacy_mode", count == 1 and is_equal_approx(interval, configured_interval), "count=%d interval=%.2f configured=%.2f" % [count, interval, configured_interval])


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
