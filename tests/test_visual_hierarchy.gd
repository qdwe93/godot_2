extends Node


const EXPECTED_CASE_COUNT: int = 6
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const XP_GEM_SCENE: PackedScene = preload("res://scenes/xp_gem.tscn")
const PROJECTILE_SCENE: PackedScene = preload("res://scenes/projectile.tscn")
const ORBITAL_SCENE: PackedScene = preload("res://scenes/orbital.tscn")
const GROUND_TILE: Texture2D = preload("res://assets/sprites/ground_tile.png")

var _passed: int = 0
var _failed: int = 0
var _skipped: int = 0
var _recorded: int = 0
var _main: Node = null


func _ready() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	if MAIN_SCENE == null or XP_GEM_SCENE == null or PROJECTILE_SCENE == null or ORBITAL_SCENE == null or GROUND_TILE == null:
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
	var tone_luminances: PackedFloat32Array = _read_ground_tile_tone_luminances()
	_test_ground_tile_value_band_is_narrow(tone_luminances)
	_test_outlined_elements_clear_minimum_contrast(tone_luminances)
	_test_colorrect_elements_are_outlined()
	_test_background_underlay_follows_the_tile()
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


func _read_ground_tile_tone_luminances() -> PackedFloat32Array:
	var image: Image = GROUND_TILE.get_image()
	if image == null or image.is_empty():
		return PackedFloat32Array()
	var luminances: Array[float] = []
	for y in range(0, image.get_height(), 4):
		for x in range(0, image.get_width(), 4):
			luminances.append(_relative_luminance(image.get_pixel(x, y)))
	if luminances.is_empty():
		return PackedFloat32Array()
	luminances.sort()
	var dark_index: int = roundi((luminances.size() - 1) * 0.02)
	var bright_index: int = roundi((luminances.size() - 1) * 0.98)
	return PackedFloat32Array([luminances[dark_index], luminances[bright_index]])


func _test_ground_tile_value_band_is_narrow(tone_luminances: PackedFloat32Array) -> void:
	# 이 명도 대역이 외곽선 전략 전체를 성립시킨다. #14141A의 휘도는 0.011이라 가장
	# 어두운 바닥 휘도 0.133까지 3:1을 넘지만, 대역이 넓어져 그 선을 건너면 외곽선
	# 두께를 아무리 늘려도 그 위의 스프라이트를 구할 수 없다.
	if tone_luminances.size() != 2:
		_record_case("ground_tile_value_band_is_narrow", false, "band=unreadable")
		return
	var dark_luminance: float = tone_luminances[0]
	var bright_luminance: float = tone_luminances[1]
	var passed: bool = (
		dark_luminance >= 0.28
		and dark_luminance <= 0.58
		and bright_luminance >= 0.28
		and bright_luminance <= 0.58
	)
	_record_case("ground_tile_value_band_is_narrow", passed,
		"dark=%.4f bright=%.4f allowed=0.28..0.58" % [dark_luminance, bright_luminance])


func _test_outlined_elements_clear_minimum_contrast(tone_luminances: PackedFloat32Array) -> void:
	# 어두운 톤에서만 통과하고 밝은 톤에서 실패하는 것도 불합격이다. 타일이 밝아지는
	# 자리마다 스프라이트가 사라진다면 바닥 전체에서 분리되는 외곽선이 아니기 때문이다.
	if tone_luminances.size() != 2:
		_record_case("outlined_elements_clear_minimum_contrast", false, "ground_tones=unreadable")
		return
	var definitions: Array[Dictionary] = _outlined_scene_definitions()
	var readings: PackedStringArray = []
	for definition in definitions:
		var element_name: String = String(definition["name"])
		var scene: PackedScene = definition["scene"] as PackedScene
		var instance: Node = scene.instantiate() if scene != null else null
		var outline: ColorRect = instance.get_node_or_null("Outline") as ColorRect if instance != null else null
		if outline == null:
			if instance != null:
				instance.free()
			_record_case("outlined_elements_clear_minimum_contrast", false, "%s tone=outline_missing" % element_name)
			return
		var outline_luminance: float = _relative_luminance(outline.color)
		for tone_index in range(2):
			var tone_name: String = "dark" if tone_index == 0 else "bright"
			var ratio: float = _contrast_ratio_from_luminances(outline_luminance, tone_luminances[tone_index])
			readings.append("%s.%s=%.2f" % [element_name, tone_name, ratio])
			if ratio < 3.0:
				instance.free()
				_record_case("outlined_elements_clear_minimum_contrast", false,
					"%s tone=%s ratio=%.2f" % [element_name, tone_name, ratio])
				return
		instance.free()
	_record_case("outlined_elements_clear_minimum_contrast", true, " ".join(readings))


func _test_colorrect_elements_are_outlined() -> void:
	# Outline이 Sprite보다 트리 뒤에 놓이면 채움을 받치는 대신 덮어 버린다. 오류 없이
	# 짙은 사각형 하나로 렌더링되는 실수라서 노드 순서까지 함께 검사한다.
	for definition in _outlined_scene_definitions():
		var element_name: String = String(definition["name"])
		var scene: PackedScene = definition["scene"] as PackedScene
		var instance: Node = scene.instantiate() if scene != null else null
		var outline: ColorRect = instance.get_node_or_null("Outline") as ColorRect if instance != null else null
		var sprite: ColorRect = instance.get_node_or_null("Sprite") as ColorRect if instance != null else null
		var valid: bool = outline != null and sprite != null
		if valid:
			valid = (
				outline.get_index() < sprite.get_index()
				and outline.offset_left < sprite.offset_left
				and outline.offset_top < sprite.offset_top
				and outline.offset_right > sprite.offset_right
				and outline.offset_bottom > sprite.offset_bottom
			)
		if instance != null:
			instance.free()
		if not valid:
			_record_case("colorrect_elements_are_outlined", false, "%s outline_order_or_size_invalid" % element_name)
			return
	_record_case("colorrect_elements_are_outlined", true, "elements=3 outline_before_sprite=true")


func _test_background_underlay_follows_the_tile() -> void:
	# 언더레이는 손으로 옮긴 16진수라 타일과 어긋나곤 했다. 이 검사가 둘을 계속 한데
	# 묶어 두어 바닥이 비는 순간에도 다른 색이 번쩍이지 않게 한다.
	var underlay: ColorRect = _main.get_node_or_null("BackgroundLayer/Background") as ColorRect
	if underlay == null:
		_record_case("background_underlay_follows_the_tile", false, "underlay=missing")
		return
	var tile_mean: Color = BackgroundGrid.read_tile_mean_colour()
	var difference: Color = Color(
		absf(underlay.color.r - tile_mean.r),
		absf(underlay.color.g - tile_mean.g),
		absf(underlay.color.b - tile_mean.b),
		absf(underlay.color.a - tile_mean.a)
	)
	var passed: bool = (
		difference.r <= 0.04
		and difference.g <= 0.04
		and difference.b <= 0.04
		and difference.a <= 0.04
	)
	_record_case("background_underlay_follows_the_tile", passed,
		"underlay=%s tile_mean=%s max_channel_delta=%.4f" % [
			underlay.color, tile_mean, maxf(maxf(difference.r, difference.g), maxf(difference.b, difference.a))])


func _outlined_scene_definitions() -> Array[Dictionary]:
	return [
		{"name": "xp_gem", "scene": XP_GEM_SCENE},
		{"name": "projectile", "scene": PROJECTILE_SCENE},
		{"name": "orbital", "scene": ORBITAL_SCENE},
	]


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


static func _contrast_ratio_from_luminances(first_luminance: float, second_luminance: float) -> float:
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
