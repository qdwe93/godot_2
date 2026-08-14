extends Node

const EXPECTED_CASE_COUNT: int = 13
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy.tscn")
const PROJECTILE_SCENE: PackedScene = preload("res://scenes/projectile.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const WEAPON_SCRIPT: Script = preload("res://scripts/weapon.gd")

var _passed: int = 0
var _failed: int = 0
var _skipped: int = 0
var _audio: AudioManager


func _ready() -> void:
	# 일시정지 검증 도중에도 하네스가 마지막 정리까지 수행해야 한다.
	process_mode = Node.PROCESS_MODE_ALWAYS
	var audio_node: Node = get_node_or_null("/root/Audio")
	if audio_node == null or not (audio_node is AudioManager):
		print("TEST_ERROR Audio autoload not found at /root/Audio")
		_record_missing_autoload_failures()
	else:
		_audio = audio_node as AudioManager
		await _run_cases()

	var total: int = _passed + _failed + _skipped
	if total != EXPECTED_CASE_COUNT:
		print("TEST_ERROR expected=%d actual=%d" % [EXPECTED_CASE_COUNT, total])
		_failed += 1
	var status: String = "PASS" if _failed == 0 and total == EXPECTED_CASE_COUNT else "FAIL"
	print("TEST_RESULT %s passed=%d failed=%d skipped=%d" % [status, _passed, _failed, _skipped])
	get_tree().quit(0 if status == "PASS" else 1)


func _run_cases() -> void:
	_test_buses_are_configured()
	_test_every_sfx_file_is_registered()
	_test_every_sfx_actually_plays()
	_test_repeat_calls_are_throttled()
	await _test_throttle_expires()
	_test_pool_is_bounded()
	_test_unknown_sound_is_ignored()
	_test_music_loops_and_can_be_stopped()
	await _test_music_survives_pause()
	_test_volume_controls_reach_the_buses()
	await _test_firing_calls_the_sound()
	await _test_damage_and_death_call_the_sounds()
	await _test_game_start_and_death_drive_the_music()


func _record_missing_autoload_failures() -> void:
	var case_names: Array[String] = [
		"buses_are_configured",
		"every_sfx_file_is_registered",
		"every_sfx_actually_plays",
		"repeat_calls_are_throttled",
		"throttle_expires",
		"pool_is_bounded",
		"unknown_sound_is_ignored",
		"music_loops_and_can_be_stopped",
		"music_survives_pause",
		"volume_controls_reach_the_buses",
		"firing_calls_the_sound",
		"damage_and_death_call_the_sounds",
		"game_start_and_death_drive_the_music",
	]
	for case_name: String in case_names:
		_record_case(case_name, false, "Audio autoload missing")


func _record_case(case_name: String, passed: bool, details: String) -> void:
	if passed:
		_passed += 1
	else:
		_failed += 1
	print("TEST_CASE %s %s %s" % [case_name, "PASS" if passed else "FAIL", details])


func _test_buses_are_configured() -> void:
	var music_index: int = AudioServer.get_bus_index(&"Music")
	var sfx_index: int = AudioServer.get_bus_index(&"SFX")
	var music_send: StringName = AudioServer.get_bus_send(music_index) if music_index >= 0 else &""
	var sfx_send: StringName = AudioServer.get_bus_send(sfx_index) if sfx_index >= 0 else &""
	var passed: bool = music_index >= 0 and sfx_index >= 0 and music_send == &"Master" and sfx_send == &"Master"
	_record_case("buses_are_configured", passed, "music=%d send=%s sfx=%d send=%s" % [music_index, music_send, sfx_index, sfx_send])


func _test_every_sfx_file_is_registered() -> void:
	var directory_path: String = "res://assets/audio/sfx"
	var registered_paths: Dictionary = {}
	var missing_files: Array[String] = []
	var unregistered_files: Array[String] = []

	for key: Variant in AudioManager.SFX_LIBRARY.keys():
		var definition: Dictionary = AudioManager.SFX_LIBRARY[key]
		var registered_path: String = String(definition.get("path", ""))
		registered_paths[registered_path] = true
		if not ResourceLoader.exists(registered_path):
			missing_files.append(registered_path)

	var disk_files: PackedStringArray = DirAccess.get_files_at(directory_path)
	for file_name: String in disk_files:
		# 임포트 부산물은 원본 효과음 수와 무관하므로 wav 원본만 비교한다.
		if file_name.get_extension().to_lower() != "wav":
			continue
		var full_path: String = directory_path.path_join(file_name)
		if not registered_paths.has(full_path):
			unregistered_files.append(full_path)

	var passed: bool = missing_files.is_empty() and unregistered_files.is_empty()
	_record_case("every_sfx_file_is_registered", passed, "disk=%d library=%d missing=%s unregistered=%s" % [disk_files.size(), AudioManager.SFX_LIBRARY.size(), missing_files, unregistered_files])


func _test_every_sfx_actually_plays() -> void:
	var failures: Array[String] = []
	for key: Variant in AudioManager.SFX_LIBRARY.keys():
		var sound_name: StringName = StringName(key)
		_audio.reset_counters()
		var played: bool = bool(_audio.play_sfx(sound_name))
		var count: int = int(_audio.get_play_count(sound_name))
		if not played or count != 1:
			failures.append("%s(played=%s,count=%d)" % [sound_name, played, count])
	_record_case("every_sfx_actually_plays", failures.is_empty(), "checked=%d failures=%s" % [AudioManager.SFX_LIBRARY.size(), failures])


func _test_repeat_calls_are_throttled() -> void:
	_audio.reset_counters()
	var accepted: int = 0
	for _request_index: int in range(20):
		if bool(_audio.play_sfx(&"shoot")):
			accepted += 1
	var count: int = int(_audio.get_play_count(&"shoot"))
	_record_case("repeat_calls_are_throttled", accepted == 1 and count == 1, "accepted=%d count=%d" % [accepted, count])


func _test_throttle_expires() -> void:
	_audio.reset_counters()
	var definition: Dictionary = AudioManager.SFX_LIBRARY[&"shoot"]
	var min_interval: float = float(definition.get("min_interval", 0.0))
	var first_played: bool = bool(_audio.play_sfx(&"shoot"))
	# 솎아내기가 보는 시계로 직접 기다린다. `create_timer` 는 짧은 시간에서
	# 프레임 델타만큼 먼저 끝나 버려 (50ms 요청에 실측 53ms/70ms) 판정이 흔들린다.
	var deadline_msec: int = Time.get_ticks_msec() + int(ceil(min_interval * 1000.0)) + 5
	while Time.get_ticks_msec() < deadline_msec:
		await get_tree().process_frame
	var second_played: bool = bool(_audio.play_sfx(&"shoot"))
	var count: int = int(_audio.get_play_count(&"shoot"))
	_record_case("throttle_expires", first_played and second_played and count == 2, "interval=%.3f first=%s second=%s count=%d" % [min_interval, first_played, second_played, count])


func _test_pool_is_bounded() -> void:
	var names: Array = _audio.get_sfx_names()
	var original_size: int = int(_audio.get_pool_size())
	var request_count: int = 100
	for request_index: int in range(request_count):
		# 제한 시간 초기화로 솎기를 우회해 같은 프레임에 풀 용량보다 많은 재생을 밀어 넣는다.
		_audio.reset_counters()
		var sound_name: StringName = StringName(names[request_index % names.size()])
		_audio.play_sfx(sound_name)
	var final_size: int = int(_audio.get_pool_size())
	var active_count: int = int(_audio.get_active_player_count())
	var passed: bool = original_size > 0 and final_size == original_size and active_count <= final_size
	_record_case("pool_is_bounded", passed, "requests=%d original=%d final=%d active=%d" % [request_count, original_size, final_size, active_count])


func _test_unknown_sound_is_ignored() -> void:
	var played: bool = bool(_audio.play_sfx(&"nope"))
	_record_case("unknown_sound_is_ignored", not played, "played=%s" % played)


func _find_music_player() -> AudioStreamPlayer:
	for child: Node in _audio.get_children():
		if child is AudioStreamPlayer:
			var player: AudioStreamPlayer = child as AudioStreamPlayer
			if player.bus == &"Music" or player.name == &"MusicPlayer":
				return player
	return null


func _test_music_loops_and_can_be_stopped() -> void:
	var music_player: AudioStreamPlayer = _find_music_player()
	var has_mp3: bool = music_player != null and music_player.stream is AudioStreamMP3
	var loops: bool = false
	if has_mp3:
		var mp3_stream: AudioStreamMP3 = music_player.stream as AudioStreamMP3
		loops = mp3_stream.loop
	_audio.stop_music()
	_audio.play_music()
	var started: bool = bool(_audio.is_music_playing())
	_audio.stop_music()
	var stopped: bool = not bool(_audio.is_music_playing())
	_record_case("music_loops_and_can_be_stopped", has_mp3 and loops and started and stopped, "mp3=%s loop=%s started=%s stopped=%s" % [has_mp3, loops, started, stopped])


func _test_music_survives_pause() -> void:
	_audio.stop_music()
	_audio.play_music()
	var started_before_pause: bool = bool(_audio.is_music_playing())
	_audio.reset_counters()
	get_tree().paused = true
	# 한 프레임을 실제로 넘겨 정지 직후의 값만 확인하는 허술한 검사가 되지 않게 한다.
	await get_tree().process_frame
	var music_still_playing: bool = bool(_audio.is_music_playing())
	var sfx_played: bool = bool(_audio.play_sfx(&"level_up"))
	# 뒤 테스트와 종료 처리가 멈추지 않도록 성공 여부와 관계없이 즉시 복구한다.
	get_tree().paused = false
	_record_case("music_survives_pause", started_before_pause and music_still_playing and sfx_played, "started=%s playing=%s sfx=%s" % [started_before_pause, music_still_playing, sfx_played])


func _test_volume_controls_reach_the_buses() -> void:
	var music_index: int = AudioServer.get_bus_index(&"Music")
	var sfx_index: int = AudioServer.get_bus_index(&"SFX")
	var master_index: int = AudioServer.get_bus_index(&"Master")
	if music_index < 0 or sfx_index < 0 or master_index < 0:
		_record_case("volume_controls_reach_the_buses", false, "required bus missing")
		return

	var original_music_db: float = AudioServer.get_bus_volume_db(music_index)
	var original_sfx_db: float = AudioServer.get_bus_volume_db(sfx_index)
	var original_muted: bool = AudioServer.is_bus_mute(master_index)

	_audio.set_music_volume(0.5)
	var half_db: float = AudioServer.get_bus_volume_db(music_index)
	_audio.set_sfx_volume(0.25)
	var quarter_db: float = AudioServer.get_bus_volume_db(sfx_index)
	_audio.set_music_volume(0.0)
	var zero_db: float = AudioServer.get_bus_volume_db(music_index)
	_audio.set_muted(true)
	var muted: bool = AudioServer.is_bus_mute(master_index)

	var passed: bool = is_equal_approx(half_db, linear_to_db(0.5)) and is_equal_approx(quarter_db, linear_to_db(0.25)) and is_finite(zero_db) and zero_db <= -80.0 and muted
	AudioServer.set_bus_volume_db(music_index, original_music_db)
	AudioServer.set_bus_volume_db(sfx_index, original_sfx_db)
	AudioServer.set_bus_mute(master_index, original_muted)
	_record_case("volume_controls_reach_the_buses", passed, "half_db=%.3f quarter_db=%.3f zero_db=%.3f muted=%s" % [half_db, quarter_db, zero_db, muted])


## 배선 검사 — "매니저가 소리를 낼 수 있다"와 "게임이 그 소리를 부른다"는 다른 문제다.
##
## 이 프로젝트에서 정의는 멀쩡한데 호출처가 0건이던 버그가 세 번 나왔다.
## 아래 두 케이스는 실제 무기와 실제 플레이어를 굴려 재생 횟수를 본다.


func _test_firing_calls_the_sound() -> void:
	var projectile_container: Node2D = Node2D.new()
	projectile_container.add_to_group(&"projectile_container")
	add_child(projectile_container)

	var enemy: Node2D = ENEMY_SCENE.instantiate() as Node2D
	# 그룹 등록은 씬이 아니라 스포너가 한다. 테스트에서도 스포너와 같은 일을 해 줘야
	# 무기가 적을 찾는다 (`enemy_spawner.gd` 127행과 같은 문자열이다).
	enemy.add_to_group(&"enemies")
	add_child(enemy)
	enemy.global_position = Vector2(60.0, 0.0)

	var weapon: Node2D = WEAPON_SCRIPT.new() as Node2D
	weapon.set(&"projectile_scene", PROJECTILE_SCENE)
	weapon.set(&"attack_range", 400.0)
	add_child(weapon)
	weapon.global_position = Vector2.ZERO
	await get_tree().physics_frame

	_audio.reset_counters()
	var projectile: Variant = weapon.call(&"try_fire")
	# 발사체는 곧 자가 해제될 수 있다. "만들어졌는가"는 지금 bool 로 붙잡는다.
	var fired: bool = projectile != null
	var shoot_count: int = int(_audio.get_play_count(&"shoot"))

	weapon.queue_free()
	enemy.queue_free()
	projectile_container.queue_free()
	_record_case("firing_calls_the_sound", fired and shoot_count == 1, "fired=%s shoot_count=%d" % [fired, shoot_count])


func _test_damage_and_death_call_the_sounds() -> void:
	var player: Node = PLAYER_SCENE.instantiate()
	player.set(&"health_regen", 0.0)
	add_child(player)
	await get_tree().physics_frame

	_audio.reset_counters()
	player.call(&"take_damage", 1.0)
	var hurt_after_damage: int = int(_audio.get_play_count(&"hurt"))
	var death_after_damage: int = int(_audio.get_play_count(&"death"))

	player.call(&"advance_invincibility", 10.0)
	# **여기서 반드시 다시 초기화한다.** `hurt` 는 최소 간격이 150ms 라, 바로 위
	# 피해에서 이미 한 번 났다는 이유만으로 솎여 버린다. 그러면 "죽는 프레임에
	# 피격음을 내지 않는다"를 검사하는 게 아니라 솎아내기를 검사하는 꼴이 되고,
	# 실제로 `_die()` 뒤의 `return` 을 지워도 이 케이스가 통과했다.
	_audio.reset_counters()
	player.call(&"take_damage", 999999.0)
	var hurt_on_death: int = int(_audio.get_play_count(&"hurt"))
	var death_on_death: int = int(_audio.get_play_count(&"death"))

	player.queue_free()
	var passed: bool = hurt_after_damage == 1 and death_after_damage == 0 and hurt_on_death == 0 and death_on_death == 1
	_record_case("damage_and_death_call_the_sounds", passed, "damage(hurt=%d death=%d) death_frame(hurt=%d death=%d)" % [hurt_after_damage, death_after_damage, hurt_on_death, death_on_death])


func _test_game_start_and_death_drive_the_music() -> void:
	# 배경음악만은 실제 게임 씬으로 확인한다. GameFlow 는 노드 경로를 여러 개 물고
	# 있어 손으로 조립하면 "조립이 틀린 것"과 "배선이 빠진 것"을 구별할 수 없다.
	var main: Node = MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var game_flow: Node = main.get_node_or_null("GameFlow")
	var player: Node = main.get_node_or_null("Player")
	if game_flow == null or player == null:
		main.queue_free()
		get_tree().paused = false
		_record_case("game_start_and_death_drive_the_music", false, "GameFlow 또는 Player 를 찾지 못했다")
		return

	_audio.stop_music()
	game_flow.call(&"start_game")
	var playing_after_start: bool = bool(_audio.is_music_playing())

	_audio.reset_counters()
	player.call(&"advance_invincibility", 10.0)
	player.call(&"take_damage", 999999.0)
	await get_tree().process_frame
	var playing_after_death: bool = bool(_audio.is_music_playing())
	var death_count: int = int(_audio.get_play_count(&"death"))

	main.queue_free()
	# 사망 처리가 트리를 멈춰 둔 채 끝나면 뒤 정리가 진행되지 않는다.
	get_tree().paused = false
	var passed: bool = playing_after_start and not playing_after_death and death_count == 1
	_record_case("game_start_and_death_drive_the_music", passed, "start=%s after_death=%s death_count=%d" % [playing_after_start, playing_after_death, death_count])
