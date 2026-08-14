extends Control

const STEP: float = 0.1

@onready var _music_minus_button: Button = $Rows/MusicRow/MinusButton
@onready var _music_plus_button: Button = $Rows/MusicRow/PlusButton
@onready var _music_bar: ProgressBar = $Rows/MusicRow/Bar
@onready var _music_value_label: Label = $Rows/MusicRow/ValueLabel
@onready var _sfx_minus_button: Button = $Rows/SfxRow/MinusButton
@onready var _sfx_plus_button: Button = $Rows/SfxRow/PlusButton
@onready var _sfx_bar: ProgressBar = $Rows/SfxRow/Bar
@onready var _sfx_value_label: Label = $Rows/SfxRow/ValueLabel

var _audio: AudioManager


func _ready() -> void:
	var audio_node: Node = get_node_or_null("/root/Audio")
	if audio_node == null or not (audio_node is AudioManager):
		# 독립 미리보기에서도 씬 구조를 확인할 수 있어야 하므로 오류만 알리고 멈춘다.
		push_error("VolumeSettings: Audio autoload를 찾지 못했습니다.")
		return
	_audio = audio_node as AudioManager

	_music_minus_button.pressed.connect(_change_music.bind(-STEP))
	_music_plus_button.pressed.connect(_change_music.bind(STEP))
	_sfx_minus_button.pressed.connect(_change_sfx.bind(-STEP))
	_sfx_plus_button.pressed.connect(_change_sfx.bind(STEP))
	refresh()


func refresh() -> void:
	if _audio == null:
		return
	var music_percent: int = roundi(_audio.get_music_volume() * 100.0)
	var sfx_percent: int = roundi(_audio.get_sfx_volume() * 100.0)
	_music_bar.value = music_percent
	_sfx_bar.value = sfx_percent
	_music_value_label.text = "%d%%" % music_percent
	_sfx_value_label.text = "%d%%" % sfx_percent


func _change_music(delta: float) -> void:
	if _audio == null:
		return
	_audio.set_music_volume(clampf(_audio.get_music_volume() + delta, 0.0, 1.0))
	refresh()


func _change_sfx(delta: float) -> void:
	if _audio == null:
		return
	_audio.set_sfx_volume(clampf(_audio.get_sfx_volume() + delta, 0.0, 1.0))
	refresh()
	# 바뀐 효과음 크기를 화면을 닫지 않고 귀로 확인할 수 있게 대표음을 한 번 낸다.
	_audio.play_sfx(&"hit")


func get_displayed_music_percent() -> int:
	return roundi(_music_bar.value)


func get_displayed_sfx_percent() -> int:
	return roundi(_sfx_bar.value)
