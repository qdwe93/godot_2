extends Node
class_name AudioManager

const SFX_POOL_SIZE: int = 12
const SILENT_VOLUME_DB: float = -80.0
const BGM_PATH: String = "res://assets/audio/bgm/main_theme.mp3"
const SETTINGS_PATH: String = "user://settings.cfg"

const SFX_LIBRARY: Dictionary = {
	&"shoot":    {"path": "res://assets/audio/sfx/shoot.wav",    "volume_db": -9.0,  "min_interval": 0.05, "pitch_jitter": 0.08},
	&"hit":      {"path": "res://assets/audio/sfx/hit.wav",      "volume_db": -13.0, "min_interval": 0.04, "pitch_jitter": 0.12},
	&"pickup":   {"path": "res://assets/audio/sfx/pickup.wav",   "volume_db": -16.0, "min_interval": 0.07, "pitch_jitter": 0.14},
	&"hurt":     {"path": "res://assets/audio/sfx/hurt.wav",     "volume_db": -4.0,  "min_interval": 0.15, "pitch_jitter": 0.05},
	&"level_up": {"path": "res://assets/audio/sfx/level_up.wav", "volume_db": -3.0,  "min_interval": 0.0,  "pitch_jitter": 0.0},
	&"death":    {"path": "res://assets/audio/sfx/death.wav",    "volume_db": -2.0,  "min_interval": 0.0,  "pitch_jitter": 0.0},
}

var _music_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_streams: Dictionary = {}
var _last_played_msec: Dictionary = {}
var _play_counts: Dictionary = {}
var _player_started_msec: Dictionary = {}

var _music_bus_name: StringName = &"Master"
var _sfx_bus_name: StringName = &"Master"
var _music_bus_index: int = -1
var _sfx_bus_index: int = -1
var _master_bus_index: int = -1
var _music_base_db: float = 0.0
var _sfx_base_db: float = 0.0
var _music_volume: float = 1.0
var _sfx_volume: float = 1.0


func _ready() -> void:
	# 일시정지 선택지에서도 소리가 이어져야 하므로 씬 트리의 정지 상태를 따르지 않는다.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_master_bus_index = AudioServer.get_bus_index(&"Master")
	_music_bus_name = _resolve_bus_name(&"Music")
	_sfx_bus_name = _resolve_bus_name(&"SFX")
	_music_bus_index = AudioServer.get_bus_index(_music_bus_name)
	_sfx_bus_index = AudioServer.get_bus_index(_sfx_bus_name)
	# 사용자가 고른 100%가 원래 믹스를 뜻해야 하므로 설정을 덮기 전에 기준값을 붙잡는다.
	_music_base_db = AudioServer.get_bus_volume_db(_music_bus_index) if _music_bus_index >= 0 else 0.0
	_sfx_base_db = AudioServer.get_bus_volume_db(_sfx_bus_index) if _sfx_bus_index >= 0 else 0.0

	_create_music_player()
	_create_sfx_pool()
	_load_sfx_library()
	load_settings()


func _resolve_bus_name(preferred_name: StringName) -> StringName:
	if AudioServer.get_bus_index(preferred_name) >= 0:
		return preferred_name

	# 테스트나 초기 설치에서 버스 파일이 빠져도 나머지 오디오 기능은 살아 있어야 한다.
	push_error("AudioManager: '%s' 버스를 찾지 못해 Master 버스를 사용합니다." % preferred_name)
	return &"Master"


func _create_music_player() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.name = &"MusicPlayer"
	_music_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_music_player.bus = _music_bus_name
	add_child(_music_player)

	var loaded_music: Resource = load(BGM_PATH)
	if loaded_music == null or not (loaded_music is AudioStream):
		push_error("AudioManager: 배경음악을 불러오지 못했습니다: %s" % BGM_PATH)
		return

	if loaded_music is AudioStreamMP3:
		var mp3_stream: AudioStreamMP3 = loaded_music as AudioStreamMP3
		# 재임포트가 반복 설정을 지울 수 있으므로 실행 시점의 스트림에 직접 보장한다.
		mp3_stream.loop = true
	else:
		push_error("AudioManager: 배경음악이 AudioStreamMP3가 아니어서 반복을 설정할 수 없습니다.")
	_music_player.stream = loaded_music as AudioStream


func _create_sfx_pool() -> void:
	for index: int in range(SFX_POOL_SIZE):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = StringName("SFXPlayer%02d" % (index + 1))
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		player.bus = _sfx_bus_name
		add_child(player)
		_sfx_players.append(player)
		_player_started_msec[player.get_instance_id()] = 0


func _load_sfx_library() -> void:
	for key: Variant in SFX_LIBRARY.keys():
		var sound_name: StringName = StringName(key)
		var definition: Dictionary = SFX_LIBRARY[sound_name]
		var path: String = String(definition.get("path", ""))
		var loaded_stream: Resource = load(path)
		if loaded_stream == null or not (loaded_stream is AudioStream):
			# 한 파일의 손상 때문에 다른 효과음까지 막히지 않도록 실패 항목만 제외한다.
			push_error("AudioManager: 효과음을 불러오지 못했습니다: %s" % path)
			continue
		_sfx_streams[sound_name] = loaded_stream as AudioStream
		_play_counts[sound_name] = 0


func play_sfx(sound_name: StringName) -> bool:
	if not SFX_LIBRARY.has(sound_name) or not _sfx_streams.has(sound_name):
		return false

	var definition: Dictionary = SFX_LIBRARY[sound_name]
	var now_msec: int = Time.get_ticks_msec()
	var min_interval: float = float(definition.get("min_interval", 0.0))
	if _last_played_msec.has(sound_name):
		var previous_msec: int = int(_last_played_msec[sound_name])
		var elapsed_msec: int = now_msec - previous_msec
		if elapsed_msec < int(ceil(min_interval * 1000.0)):
			return false

	var player: AudioStreamPlayer = _acquire_sfx_player()
	if player == null:
		return false

	var pitch_jitter: float = float(definition.get("pitch_jitter", 0.0))
	player.stop()
	player.stream = _sfx_streams[sound_name] as AudioStream
	player.volume_db = float(definition.get("volume_db", 0.0))
	player.pitch_scale = randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter) if pitch_jitter > 0.0 else 1.0
	player.play()

	_last_played_msec[sound_name] = now_msec
	_player_started_msec[player.get_instance_id()] = now_msec
	_play_counts[sound_name] = int(_play_counts.get(sound_name, 0)) + 1
	return true


func _acquire_sfx_player() -> AudioStreamPlayer:
	for player: AudioStreamPlayer in _sfx_players:
		if not player.playing:
			return player

	# 풀 포화 시 중요한 새 요청이 사라지지 않도록 가장 오래된 음성을 교체한다.
	var oldest_player: AudioStreamPlayer = _sfx_players[0]
	var oldest_started_msec: int = int(_player_started_msec.get(oldest_player.get_instance_id(), 0))
	for player: AudioStreamPlayer in _sfx_players:
		var started_msec: int = int(_player_started_msec.get(player.get_instance_id(), 0))
		if started_msec < oldest_started_msec:
			oldest_player = player
			oldest_started_msec = started_msec
	return oldest_player


func play_music() -> void:
	if _music_player == null or _music_player.stream == null or _music_player.playing:
		return
	_music_player.stream_paused = false
	_music_player.play(0.0)


func stop_music() -> void:
	if _music_player != null:
		_music_player.stop()


func set_music_paused(paused: bool) -> void:
	if _music_player != null:
		_music_player.stream_paused = paused


func is_music_playing() -> bool:
	return _music_player != null and _music_player.playing


func set_music_volume(linear: float) -> void:
	var clamped_linear: float = clampf(linear, 0.0, 1.0)
	var changed: bool = not is_equal_approx(_music_volume, clamped_linear)
	_music_volume = clamped_linear
	_apply_bus_volume(_music_bus_index, _music_base_db, _music_volume)
	if changed:
		save_settings()


func set_sfx_volume(linear: float) -> void:
	var clamped_linear: float = clampf(linear, 0.0, 1.0)
	var changed: bool = not is_equal_approx(_sfx_volume, clamped_linear)
	_sfx_volume = clamped_linear
	_apply_bus_volume(_sfx_bus_index, _sfx_base_db, _sfx_volume)
	if changed:
		save_settings()


func get_music_volume() -> float:
	return _music_volume


func get_sfx_volume() -> float:
	return _sfx_volume


func get_music_base_db() -> float:
	return _music_base_db


func get_sfx_base_db() -> float:
	return _sfx_base_db


func get_settings_path() -> String:
	return SETTINGS_PATH


func save_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	var load_error: Error = config.load(SETTINGS_PATH)
	if load_error != OK and load_error != ERR_FILE_NOT_FOUND:
		# 손상된 파일의 일부를 재사용하면 다음 실행도 읽지 못하므로 새 설정으로 교체한다.
		config = ConfigFile.new()
	config.set_value("audio", "music_volume", _music_volume)
	config.set_value("audio", "sfx_volume", _sfx_volume)
	var save_error: Error = config.save(SETTINGS_PATH)
	if save_error != OK:
		push_error("AudioManager: 음량 설정을 저장하지 못했습니다: %s" % error_string(save_error))


func load_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	var load_error: Error = config.load(SETTINGS_PATH)
	if load_error == ERR_FILE_NOT_FOUND:
		# 첫 실행에는 파일이 없는 것이 정상이며, 레이아웃의 믹스를 그대로 쓴다.
		_music_volume = 1.0
		_sfx_volume = 1.0
	elif load_error != OK:
		push_error("AudioManager: 음량 설정을 읽지 못해 기본값을 사용합니다: %s" % error_string(load_error))
		_music_volume = 1.0
		_sfx_volume = 1.0
	else:
		_music_volume = _read_volume_setting(config, "music_volume")
		_sfx_volume = _read_volume_setting(config, "sfx_volume")

	_apply_bus_volume(_music_bus_index, _music_base_db, _music_volume)
	_apply_bus_volume(_sfx_bus_index, _sfx_base_db, _sfx_volume)


func _read_volume_setting(config: ConfigFile, key: String) -> float:
	var raw_value: Variant = config.get_value("audio", key, 1.0)
	var value_type: int = typeof(raw_value)
	if value_type != TYPE_FLOAT and value_type != TYPE_INT:
		return 1.0
	var numeric_value: float = float(raw_value)
	if not is_finite(numeric_value) or numeric_value < 0.0 or numeric_value > 1.0:
		return 1.0
	return numeric_value


func _apply_bus_volume(bus_index: int, base_db: float, linear: float) -> void:
	if bus_index < 0:
		return
	var volume_db: float = SILENT_VOLUME_DB if linear <= 0.0 else base_db + linear_to_db(linear)
	AudioServer.set_bus_volume_db(bus_index, volume_db)


func set_muted(muted: bool) -> void:
	if _master_bus_index >= 0:
		AudioServer.set_bus_mute(_master_bus_index, muted)


func is_muted() -> bool:
	return _master_bus_index >= 0 and AudioServer.is_bus_mute(_master_bus_index)


func get_play_count(sound_name: StringName) -> int:
	return int(_play_counts.get(sound_name, 0))


func get_pool_size() -> int:
	return _sfx_players.size()


func get_active_player_count() -> int:
	var active_count: int = 0
	for player: AudioStreamPlayer in _sfx_players:
		if player.playing:
			active_count += 1
	return active_count


func get_sfx_names() -> Array:
	return SFX_LIBRARY.keys()


func reset_counters() -> void:
	_last_played_msec.clear()
	_play_counts.clear()
	for key: Variant in SFX_LIBRARY.keys():
		_play_counts[StringName(key)] = 0
