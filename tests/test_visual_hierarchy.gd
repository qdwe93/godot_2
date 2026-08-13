extends Node


const EXPECTED_CASE_COUNT: int = 4
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const XP_GEM_SCENE: PackedScene = preload("res://scenes/xp_gem.tscn")
const PROJECTILE_SCENE: PackedScene = preload("res://scenes/projectile.tscn")
const BOSS_SPAWNER_SCRIPT: Script = preload("res://scripts/boss_spawner.gd")

var _passed: int = 0
var _failed: int = 0
var _skipped: int = 0
var _recorded: int = 0
var _main: Node = null


func _ready() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	if MAIN_SCENE == null or PLAYER_SCENE == null or XP_GEM_SCENE == null or PROJECTILE_SCENE == null or BOSS_SPAWNER_SCRIPT == null:
		print("TEST_ERROR setup_failed required visual resource could not be loaded")
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
	var colours: Dictionary = _read_visual_colours()
	if colours.is_empty():
		print("TEST_ERROR setup_failed could_not_read_visual_colours")
		await _dispose_main()
		_finish()
		return
	_test_brightness_order_is_correct(colours)
	_test_every_element_meets_minimum_contrast(colours)
	_test_player_is_brightest(colours)
	_test_enemy_variants_have_distinct_shapes()
	await _dispose_main()
	_finish()


func _read_visual_colours() -> Dictionary:
	# 배경은 BackgroundLayer(CanvasLayer) 아래로 옮겼다. Control 앵커가 Node2D 부모
	# 밑에서는 동작하지 않아 화면비가 다른 기기에서 뷰포트를 못 덮었기 때문이다.
	var background: ColorRect = _main.get_node_or_null("BackgroundLayer/Background") as ColorRect
	var player: Node = PLAYER_SCENE.instantiate()
	var gem: Node = XP_GEM_SCENE.instantiate()
	var projectile: Node = PROJECTILE_SCENE.instantiate()
	var player_sprite: CanvasItem = player.get_node_or_null("Sprite") as CanvasItem if player != null else null
	var gem_sprite: CanvasItem = gem.get_node_or_null("Sprite") as CanvasItem if gem != null else null
	var projectile_sprite: CanvasItem = projectile.get_node_or_null("Sprite") as CanvasItem if projectile != null else null
	var boss_spawner: Node = BOSS_SPAWNER_SCRIPT.new()
	# ColorRect와 Polygon2D 둘 다 color 속성을 갖는다. 타입으로 못 박으면
	# 스프라이트 노드 종류를 바꾸는 순간 테스트가 조용히 셋업 실패한다.
	if background == null or boss_spawner == null or not _has_colour(player_sprite) or not _has_colour(gem_sprite) or not _has_colour(projectile_sprite):
		if is_instance_valid(player):
			player.queue_free()
		if is_instance_valid(gem):
			gem.queue_free()
		if is_instance_valid(projectile):
			projectile.queue_free()
		return {}
	var basic_type: Dictionary = WaveData.get_enemy_type(&"basic")
	var fast_type: Dictionary = WaveData.get_enemy_type(&"fast")
	var tank_type: Dictionary = WaveData.get_enemy_type(&"tank")
	var boss_colour: Color = Color(boss_spawner.get("boss_color"))
	boss_spawner.free()
	var colours: Dictionary = {
		"background": background.color,
		"player": _read_colour(player_sprite),
		"boss": boss_colour,
		"tank": Color(tank_type.get("color", Color.BLACK)),
		"basic": Color(basic_type.get("color", Color.BLACK)),
		"fast": Color(fast_type.get("color", Color.BLACK)),
		"gem": _read_colour(gem_sprite),
		"projectile": _read_colour(projectile_sprite),
	}
	player.queue_free()
	gem.queue_free()
	projectile.queue_free()
	return colours


static func _has_colour(node: CanvasItem) -> bool:
	if node == null:
		return false
	var value: Variant = node.get("color")
	return value is Color


static func _read_colour(node: CanvasItem) -> Color:
	var value: Variant = node.get("color")
	if value is Color:
		return value
	return Color.BLACK


func _test_brightness_order_is_correct(colours: Dictionary) -> void:
	var ordered_names: Array[String] = ["player", "boss", "tank", "basic", "fast", "gem", "projectile"]
	for index in range(ordered_names.size() - 1):
		var brighter_name: String = ordered_names[index]
		var darker_name: String = ordered_names[index + 1]
		var brighter_luminance: float = _relative_luminance(Color(colours[brighter_name]))
		var darker_luminance: float = _relative_luminance(Color(colours[darker_name]))
		if brighter_luminance <= darker_luminance:
			_record_case("brightness_order_is_correct", false, "%s=%.6f %s=%.6f" % [brighter_name, brighter_luminance, darker_name, darker_luminance])
			return
	_record_case("brightness_order_is_correct", true, "ordered_elements=%d" % ordered_names.size())


func _test_every_element_meets_minimum_contrast(colours: Dictionary) -> void:
	var background: Color = Color(colours["background"])
	var element_names: Array[String] = ["player", "boss", "tank", "basic", "fast", "gem", "projectile"]
	for element_name in element_names:
		var ratio: float = _contrast_ratio(Color(colours[element_name]), background)
		if ratio < 3.0:
			_record_case("every_element_meets_minimum_contrast", false, "%s ratio=%.2f" % [element_name, ratio])
			return
	_record_case("every_element_meets_minimum_contrast", true, "elements=%d minimum=3.0" % element_names.size())


func _test_player_is_brightest(colours: Dictionary) -> void:
	var player_luminance: float = _relative_luminance(Color(colours["player"]))
	for element_name in ["boss", "tank", "basic", "fast", "gem", "projectile"]:
		var luminance: float = _relative_luminance(Color(colours[element_name]))
		if player_luminance <= luminance:
			_record_case("player_is_brightest", false, "player=%.6f %s=%.6f" % [player_luminance, element_name, luminance])
			return
	_record_case("player_is_brightest", true, "player=%.6f" % player_luminance)


func _test_enemy_variants_have_distinct_shapes() -> void:
	var variant_ids: Array[StringName] = [&"basic", &"fast", &"tank"]
	var seen_shapes: Dictionary = {}
	var seen_point_counts: Dictionary = {}
	for variant_id in variant_ids:
		var enemy_type: Dictionary = WaveData.get_enemy_type(variant_id)
		var shape_id: StringName = StringName(enemy_type.get("shape", &""))
		var point_count: int = WaveData.get_shape_points(shape_id, 10.0).size()
		if seen_shapes.has(shape_id) or seen_point_counts.has(point_count):
			_record_case("enemy_variants_have_distinct_shapes", false, "variant=%s shape=%s points=%d" % [variant_id, shape_id, point_count])
			return
		seen_shapes[shape_id] = true
		seen_point_counts[point_count] = true
	_record_case("enemy_variants_have_distinct_shapes", true, "shapes=%d point_counts=%d" % [seen_shapes.size(), seen_point_counts.size()])


static func _srgb_to_linear(channel: float) -> float:
	if channel <= 0.04045:
		return channel / 12.92
	return pow((channel + 0.055) / 1.055, 2.4)


static func _relative_luminance(colour: Color) -> float:
	return 0.2126 * _srgb_to_linear(colour.r) + 0.7152 * _srgb_to_linear(colour.g) + 0.0722 * _srgb_to_linear(colour.b)


static func _contrast_ratio(first: Color, second: Color) -> float:
	var first_luminance: float = _relative_luminance(first)
	var second_luminance: float = _relative_luminance(second)
	var lighter: float = maxf(first_luminance, second_luminance)
	var darker: float = minf(first_luminance, second_luminance)
	return (lighter + 0.05) / (darker + 0.05)


func _dispose_main() -> void:
	get_tree().paused = false
	if is_instance_valid(_main):
		_main.queue_free()
	await get_tree().process_frame
	_main = null


func _record_case(case_name: String, passed: bool, detail: String) -> void:
	_recorded += 1
	if passed:
		_passed += 1
		print("TEST_CASE %s PASS %s" % [case_name, detail])
	else:
		_failed += 1
		print("TEST_CASE %s FAIL %s" % [case_name, detail])


func _finish() -> void:
	get_tree().paused = false
	if _recorded != EXPECTED_CASE_COUNT:
		print("TEST_ERROR missing_cases expected=%d recorded=%d" % [EXPECTED_CASE_COUNT, _recorded])
		_failed += 1
	var overall_passed: bool = _passed > 0 and _failed == 0 and _recorded == EXPECTED_CASE_COUNT
	print("TEST_RESULT %s passed=%d failed=%d skipped=%d" % ["PASS" if overall_passed else "FAIL", _passed, _failed, _skipped])
	get_tree().quit(0 if overall_passed else 1)
