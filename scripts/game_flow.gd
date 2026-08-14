extends CanvasLayer

@export var player_path: NodePath
@export var hud_path: NodePath
@export var level_up_ui_path: NodePath
@export var reload_on_restart: bool = true

@onready var pause_button: Button = $PauseButton
@onready var pause_panel: Control = $PausePanel
@onready var resume_button: Button = $PausePanel/ResumeButton
@onready var pause_restart_button: Button = $PausePanel/PauseRestartButton
@onready var title_panel: Control = $TitlePanel
@onready var game_over_panel: Control = $GameOverPanel
@onready var result_label: Label = $GameOverPanel/ResultLabel
@onready var start_button: Button = $TitlePanel/StartButton
@onready var restart_button: Button = $GameOverPanel/RestartButton

var player: Node
var hud: Node
var level_up_ui: Node
var auto_play_enabled: bool = false


func _ready() -> void:
	player = get_node_or_null(player_path)
	if player == null:
		push_error("GameFlow: player_path could not be resolved: %s" % player_path)
	else:
		player.connect(&"died", Callable(self, "_on_player_died"))

	hud = get_node_or_null(hud_path)
	if hud == null:
		push_error("GameFlow: hud_path could not be resolved: %s" % hud_path)

	level_up_ui = get_node_or_null(level_up_ui_path)
	if level_up_ui == null:
		push_error("GameFlow: level_up_ui_path could not be resolved: %s" % level_up_ui_path)

	start_button.pressed.connect(start_game)
	restart_button.pressed.connect(restart)
	resume_button.pressed.connect(close_pause_menu)
	pause_restart_button.pressed.connect(restart)
	pause_button.pressed.connect(toggle_pause)

	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	if user_args.has("--auto-play"):
		enable_auto_play()
	else:
		title_panel.show()
		get_tree().paused = true
		print("FLOW_TITLE_SHOWN")


func _process(_delta: float) -> void:
	pause_button.visible = can_pause() or is_pause_menu_visible()
	if not auto_play_enabled or level_up_ui == null:
		return
	var level_up_visible: bool = bool(level_up_ui.get("visible"))
	if level_up_visible:
		var choices: Variant = level_up_ui.call("get_choice_ids")
		if choices is Array and not choices.is_empty():
			level_up_ui.call("choose", 0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		toggle_pause()
		get_viewport().set_input_as_handled()


func enable_auto_play() -> void:
	auto_play_enabled = true
	title_panel.hide()
	get_tree().paused = false
	print("FLOW_STARTED auto=true")


func start_game() -> void:
	title_panel.hide()
	get_tree().paused = false
	print("FLOW_STARTED auto=%s" % str(auto_play_enabled).to_lower())


func restart() -> void:
	pause_panel.hide()
	# SceneTree.paused survives reloads, so clear it before replacing the scene.
	get_tree().paused = false
	print("FLOW_RESTART")
	if reload_on_restart:
		get_tree().reload_current_scene()


func is_title_visible() -> bool:
	return title_panel.visible


func is_game_over_visible() -> bool:
	return game_over_panel.visible


## 일시정지를 걸 수 있는 상황인가.
##
## 타이틀·게임오버·레벨업은 각자의 이유로 이미 일시정지를 걸고 있다.
## 그 위에서 일시정지 버튼이 또 눌리면 해제 권한이 흐려지므로 허용하지 않는다.
func can_pause() -> bool:
	if title_panel.visible or game_over_panel.visible:
		return false
	if level_up_ui != null:
		var level_up_visible: bool = bool(level_up_ui.get("visible"))
		if level_up_visible:
			return false
	return true


func toggle_pause() -> void:
	if is_pause_menu_visible():
		close_pause_menu()
	else:
		open_pause_menu()


func open_pause_menu() -> void:
	if not can_pause():
		return
	pause_panel.show()
	get_tree().paused = true
	print("FLOW_PAUSED")


func close_pause_menu() -> void:
	if not pause_panel.visible:
		return
	pause_panel.hide()
	get_tree().paused = false
	print("FLOW_RESUMED")


func is_pause_menu_visible() -> bool:
	return pause_panel.visible


func _on_player_died() -> void:
	pause_panel.hide()
	var elapsed: float = 0.0
	var kills: int = 0
	var level: int = 0
	var formatted_time: String = "00:00"
	if hud != null:
		elapsed = float(hud.call("get_elapsed_time"))
		kills = int(hud.call("get_kill_count"))
		formatted_time = str(hud.call("format_elapsed_time", elapsed))
		var displayed_values: Variant = hud.call("get_displayed_values")
		if displayed_values is Dictionary:
			var level_value: Variant = displayed_values.get("level", 0)
			level = int(level_value)
	else:
		push_error("GameFlow: cannot build game-over summary because hud_path is unresolved")

	result_label.text = "생존 시간: %s\n처치 수: %d\n도달 레벨: %d" % [formatted_time, kills, level]
	game_over_panel.show()
	get_tree().paused = true
	print("FLOW_GAME_OVER time=%s kills=%d level=%d" % [formatted_time, kills, level])
