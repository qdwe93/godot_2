extends Node

## 밸런스 진단 — 실제 main.tscn을 돌려 생존 시간과 성장 곡선을 측정한다.
##
## 테스트가 아니라 **측정 도구**다. PASS/FAIL이 없고 수치만 뱉는다.
## M10에서 매번 새로 쓰다 시간을 버려서 저장소에 남긴다.
##
## 실행:
##   Godot..._console.exe --headless --path <project> --quit-after 200000 \
##       res://tests/diag_balance.tscn -- --mode=bot --max=900
##
## 모드:
##   bot   기본. 회피 + 젬 수집을 흉내 내는 봇이 조작한다
##   idle  아무 입력도 넣지 않는다 (하한값 측정)
##
## 3택 선택 전략 (--pick=):
##   random  기본. GameFlow의 --auto-play가 첫 선택지를 고른다 (선택지 순서가
##           무작위이므로 사실상 무작위 선택이다)
##   greedy  화력 우선으로 고정한 최선 빌드. "선택이 나빠서 약한 것"과
##           "화력 상한 자체가 낮은 것"을 분리하려면 이 값이 필요하다.
##           우선순위는 tools/balance_sim.py 의 GREEDY 와 같은 순서로 맞춘다
##
## 출력 규약:
##   DIAG_START  mode=... max=...
##   DIAG_SAMPLE t=... enemies=... kills=... level=... hp=... dps=...
##   DIAG_UPGRADE t=... id=... level=...
##   DIAG_RESULT survived=... kills=... level=... reason=...
##
## 주의: 출력을 파이프로 받으면 버퍼링되어 진행이 안 보인다. 파일로 리다이렉트할 것.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

## 봇 행동 상수 (devlog 014의 규칙을 그대로 옮겼다)
const DANGER_RADIUS: float = 190.0
const GEM_SEEK_RADIUS: float = 400.0
const EDGE_MARGIN: float = 90.0
const THREAT_DEADZONE: float = 0.05

const MOVE_ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_up", &"move_down",
]

var _mode: String = "bot"
var _max_seconds: float = 900.0
var _sample_interval: float = 15.0
var _time_scale: float = 1.0
var _pick_strategy: String = "random"

## greedy 전략의 우선순위. 앞에 있을수록 먼저 고른다.
## 화력(산탄·궤도구·장갑)을 먼저 채우고, 생존(심장)과 기동(신발)을 뒤에 둔다.
## 왕관은 경험치만 늘려 직접 화력이 되지 않으므로 마지막이다.
const GREEDY_PRIORITY: Array[StringName] = [
	&"shotgun", &"orbital", &"blade", &"gloves", &"heart", &"shoes", &"magnet", &"crown",
]

var _main: Node = null
var _player: Node2D = null
var _enemy_container: Node2D = null
var _pickup_container: Node2D = null
var _enemy_spawner: Node = null
var _level_system: Node = null
var _hud: Node = null
var _game_flow: Node = null
var _upgrade_manager: Node = null

var _next_sample_at: float = 0.0
var _kills_at_last_sample: int = 0


func _ready() -> void:
	_parse_arguments()
	await _run()


func _parse_arguments() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "--idle":
			_mode = "idle"
		elif argument.begins_with("--mode="):
			_mode = argument.substr(7)
		elif argument.begins_with("--max="):
			_max_seconds = maxf(float(argument.substr(6)), 1.0)
		elif argument.begins_with("--sample="):
			_sample_interval = maxf(float(argument.substr(9)), 1.0)
		elif argument.begins_with("--pick="):
			_pick_strategy = argument.substr(7)
		elif argument.begins_with("--speed="):
			# 게임 시간은 실제 시간과 1:1이다. 15분짜리 판을 재려면 15분이 걸린다.
			# time_scale로 배속을 걸면 측정 사이클이 짧아진다. 물리 스텝 상한도
			# 같이 올리지 않으면 배속만큼 따라가지 못하고 조용히 느려진다.
			_time_scale = clampf(float(argument.substr(8)), 0.1, 20.0)


func _run() -> void:
	if MAIN_SCENE == null:
		print("DIAG_ERROR main scene could not be loaded")
		_finish_process()
		return

	_main = MAIN_SCENE.instantiate()
	if _main == null:
		print("DIAG_ERROR main scene could not be instantiated")
		_finish_process()
		return
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame

	if not _resolve_nodes():
		_finish_process()
		return

	# 타이틀 화면을 건너뛰고, 레벨업 3택도 자동으로 고르게 한다.
	_game_flow.call(&"enable_auto_play")
	if _pick_strategy == "greedy":
		# GameFlow의 자동 선택(항상 0번)과 경쟁하지 않도록 꺼 두고 여기서 고른다.
		_game_flow.set(&"auto_play_enabled", false)
	_connect_observers()

	if _time_scale != 1.0:
		Engine.max_physics_steps_per_frame = maxi(8, int(ceil(_time_scale)) * 8)
		Engine.time_scale = _time_scale

	print("DIAG_START mode=%s pick=%s max=%.1f sample=%.1f speed=%.1f" % [_mode, _pick_strategy, _max_seconds, _sample_interval, _time_scale])
	_next_sample_at = _sample_interval

	var reason: String = "max_time"
	while true:
		# physics_frame은 일시정지 중에 오지 않는다 (devlog 014 3절). process_frame을 쓴다.
		await get_tree().process_frame
		if not is_instance_valid(_player):
			reason = "player_freed"
			break
		if bool(_player.get(&"_is_dead")):
			reason = "died"
			break

		if _pick_strategy == "greedy":
			_pick_greedy_upgrade()

		if not get_tree().paused and _mode == "bot":
			_drive_bot()

		var elapsed: float = float(_enemy_spawner.call(&"get_elapsed_time"))
		if elapsed >= _next_sample_at:
			_emit_sample(elapsed)
			_next_sample_at += _sample_interval
		if elapsed >= _max_seconds:
			reason = "max_time"
			break

	_release_inputs()
	var final_elapsed: float = float(_enemy_spawner.call(&"get_elapsed_time"))
	_emit_sample(final_elapsed)
	print("DIAG_RESULT mode=%s pick=%s survived=%.1f kills=%d level=%d reason=%s" % [
		_mode,
		_pick_strategy,
		final_elapsed,
		_kill_count(),
		_current_level(),
		reason,
	])
	_print_upgrade_summary()
	_finish_process()


func _resolve_nodes() -> bool:
	_player = _main.get_node_or_null("Player") as Node2D
	_enemy_container = _main.get_node_or_null("EnemyContainer") as Node2D
	_pickup_container = _main.get_node_or_null("PickupContainer") as Node2D
	_enemy_spawner = _main.get_node_or_null("EnemySpawner")
	_hud = _main.get_node_or_null("HUD")
	_game_flow = _main.get_node_or_null("GameFlow")
	_upgrade_manager = _main.get_node_or_null("UpgradeManager")
	if _player != null:
		_level_system = _player.get_node_or_null("LevelSystem")

	var missing: PackedStringArray = []
	if _player == null:
		missing.append("Player")
	if _enemy_container == null:
		missing.append("EnemyContainer")
	if _enemy_spawner == null or not _enemy_spawner.has_method(&"get_elapsed_time"):
		missing.append("EnemySpawner.get_elapsed_time")
	if _game_flow == null or not _game_flow.has_method(&"enable_auto_play"):
		missing.append("GameFlow.enable_auto_play")
	if _level_system == null:
		missing.append("Player/LevelSystem")
	if not missing.is_empty():
		print("DIAG_ERROR missing=%s" % ",".join(missing))
		return false
	return true


func _connect_observers() -> void:
	# 업그레이드 선택 시점을 남기면 성장 곡선을 시간축에 얹어 볼 수 있다.
	var level_up_ui: Node = _main.get_node_or_null("LevelUpUI")
	if level_up_ui != null and level_up_ui.has_signal(&"upgrade_chosen"):
		level_up_ui.connect(&"upgrade_chosen", Callable(self, "_on_upgrade_chosen"))


func _on_upgrade_chosen(id: StringName) -> void:
	var elapsed: float = float(_enemy_spawner.call(&"get_elapsed_time"))
	var level: int = 0
	if _upgrade_manager != null and _upgrade_manager.has_method(&"get_level"):
		level = int(_upgrade_manager.call(&"get_level", id))
	print("DIAG_UPGRADE t=%.1f id=%s level=%d" % [elapsed, id, level])


## 봇 조작 — 위협에서 멀어지고, 한가하면 젬을 주우러 간다.
func _drive_bot() -> void:
	var player_position: Vector2 = _player.global_position
	var desired: Vector2 = Vector2.ZERO

	for child in _enemy_container.get_children():
		var enemy: Node2D = child as Node2D
		if enemy == null:
			continue
		var away: Vector2 = player_position - enemy.global_position
		var distance: float = away.length()
		if distance > 0.1 and distance < DANGER_RADIUS:
			# 가까울수록 강하게 밀려난다
			desired += away.normalized() * (1.0 - distance / DANGER_RADIUS)

	if desired.length() < THREAT_DEADZONE:
		var gem: Node2D = _find_nearest_gem(player_position)
		if gem != null:
			desired = (gem.global_position - player_position).normalized()

	desired += _edge_correction(player_position)

	if desired.length() < 0.001:
		_release_inputs()
		return
	_press_direction(desired.normalized())


## 우선순위가 가장 높은 선택지를 고른다. 없으면 0번.
func _pick_greedy_upgrade() -> void:
	var level_up_ui: Node = _main.get_node_or_null("LevelUpUI")
	if level_up_ui == null or not bool(level_up_ui.get(&"visible")):
		return
	var choices: Variant = level_up_ui.call(&"get_choice_ids")
	if not (choices is Array) or (choices as Array).is_empty():
		return
	var choice_ids: Array = choices as Array
	var best_index: int = 0
	var best_rank: int = GREEDY_PRIORITY.size()
	for index in range(choice_ids.size()):
		var rank: int = GREEDY_PRIORITY.find(StringName(choice_ids[index]))
		if rank >= 0 and rank < best_rank:
			best_rank = rank
			best_index = index
	level_up_ui.call(&"choose", best_index)


func _find_nearest_gem(from_position: Vector2) -> Node2D:
	if _pickup_container == null:
		return null
	var nearest: Node2D = null
	var nearest_distance: float = GEM_SEEK_RADIUS
	for child in _pickup_container.get_children():
		var gem: Node2D = child as Node2D
		if gem == null:
			continue
		var distance: float = from_position.distance_to(gem.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = gem
	return nearest


## 구석에 몰려 죽는 것을 막는다. 가장자리에 가까울수록 중앙으로 당긴다.
func _edge_correction(player_position: Vector2) -> Vector2:
	var width: float = float(ProjectSettings.get_setting("display/window/size/viewport_width"))
	var height: float = float(ProjectSettings.get_setting("display/window/size/viewport_height"))
	var correction: Vector2 = Vector2.ZERO
	if player_position.x < EDGE_MARGIN:
		correction.x += 1.0 - player_position.x / EDGE_MARGIN
	elif player_position.x > width - EDGE_MARGIN:
		correction.x -= 1.0 - (width - player_position.x) / EDGE_MARGIN
	if player_position.y < EDGE_MARGIN:
		correction.y += 1.0 - player_position.y / EDGE_MARGIN
	elif player_position.y > height - EDGE_MARGIN:
		correction.y -= 1.0 - (height - player_position.y) / EDGE_MARGIN
	return correction


func _press_direction(direction: Vector2) -> void:
	_release_inputs()
	if direction.x < 0.0:
		Input.action_press(&"move_left", absf(direction.x))
	elif direction.x > 0.0:
		Input.action_press(&"move_right", direction.x)
	if direction.y < 0.0:
		Input.action_press(&"move_up", absf(direction.y))
	elif direction.y > 0.0:
		Input.action_press(&"move_down", direction.y)


func _release_inputs() -> void:
	for action in MOVE_ACTIONS:
		if Input.is_action_pressed(action):
			Input.action_release(action)


func _kill_count() -> int:
	if _hud != null and _hud.has_method(&"get_kill_count"):
		return int(_hud.call(&"get_kill_count"))
	return 0


func _current_level() -> int:
	if _level_system != null:
		return int(_level_system.get(&"level"))
	return 0


## 이론 DPS — 실제 명중률이 아니라 "쏠 수 있는 양"의 상한이다.
## 적 체력 배율과 나란히 놓고 보면 화력이 따라가는지 알 수 있다.
func _theoretical_dps() -> float:
	var total: float = 0.0
	var weapon: Node = _player.get_node_or_null("Weapon")
	if weapon != null:
		var cooldown: float = float(weapon.get(&"cooldown"))
		if cooldown > 0.0:
			total += float(weapon.get(&"projectile_damage")) / cooldown
	var shotgun: Node = _player.get_node_or_null("Shotgun")
	if shotgun != null and bool(shotgun.get(&"is_unlocked")):
		var shotgun_cooldown: float = float(shotgun.get(&"cooldown"))
		if shotgun_cooldown > 0.0:
			total += float(shotgun.get(&"projectile_damage")) * float(shotgun.get(&"pellet_count")) / shotgun_cooldown
	var orbital: Node = _player.get_node_or_null("Orbital")
	if orbital != null and bool(orbital.get(&"is_unlocked")):
		var hit_interval: float = float(orbital.get(&"hit_interval"))
		if hit_interval > 0.0:
			total += float(orbital.get(&"damage")) / hit_interval
	return total


func _emit_sample(elapsed: float) -> void:
	var kills: int = _kill_count()
	var kills_delta: int = kills - _kills_at_last_sample
	_kills_at_last_sample = kills
	var phase_index: int = int(_enemy_spawner.call(&"get_current_phase_index"))
	var phase: Dictionary = WaveData.get_phase_for_time(elapsed)
	var health: float = float(_player.get(&"health")) if is_instance_valid(_player) else 0.0
	var max_health: float = float(_player.get(&"max_health")) if is_instance_valid(_player) else 0.0
	var gems: int = _pickup_container.get_child_count() if _pickup_container != null else 0

	print("DIAG_SAMPLE t=%.1f phase=%d enemies=%d gems=%d kills=%d kps=%.2f level=%d hp=%.0f/%.0f dps=%.1f hp_mult=%.1f fps=%.0f" % [
		elapsed,
		phase_index,
		_enemy_container.get_child_count(),
		gems,
		kills,
		float(kills_delta) / _sample_interval,
		_current_level(),
		health,
		max_health,
		_theoretical_dps(),
		float(phase.get("health_multiplier", 1.0)),
		Engine.get_frames_per_second(),
	])


func _print_upgrade_summary() -> void:
	if _upgrade_manager == null or not _upgrade_manager.has_method(&"get_level"):
		return
	var parts: PackedStringArray = []
	for upgrade_id in UpgradeData.get_all_ids():
		parts.append("%s=%d" % [upgrade_id, int(_upgrade_manager.call(&"get_level", upgrade_id))])
	print("DIAG_UPGRADES %s" % " ".join(parts))
	if _upgrade_manager.has_method(&"get_stat_report"):
		var report: Dictionary = _upgrade_manager.call(&"get_stat_report")
		print("DIAG_STATS speed=%.1f max_health=%.0f regen=%.2f cooldown=%.3f magnet=%.1f xp_mult=%.2f dps=%.1f shotgun=%s orbital=%s" % [
			float(report.get("speed", 0.0)),
			float(report.get("max_health", 0.0)),
			float(report.get("health_regen", 0.0)),
			float(report.get("cooldown", 0.0)),
			float(report.get("magnet_radius", 0.0)),
			float(report.get("experience_multiplier", 1.0)),
			float(report.get("theoretical_dps", 0.0)),
			str(report.get("shotgun_unlocked", false)).to_lower(),
			str(report.get("orbital_unlocked", false)).to_lower(),
		])


func _finish_process() -> void:
	_release_inputs()
	await get_tree().process_frame
	get_tree().quit(0)
