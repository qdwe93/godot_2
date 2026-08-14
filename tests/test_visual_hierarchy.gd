extends Node


const EXPECTED_CASE_COUNT: int = 5
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const XP_GEM_SCENE: PackedScene = preload("res://scenes/xp_gem.tscn")
const PROJECTILE_SCENE: PackedScene = preload("res://scenes/projectile.tscn")
const PLAYER_SCRIPT: Script = preload("res://scripts/player.gd")
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
	_test_world_draw_order()
	await _dispose_main()
	_finish()



## 세계의 **그리기 순서**가 못박혀 있는가.
##
## 예전에는 월드 컨테이너의 z_index 가 전부 0 이라 그리는 순서가 곧 **씬 트리 순서**였다.
## 그래서 젬(PickupContainer)이 적(EnemyContainer)보다 씬에서 나중에 나온다는 이유만으로
## 적 위에 그려졌고, 몹이 경험치 구슬 뒤로 지나가는 것처럼 보였다. 사용자가 실기에서
## 지적한 문제다.
##
## **숫자를 검사하지 않는다.** 검사하는 것은 순서다 — 값은 얼마든 조정할 수 있어야 한다.
func _test_world_draw_order() -> void:
	# 아래에서 위로. 이 순서가 뒤집히면 무언가가 엉뚱한 것 뒤로 숨는다.
	var expected_order: Array[String] = [
		"PickupContainer",    # 젬은 바닥에 떨어져 있다
		"EnemyContainer",
		"Player",
		"ProjectileContainer",
		"EffectContainer",
	]
	var offenders: PackedStringArray = []
	var readings: PackedStringArray = []
	var previous_z: int = -2147483648
	var previous_name: String = ""
	for node_name in expected_order:
		var node: CanvasItem = _main.get_node_or_null(node_name) as CanvasItem
		if node == null:
			offenders.append("%s(없음)" % node_name)
			continue
		readings.append("%s=%d" % [node_name, node.z_index])
		if node.z_index <= previous_z:
			offenders.append("%s(%d) <= %s(%d)" % [node_name, node.z_index, previous_name, previous_z])
		previous_z = node.z_index
		previous_name = node_name

	# 바닥은 무엇보다도 아래여야 한다.
	var ground: CanvasItem = _main.get_node_or_null("Ground") as CanvasItem
	if ground == null:
		offenders.append("Ground(없음)")
	else:
		readings.append("Ground=%d" % ground.z_index)
		if ground.z_index >= previous_z:
			offenders.append("Ground(%d) 가 맨 아래가 아니다" % ground.z_index)

	_record_case("world_draw_order", offenders.is_empty(),
		"%s %s" % [" ".join(readings), "ok" if offenders.is_empty() else ",".join(offenders)])


func _read_visual_colours() -> Dictionary:
	# 배경은 BackgroundLayer(CanvasLayer) 아래로 옮겼다. Control 앵커가 Node2D 부모
	# 밑에서는 동작하지 않아 화면비가 다른 기기에서 뷰포트를 못 덮었기 때문이다.
	var background: ColorRect = _main.get_node_or_null("BackgroundLayer/Background") as ColorRect
	var player: Node = PLAYER_SCENE.instantiate()
	var gem: Node = XP_GEM_SCENE.instantiate()
	var projectile: Node = PROJECTILE_SCENE.instantiate()
	# 플레이어 스프라이트는 M15에서 텍스처가 됐다. 그림에 색이 구워져 있어 노드에서
	# 읽을 수 없으므로 규칙상의 기준 색을 스크립트 상수에서 읽는다. 그림이 그 색과
	# 실제로 맞는지는 tools/check_sprite_luminance.py 가 축소해서 잰다.
	var player_colour: Color = Color(PLAYER_SCRIPT.BASE_SPRITE_COLOUR)
	var gem_sprite: CanvasItem = gem.get_node_or_null("Sprite") as CanvasItem if gem != null else null
	var projectile_sprite: CanvasItem = projectile.get_node_or_null("Sprite") as CanvasItem if projectile != null else null
	var boss_spawner: Node = BOSS_SPAWNER_SCRIPT.new()
	# ColorRect와 Polygon2D 둘 다 color 속성을 갖는다. 타입으로 못 박으면
	# 스프라이트 노드 종류를 바꾸는 순간 테스트가 조용히 셋업 실패한다.
	if background == null or boss_spawner == null or not _has_colour(gem_sprite) or not _has_colour(projectile_sprite):
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
		"player": player_colour,
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
	# 적록색각이상에서는 빨강·주황·자주가 같은 갈색으로 수렴한다. 그래서 형태가
	# 유일한 구분 수단이다. 예전에는 Polygon2D 의 점 개수를 셌는데, M15에서
	# 스프라이트로 바뀌면서 셀 점이 없어졌다. 대신 **변종마다 다른 그림을 쓰는가**를 본다.
	var textures: Dictionary = {}
	var missing: PackedStringArray = []
	for variant_id: StringName in WaveData.ENEMY_TYPES:
		var texture_path: String = str(WaveData.get_enemy_type(variant_id).get("texture", ""))
		if texture_path.is_empty():
			missing.append(String(variant_id))
			continue
		if not ResourceLoader.exists(texture_path):
			missing.append("%s(no_file)" % variant_id)
			continue
		textures[texture_path] = true
	var variant_count: int = WaveData.ENEMY_TYPES.size()
	var distinct: int = textures.size()
	_record_case(
		"enemy_variants_have_distinct_shapes",
		missing.is_empty() and distinct == variant_count and variant_count >= 2,
		"variants=%d distinct_textures=%d missing=%s" % [
			variant_count, distinct, "none" if missing.is_empty() else ",".join(missing)]
	)


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
