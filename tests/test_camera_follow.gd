extends Node

## M16 — 카메라 도입으로 세계가 무한해졌다. 그 결과 성립해야 하는 **관계**를 고정한다.
##
## 실기 테스트에서 사용자가 요구한 것:
##   "이동할때 배경이 이동되는게 아니고 주인공이 이동하는거. 주인공은 항상 가운데 있어야해"
##
## 이 한 줄이 바꾸는 것이 생각보다 많다.
##
##   1. 주인공을 뷰포트 사각형에 가두던 `_clamp_to_screen()` 이 의미를 잃는다.
##      사각형이 주인공과 함께 움직이므로 자기 자신을 가두는 꼴이 된다.
##   2. 적 스폰 기준이 "월드 원점 근처의 화면"에서 **"지금 보이는 화면"** 으로 바뀐다.
##      안 바꾸면 주인공이 멀리 가는 순간 적이 아예 안 나온다.
##   3. 화면 흔들림 대상이 Main 에서 **카메라**로 바뀐다. Main 을 흔들면 카메라도
##      자식으로 같이 움직여 화면상으로는 아무 일도 일어나지 않는다.
##   4. 뒤처진 적을 회수해야 한다. 주인공(200)이 적(40~115)보다 빠르므로 한 방향으로
##      달리면 뒤쪽 적은 영원히 못 따라오면서 적 수 상한만 차지한다.
##   5. 배경이 단색이면 움직임이 안 보인다. 흐르는 격자가 유일한 단서다.
##
## 1~5 는 전부 "유닛 테스트는 통과하는데 게임은 이상한" 종류다. 관계로 고정한다.

const EXPECTED_CASE_COUNT: int = 7
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const GRID_SCRIPT = preload("res://scripts/background_grid.gd")

var _passed: int = 0
var _failed: int = 0
var _skipped: int = 0
var _recorded: int = 0
var _main: Node = null


func _ready() -> void:
	_main = MAIN_SCENE.instantiate()
	if _main == null:
		print("TEST_ERROR setup_failed main_scene_could_not_instantiate")
		_finish()
		return
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame

	# 타이틀 화면에서는 트리가 멈춰 있어 _physics_process 가 아예 돌지 않는다.
	var game_flow: Node = _main.get_node_or_null("GameFlow")
	if game_flow != null and game_flow.has_method(&"enable_auto_play"):
		game_flow.call(&"enable_auto_play")
	await get_tree().process_frame

	await _case_camera_is_current()
	await _case_player_stays_at_view_centre()
	await _case_player_is_not_clamped()
	await _case_enemies_spawn_around_the_view()
	await _case_distant_enemies_are_reclaimed()
	await _case_shake_moves_the_camera()
	await _case_ground_grid_follows_in_tile_steps()

	_main.free()
	_finish()


func _finish() -> void:
	if _recorded != EXPECTED_CASE_COUNT:
		print("TEST_ERROR missing_cases expected=%d recorded=%d" % [EXPECTED_CASE_COUNT, _recorded])
		_failed += 1
	var overall: String = "PASS" if _failed == 0 and _passed > 0 and _recorded == EXPECTED_CASE_COUNT else "FAIL"
	print("TEST_RESULT %s passed=%d failed=%d skipped=%d" % [overall, _passed, _failed, _skipped])
	get_tree().quit(0 if overall == "PASS" else 1)


func _player() -> Node2D:
	return _main.get_node_or_null("Player") as Node2D


## 카메라가 주인공의 자식으로 존재하고 실제로 활성인가.
func _case_camera_is_current() -> void:
	var camera: Camera2D = _main.get_node_or_null("Player/Camera2D") as Camera2D
	if camera == null:
		_record("camera_is_current", false, "player_has_no_camera2d")
		return
	await get_tree().process_frame
	_record("camera_is_current", camera.enabled and camera.is_current(),
		"enabled=%s current=%s" % [str(camera.enabled).to_lower(), str(camera.is_current()).to_lower()])


## 주인공이 어디로 가든 화면 한가운데에 있는가.
## 이것이 사용자가 요구한 바로 그것이다.
func _case_player_stays_at_view_centre() -> void:
	var player: Node2D = _player()
	if player == null:
		_record("player_stays_at_view_centre", false, "player_missing")
		return

	var offenders: PackedStringArray = []
	for spot: Vector2 in [Vector2(640.0, 360.0), Vector2(5000.0, -3200.0), Vector2(-12000.0, 8400.0)]:
		player.global_position = spot
		await get_tree().process_frame
		await get_tree().process_frame
		var centre: Vector2 = Arena.get_view_center(_main)
		if centre.distance_to(spot) > 1.0:
			offenders.append("at(%.0f,%.0f)->centre(%.0f,%.0f)" % [spot.x, spot.y, centre.x, centre.y])

	_record("player_stays_at_view_centre", offenders.is_empty(),
		"ok" if offenders.is_empty() else ",".join(offenders))


## 화면 밖으로 나가려 해도 되돌려지지 않는가.
## 예전 `_clamp_to_screen()` 이 남아 있으면 여기서 뷰포트 안으로 끌려 들어온다.
func _case_player_is_not_clamped() -> void:
	var player: Node2D = _player()
	if player == null:
		_record("player_is_not_clamped", false, "player_missing")
		return

	var arena: Vector2 = Arena.get_size(_main)
	var far_spot: Vector2 = Vector2(arena.x * 4.0, arena.y * -3.0)
	player.global_position = far_spot
	for _frame in range(4):
		await get_tree().physics_frame
	var drift: float = player.global_position.distance_to(far_spot)

	_record("player_is_not_clamped", drift <= 1.0,
		"placed=(%.0f,%.0f) now=(%.0f,%.0f) drift=%.1f" % [
			far_spot.x, far_spot.y, player.global_position.x, player.global_position.y, drift])


## 주인공이 멀리 떨어진 곳에 있어도 적이 **그 화면 둘레**에서 태어나는가.
## 월드 원점 기준으로 계산하면 주인공은 텅 빈 곳을 영원히 걷게 된다.
func _case_enemies_spawn_around_the_view() -> void:
	var player: Node2D = _player()
	var spawner: Node = _main.get_node_or_null("EnemySpawner")
	var container: Node = _main.get_node_or_null("EnemyContainer")
	if player == null or spawner == null or container == null:
		_record("enemies_spawn_around_the_view", false, "nodes_missing")
		return

	for child in container.get_children():
		child.free()

	var far_spot: Vector2 = Vector2(9000.0, -6000.0)
	player.global_position = far_spot
	await get_tree().process_frame
	await get_tree().process_frame

	var centre: Vector2 = Arena.get_view_center(_main)
	var expected_radius: float = Arena.get_spawn_radius(spawner, float(spawner.get(&"spawn_margin")))
	for _tick in range(4):
		spawner.call(&"trigger_spawn_tick_for_testing")
	await get_tree().process_frame

	var spawned: Array = container.get_children()
	if spawned.is_empty():
		_record("enemies_spawn_around_the_view", false, "no_enemy_spawned")
		return

	var offenders: PackedStringArray = []
	for enemy in spawned:
		var distance: float = (enemy as Node2D).global_position.distance_to(centre)
		if absf(distance - expected_radius) > 2.0:
			offenders.append("%.0f" % distance)

	_record("enemies_spawn_around_the_view", offenders.is_empty(),
		"count=%d centre=(%.0f,%.0f) radius=%.0f %s" % [
			spawned.size(), centre.x, centre.y, expected_radius,
			"ok" if offenders.is_empty() else "off=" + ",".join(offenders)])


## 너무 뒤처진 적은 조용히 회수되는가. **died 를 쏘면 안 된다** — 도망쳤다고
## 경험치와 처치 수가 들어오면 안 되기 때문이다.
func _case_distant_enemies_are_reclaimed() -> void:
	var player: Node2D = _player()
	var container: Node = _main.get_node_or_null("EnemyContainer")
	var enemy_scene: PackedScene = load("res://scenes/enemy.tscn") as PackedScene
	if player == null or container == null or enemy_scene == null:
		_record("distant_enemies_are_reclaimed", false, "nodes_missing")
		return

	for child in container.get_children():
		child.free()

	var enemy: Node2D = enemy_scene.instantiate() as Node2D
	enemy.set(&"target", player)
	enemy.set(&"despawn_distance", 500.0)
	container.add_child(enemy)
	enemy.global_position = player.global_position + Vector2(4000.0, 0.0)

	# died 가 새어 나오는지 감시한다. 람다는 지역 변수를 값으로 잡으므로 배열에 담는다.
	var death_reports: Array = []
	(enemy.get(&"died") as Signal).connect(func(_position: Vector2) -> void: death_reports.append(1))

	# 회수 검사는 30 물리프레임에 한 번, 인스턴스마다 위상을 흩어 돈다.
	for _frame in range(40):
		await get_tree().physics_frame
		if not is_instance_valid(enemy):
			break

	var reclaimed: bool = not is_instance_valid(enemy)
	_record("distant_enemies_are_reclaimed", reclaimed and death_reports.is_empty(),
		"reclaimed=%s died_emitted=%d" % [str(reclaimed).to_lower(), death_reports.size()])


## 흔들리는 것이 Main 이 아니라 카메라인가.
## Main 을 흔들면 카메라가 그 자식이라 같이 움직여 **화면은 미동도 하지 않는다.**
func _case_shake_moves_the_camera() -> void:
	var shaker: Node = _main.get_node_or_null("ScreenShake")
	var camera: Node2D = _main.get_node_or_null("Player/Camera2D") as Node2D
	if shaker == null or camera == null:
		_record("shake_moves_the_camera", false, "shaker_or_camera_missing")
		return

	var main_before: Vector2 = (_main as Node2D).position
	shaker.call(&"clear_cooldown_for_testing")
	shaker.call(&"shake", 0.5, 12.0)

	var camera_moved: bool = false
	for _frame in range(6):
		await get_tree().physics_frame
		if camera.position.length() > 0.5:
			camera_moved = true
			break
	var main_still: bool = (_main as Node2D).position.distance_to(main_before) <= 0.01

	# 뒷정리 — 흔들림이 끝나 원위치로 돌아오는지도 같이 본다.
	for _frame in range(40):
		await get_tree().physics_frame
	var restored: bool = camera.position.length() <= 0.01

	_record("shake_moves_the_camera", camera_moved and main_still and restored,
		"camera_moved=%s main_still=%s restored=%s" % [
			str(camera_moved).to_lower(), str(main_still).to_lower(), str(restored).to_lower()])


## 바닥 격자가 화면을 따라오되 **타일 단위로 끊어서** 오는가.
## 매끄럽게 따라오면 격자가 주인공에게 붙어 버려 아무것도 흐르지 않는다.
func _case_ground_grid_follows_in_tile_steps() -> void:
	var ground: Node2D = _main.get_node_or_null("Ground") as Node2D
	var player: Node2D = _player()
	if ground == null or player == null:
		_record("ground_grid_follows_in_tile_steps", false, "ground_or_player_missing")
		return

	var tile: float = float(GRID_SCRIPT.TILE_SIZE)
	var offenders: PackedStringArray = []
	for spot: Vector2 in [Vector2(0.0, 0.0), Vector2(1234.0, -987.0), Vector2(-5678.0, 4321.0)]:
		player.global_position = spot
		await get_tree().process_frame
		await get_tree().process_frame
		var centre: Vector2 = Arena.get_view_center(_main)
		var snapped_to_tile: bool = is_equal_approx(fmod(absf(ground.global_position.x), tile), 0.0) \
			and is_equal_approx(fmod(absf(ground.global_position.y), tile), 0.0)
		var covers_view: bool = ground.global_position.distance_to(centre) <= tile
		if not snapped_to_tile or not covers_view:
			offenders.append("at(%.0f,%.0f)->ground(%.0f,%.0f)" % [
				spot.x, spot.y, ground.global_position.x, ground.global_position.y])

	_record("ground_grid_follows_in_tile_steps", offenders.is_empty(),
		"tile=%.0f %s" % [tile, "ok" if offenders.is_empty() else ",".join(offenders)])


func _record(case_name: String, ok: bool, detail: String) -> void:
	_recorded += 1
	if ok:
		_passed += 1
		print("TEST_CASE %s PASS %s" % [case_name, detail])
	else:
		_failed += 1
		print("TEST_CASE %s FAIL %s" % [case_name, detail])
