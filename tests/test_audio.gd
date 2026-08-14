extends Node

const EXPECTED_CASE_COUNT: int = 21
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy.tscn")
const PROJECTILE_SCENE: PackedScene = preload("res://scenes/projectile.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const XP_GEM_SCENE: PackedScene = preload("res://scenes/xp_gem.tscn")
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const VOLUME_SETTINGS_SCENE: PackedScene = preload("res://scenes/volume_settings.tscn")
const WEAPON_SCRIPT: Script = preload("res://scripts/weapon.gd")

var _passed: int = 0
var _failed: int = 0
var _skipped: int = 0
var _audio: AudioManager


class ExperienceTarget extends Node2D:
	var received_experience: float = 0.0

	func add_experience(amount: float) -> void:
		received_experience += amount


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
	_test_default_volume_is_full()
	_test_volume_survives_a_reload()
	_test_broken_settings_fall_back_to_default()
	_test_volume_buttons_change_the_volume()
	_test_volume_buttons_are_opaque_and_tappable()
	await _test_firing_calls_the_sound()
	await _test_collecting_a_gem_calls_the_sound()
	_test_pickup_is_the_quietest_and_throttled_sound()
	await _test_damage_and_death_call_the_sounds()
	await _test_game_start_and_death_drive_the_music()
	await _test_volume_ui_is_in_the_pause_menu()


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
		"default_volume_is_full",
		"volume_survives_a_reload",
		"broken_settings_fall_back_to_default",
		"volume_buttons_change_the_volume",
		"volume_buttons_are_opaque_and_tappable",
		"firing_calls_the_sound",
		"collecting_a_gem_calls_the_sound",
		"pickup_is_the_quietest_and_throttled_sound",
		"damage_and_death_call_the_sounds",
		"game_start_and_death_drive_the_music",
		"volume_ui_is_in_the_pause_menu",
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

	var original_music_volume: float = _audio.get_music_volume()
	var original_sfx_volume: float = _audio.get_sfx_volume()
	var original_muted: bool = AudioServer.is_bus_mute(master_index)

	_audio.set_music_volume(0.5)
	var half_db: float = AudioServer.get_bus_volume_db(music_index)
	_audio.set_sfx_volume(0.25)
	var quarter_db: float = AudioServer.get_bus_volume_db(sfx_index)
	_audio.set_music_volume(0.0)
	var zero_db: float = AudioServer.get_bus_volume_db(music_index)
	_audio.set_muted(true)
	var muted: bool = AudioServer.is_bus_mute(master_index)
	# 범위 밖 요청은 매니저가 직접 막아야 한다. UI 쪽 clamp 에 기대면 API 를 다른
	# 곳에서 부르는 순간 설계한 믹스보다 커진다.
	_audio.set_music_volume(1.5)
	var over_clamped: bool = is_equal_approx(_audio.get_music_volume(), 1.0)
	_audio.set_music_volume(-0.5)
	var under_clamped: bool = is_equal_approx(_audio.get_music_volume(), 0.0)

	var expected_half_db: float = _audio.get_music_base_db() + linear_to_db(0.5)
	var expected_quarter_db: float = _audio.get_sfx_base_db() + linear_to_db(0.25)
	var passed: bool = is_equal_approx(half_db, expected_half_db) and is_equal_approx(quarter_db, expected_quarter_db) and is_finite(zero_db) and zero_db <= -80.0 and muted and over_clamped and under_clamped
	_audio.set_music_volume(original_music_volume)
	_audio.set_sfx_volume(original_sfx_volume)
	AudioServer.set_bus_mute(master_index, original_muted)
	_record_case("volume_controls_reach_the_buses", passed, "half_db=%.3f quarter_db=%.3f zero_db=%.3f muted=%s clamp=%s/%s" % [half_db, quarter_db, zero_db, muted, over_clamped, under_clamped])


func _test_default_volume_is_full() -> void:
	var original_music_volume: float = _audio.get_music_volume()
	var original_sfx_volume: float = _audio.get_sfx_volume()
	DirAccess.remove_absolute(_audio.get_settings_path())
	_audio.load_settings()

	var music_index: int = AudioServer.get_bus_index(&"Music")
	var music_db: float = AudioServer.get_bus_volume_db(music_index) if music_index >= 0 else INF
	var music_volume: float = _audio.get_music_volume()
	var sfx_volume: float = _audio.get_sfx_volume()
	# **설계한 믹스**와 비교한다. `get_music_base_db()` 와 비교하면 그 값이 잘못
	# 잡혔을 때 양쪽이 같이 틀려서 통과한다 (고장 주입에서 실제로 놓쳤다).
	var designed_db: float = _read_layout_volume_db(&"Music")
	var passed: bool = is_equal_approx(music_volume, 1.0) and is_equal_approx(sfx_volume, 1.0) and is_finite(designed_db) and is_equal_approx(music_db, designed_db)

	_audio.set_music_volume(original_music_volume)
	_audio.set_sfx_volume(original_sfx_volume)
	_audio.save_settings()
	_record_case("default_volume_is_full", passed, "music=%.3f sfx=%.3f bus_db=%.3f designed_db=%.3f" % [music_volume, sfx_volume, music_db, designed_db])


func _test_volume_survives_a_reload() -> void:
	var original_music_volume: float = _audio.get_music_volume()
	var original_sfx_volume: float = _audio.get_sfx_volume()
	# **한 번에 둘 다 바꾸면 안 된다.** `save_settings()` 는 두 값을 함께 쓰므로,
	# 효과음 쪽 저장이 배경음악 값까지 같이 남긴다. 그래서 배경음악 저장을 통째로
	# 지워도 이 케이스가 통과했다 (고장 주입에서 실제로 놓쳤다). 따로 확인한다.
	_audio.set_music_volume(0.3)
	_audio.load_settings()
	var loaded_music: float = _audio.get_music_volume()

	_audio.set_sfx_volume(0.7)
	_audio.load_settings()
	var loaded_sfx: float = _audio.get_sfx_volume()
	var passed: bool = is_equal_approx(loaded_music, 0.3) and is_equal_approx(loaded_sfx, 0.7)

	_audio.set_music_volume(original_music_volume)
	_audio.set_sfx_volume(original_sfx_volume)
	_audio.save_settings()
	_record_case("volume_survives_a_reload", passed, "music=%.3f sfx=%.3f" % [loaded_music, loaded_sfx])


func _test_broken_settings_fall_back_to_default() -> void:
	var original_music_volume: float = _audio.get_music_volume()
	var original_sfx_volume: float = _audio.get_sfx_volume()
	var config: ConfigFile = ConfigFile.new()
	config.set_value("audio", "music_volume", 9.9)
	config.set_value("audio", "sfx_volume", "abc")
	var save_error: Error = config.save(_audio.get_settings_path())
	if save_error == OK:
		_audio.load_settings()

	var loaded_music: float = _audio.get_music_volume()
	var loaded_sfx: float = _audio.get_sfx_volume()
	var in_range: bool = loaded_music >= 0.0 and loaded_music <= 1.0 and loaded_sfx >= 0.0 and loaded_sfx <= 1.0
	var defaults_used: bool = is_equal_approx(loaded_music, 1.0) and is_equal_approx(loaded_sfx, 1.0)
	var passed: bool = save_error == OK and in_range and defaults_used

	_audio.set_music_volume(original_music_volume)
	_audio.set_sfx_volume(original_sfx_volume)
	_audio.save_settings()
	_record_case("broken_settings_fall_back_to_default", passed, "save_error=%s music=%.3f sfx=%.3f" % [error_string(save_error), loaded_music, loaded_sfx])


func _test_volume_buttons_change_the_volume() -> void:
	var original_music_volume: float = _audio.get_music_volume()
	_audio.set_music_volume(0.5)
	var volume_settings: Control = VOLUME_SETTINGS_SCENE.instantiate() as Control
	add_child(volume_settings)

	var minus_button: Button = volume_settings.get_node("Rows/MusicRow/MinusButton") as Button
	var plus_button: Button = volume_settings.get_node("Rows/MusicRow/PlusButton") as Button
	var before_volume: float = _audio.get_music_volume()
	var before_percent: int = int(volume_settings.call("get_displayed_music_percent"))
	minus_button.pressed.emit()
	var after_volume: float = _audio.get_music_volume()
	var after_percent: int = int(volume_settings.call("get_displayed_music_percent"))
	var changed_by_step: bool = is_equal_approx(before_volume - after_volume, 0.1)
	# 바와 숫자를 **둘 다** 본다. 하나만 보면 다른 하나가 굳어 있어도 통과한다.
	var after_text: String = str(volume_settings.call("get_displayed_music_text"))
	var display_followed: bool = before_percent - after_percent == 10 and after_percent == roundi(after_volume * 100.0) and after_text == "%d%%" % after_percent

	_audio.set_music_volume(1.0)
	plus_button.pressed.emit()
	var upper_volume: float = _audio.get_music_volume()
	_audio.set_music_volume(0.0)
	minus_button.pressed.emit()
	var lower_volume: float = _audio.get_music_volume()
	var stayed_in_range: bool = upper_volume <= 1.0 and lower_volume >= 0.0

	volume_settings.queue_free()
	_audio.set_music_volume(original_music_volume)
	_audio.save_settings()
	var passed: bool = changed_by_step and display_followed and stayed_in_range
	_record_case("volume_buttons_change_the_volume", passed, "before=%.3f/%d after=%.3f/%d text=%s upper=%.3f lower=%.3f" % [before_volume, before_percent, after_volume, after_percent, after_text, upper_volume, lower_volume])


func _test_volume_buttons_are_opaque_and_tappable() -> void:
	var volume_settings: Control = VOLUME_SETTINGS_SCENE.instantiate() as Control
	add_child(volume_settings)
	var buttons: Array[Button] = []
	_collect_buttons(volume_settings, buttons)
	var failures: Array[String] = []
	for button: Button in buttons:
		var large_enough: bool = button.custom_minimum_size.x >= 76.0 and button.custom_minimum_size.y >= 76.0
		var normal_style: StyleBox = button.get_theme_stylebox(&"normal")
		var opaque: bool = false
		if normal_style is StyleBoxFlat:
			var flat_style: StyleBoxFlat = normal_style as StyleBoxFlat
			opaque = is_equal_approx(flat_style.bg_color.a, 1.0)
		if not large_enough or not opaque:
			failures.append("%s(size=%s opaque=%s)" % [button.get_path(), button.custom_minimum_size, opaque])

	# 바도 화면을 덮는 요소다. 반투명이면 화면 한가운데 고정된 주인공이 그대로
	# 비쳐 보인다 — 실제로 그랬고 캡처로만 발견했다.
	var bars: Array[ProgressBar] = []
	_collect_bars(volume_settings, bars)
	for bar: ProgressBar in bars:
		for style_name: StringName in [&"background", &"fill"]:
			var style: StyleBox = bar.get_theme_stylebox(style_name)
			var style_opaque: bool = style is StyleBoxFlat and is_equal_approx((style as StyleBoxFlat).bg_color.a, 1.0)
			if not style_opaque:
				failures.append("%s/%s(불투명 아님)" % [bar.get_path(), style_name])

	var passed: bool = buttons.size() == 4 and bars.size() == 2 and failures.is_empty()
	volume_settings.queue_free()
	_record_case("volume_buttons_are_opaque_and_tappable", passed, "buttons=%d bars=%d failures=%s" % [buttons.size(), bars.size(), failures])


func _collect_bars(node: Node, bars: Array[ProgressBar]) -> void:
	if node is ProgressBar:
		bars.append(node as ProgressBar)
	for child: Node in node.get_children():
		_collect_bars(child, bars)


## 버스 레이아웃 파일에서 직접 읽는다. 수치를 테스트에 하드코딩하면 믹스를 바꿀 때
## 테스트가 막아선다 — 이 프로젝트에서 두 번 그랬다.
func _read_layout_volume_db(bus_name: StringName) -> float:
	var layout: Resource = load("res://default_bus_layout.tres")
	if layout == null:
		return NAN
	for index: int in range(8):
		var name_value: Variant = layout.get("bus/%d/name" % index)
		if name_value != null and StringName(str(name_value)) == bus_name:
			var db_value: Variant = layout.get("bus/%d/volume_db" % index)
			return float(db_value) if db_value != null else NAN
	return NAN


func _collect_buttons(node: Node, buttons: Array[Button]) -> void:
	if node is Button:
		buttons.append(node as Button)
	for child: Node in node.get_children():
		_collect_buttons(child, buttons)


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


func _test_collecting_a_gem_calls_the_sound() -> void:
	var target: ExperienceTarget = ExperienceTarget.new()
	add_child(target)
	target.global_position = Vector2.ZERO

	var gem: Area2D = XP_GEM_SCENE.instantiate() as Area2D
	var gem_created: bool = gem != null
	if not gem_created:
		var received_before_cleanup: float = target.received_experience
		_record_case("collecting_a_gem_calls_the_sound", false,
			"gem_created=false pickup_count=%d experience=%.3f" % [_audio.get_play_count(&"pickup"), received_before_cleanup])
		target.queue_free()
		return
	add_child(gem)
	gem.global_position = target.global_position
	gem.set(&"target", target)

	# 직전 케이스의 재생 시각까지 지워, 획득음 솎기가 배선 검사를 가리지 않게 한다.
	_audio.reset_counters()
	# physics_frame 신호는 노드들의 _physics_process 직전에 오므로, 두 번째 신호에서
	# 첫 번째 물리 틱이 실제로 젬 수집을 수행한 결과를 읽는다.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var pickup_count: int = int(_audio.get_play_count(&"pickup"))
	var received_experience: float = target.received_experience

	if is_instance_valid(gem):
		gem.queue_free()
	target.queue_free()
	_record_case("collecting_a_gem_calls_the_sound",
		gem_created and pickup_count == 1 and received_experience > 0.0,
		"gem_created=%s pickup_count=%d experience=%.3f" % [gem_created, pickup_count, received_experience])


func _test_pickup_is_the_quietest_and_throttled_sound() -> void:
	var pickup_definition: Dictionary = AudioManager.SFX_LIBRARY[&"pickup"]
	var pickup_interval: float = float(pickup_definition.get("min_interval", 0.0))
	var pickup_volume: float = float(pickup_definition.get("volume_db", INF))
	var minimum_volume: float = INF
	var volumes: PackedStringArray = []
	for key: Variant in AudioManager.SFX_LIBRARY.keys():
		var sound_name: StringName = StringName(key)
		var definition: Dictionary = AudioManager.SFX_LIBRARY[sound_name]
		var volume_db: float = float(definition.get("volume_db", INF))
		minimum_volume = minf(minimum_volume, volume_db)
		volumes.append("%s=%.1f" % [sound_name, volume_db])
	var passed: bool = pickup_interval > 0.0 and pickup_volume == minimum_volume
	_record_case("pickup_is_the_quietest_and_throttled_sound", passed,
		"interval=%.3f pickup_db=%.1f minimum_db=%.1f library=[%s]" % [pickup_interval, pickup_volume, minimum_volume, ",".join(volumes)])


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


func _test_volume_ui_is_in_the_pause_menu() -> void:
	# 씬이 혼자 동작하는 것과 일시정지 화면에 붙어 있는 것은 다른 문제다.
	# 이 프로젝트에서 "정의는 멀쩡한데 호출처가 0건"이 세 번 나왔다.
	var main: Node = MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var game_flow: Node = main.get_node_or_null("GameFlow")
	if game_flow == null:
		main.queue_free()
		get_tree().paused = false
		_record_case("volume_ui_is_in_the_pause_menu", false, "GameFlow 를 찾지 못했다")
		return

	game_flow.call(&"start_game")
	# 화면을 열기 **전에** 음량을 바꿔 둔다. 열 때 다시 읽지 않으면 숫자가 옛날 값으로
	# 남는데, 실제로 그랬다 (캡처로 발견). 이 순서가 아니면 그 결함을 못 잡는다.
	var original_music_volume: float = _audio.get_music_volume()
	_audio.set_music_volume(0.4)
	game_flow.call(&"open_pause_menu")
	await get_tree().process_frame

	var volume_settings: Control = game_flow.get_node_or_null("PausePanel/VolumeSettings") as Control
	var found: bool = volume_settings != null
	var visible_now: bool = found and volume_settings.is_visible_in_tree()
	var display_is_fresh: bool = found and int(volume_settings.call("get_displayed_music_percent")) == 40

	# 화면 밖으로 밀려나면 폰에서 못 누른다. 설계 해상도 세로 720 안에 들어와야 한다.
	var fits: bool = false
	var buttons_ok: bool = false
	var bottom: float = -1.0
	if found:
		var rect: Rect2 = volume_settings.get_global_rect()
		bottom = rect.position.y + rect.size.y
		fits = rect.position.y >= 0.0 and bottom <= 720.0
		var minus: Button = volume_settings.get_node_or_null("Rows/MusicRow/MinusButton") as Button
		var plus: Button = volume_settings.get_node_or_null("Rows/SfxRow/PlusButton") as Button
		# 컨테이너가 실제로 크기를 준 뒤의 값을 본다. custom_minimum_size 만 보면
		# 부모가 눌러 찌그러뜨린 경우를 놓친다.
		buttons_ok = minus != null and plus != null and minus.size.x >= 64.0 and minus.size.y >= 64.0 and plus.size.x >= 64.0 and plus.size.y >= 64.0

	main.queue_free()
	get_tree().paused = false
	_audio.set_music_volume(original_music_volume)
	_audio.save_settings()
	var passed: bool = found and visible_now and fits and buttons_ok and display_is_fresh
	_record_case("volume_ui_is_in_the_pause_menu", passed, "found=%s visible=%s fits=%s(bottom=%.0f) buttons=%s fresh=%s" % [found, visible_now, fits, bottom, buttons_ok, display_is_fresh])
