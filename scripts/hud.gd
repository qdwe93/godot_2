extends CanvasLayer

@export var player_path: NodePath
@export var level_system_path: NodePath
@export var enemy_container_path: NodePath

@onready var health_bar: ProgressBar = $HealthBar
@onready var health_label: Label = $HealthLabel
@onready var experience_bar: ProgressBar = $ExperienceBar
@onready var danger_vignette: ColorRect = $DangerVignette
@onready var level_label: Label = $LevelLabel
@onready var time_label: Label = $TimeLabel
@onready var kill_label: Label = $KillLabel

var _health: float = 0.0
var _max_health: float = 0.0
var _experience: float = 0.0
var _experience_required: float = 0.0
var _level: int = 0
var _kills: int = 0
var _elapsed_time: float = 0.0
var _timer_stopped: bool = false
var _danger_state: bool = false
var _danger_alpha: float = 0.0
var _normal_health_fill_style: StyleBox
var _danger_health_fill_style: StyleBoxFlat = StyleBoxFlat.new()

const DANGER_HEALTH_RATIO: float = 0.3
# 0.22였을 때 실기 스크린샷에서 화면이 통째로 붉게 물들어 적과 젬이 묻혔다.
# 위험 표시의 주역은 이제 주인공의 빨간 깜빡임(player.gd)이고, 비네트는 가장자리에
# 얇게 깔리는 보조 역할만 한다.
const MAX_DANGER_ALPHA: float = 0.09
const DANGER_COLOUR: Color = Color(0.95, 0.25, 0.25, 1.0)


func _ready() -> void:
	_normal_health_fill_style = health_bar.get_theme_stylebox(&"fill")
	_danger_health_fill_style.bg_color = DANGER_COLOUR
	_update_health_display()
	_update_experience_display()
	_update_time_display()
	_update_kill_display()
	_resolve_player()
	_resolve_level_system()
	_resolve_enemy_container()


func _process(delta: float) -> void:
	if not _timer_stopped:
		_elapsed_time += delta
		_update_time_display()


func _resolve_player() -> void:
	var player: Node = get_node_or_null(player_path)
	if player == null:
		push_error("HUD player_path failed to resolve: %s" % player_path)
		return
	if player.has_signal("health_changed"):
		player.connect("health_changed", _on_health_changed)
	else:
		push_error("HUD player at player_path has no health_changed signal: %s" % player_path)
	if player.has_signal("died"):
		player.connect("died", _on_player_died)
	else:
		push_error("HUD player at player_path has no died signal: %s" % player_path)
	var current_health: Variant = player.get("health")
	var maximum_health: Variant = player.get("max_health")
	if current_health == null or maximum_health == null:
		push_error("HUD player at player_path is missing health or max_health: %s" % player_path)
		return
	_on_health_changed(float(current_health), float(maximum_health))


func _resolve_level_system() -> void:
	var level_system: Node = get_node_or_null(level_system_path)
	if level_system == null:
		push_error("HUD level_system_path failed to resolve: %s" % level_system_path)
		return
	if level_system.has_signal("experience_changed"):
		level_system.connect("experience_changed", _on_experience_changed)
	else:
		push_error("HUD level system at level_system_path has no experience_changed signal: %s" % level_system_path)
	var current_experience: Variant = level_system.get("experience")
	var current_level: Variant = level_system.get("level")
	if current_experience == null or current_level == null:
		push_error("HUD level system is missing experience or level: %s" % level_system_path)
		return
	if not level_system.has_method("required_for_next_level"):
		push_error("HUD level system is missing required_for_next_level: %s" % level_system_path)
		return
	var required_experience: Variant = level_system.call("required_for_next_level")
	if required_experience == null:
		push_error("HUD level system returned no required experience: %s" % level_system_path)
		return
	_on_experience_changed(float(current_experience), float(required_experience), int(current_level))


func _resolve_enemy_container() -> void:
	var enemy_container: Node = get_node_or_null(enemy_container_path)
	if enemy_container == null:
		push_error("HUD enemy_container_path failed to resolve: %s" % enemy_container_path)
		return
	enemy_container.connect("child_entered_tree", _on_enemy_entered_container)
	for child: Node in enemy_container.get_children():
		_connect_enemy_death(child)


func _on_health_changed(current: float, maximum: float) -> void:
	_health = current
	_max_health = maximum
	_update_health_display()


func _on_experience_changed(current: float, required: float, level: int) -> void:
	_experience = current
	_experience_required = required
	_level = level
	_update_experience_display()


func _on_player_died() -> void:
	_timer_stopped = true


func _on_enemy_entered_container(enemy: Node) -> void:
	_connect_enemy_death(enemy)


func _connect_enemy_death(enemy: Node) -> void:
	if enemy.has_signal("died") and not enemy.is_connected("died", _on_enemy_died):
		enemy.connect("died", _on_enemy_died)


func _on_enemy_died(_enemy_position: Vector2) -> void:
	_kills += 1
	_update_kill_display()


func _update_health_display() -> void:
	health_bar.max_value = maxf(_max_health, 1.0)
	health_bar.value = clampf(_health, 0.0, health_bar.max_value)
	health_label.text = "%d/%d" % [roundi(_health), roundi(_max_health)]
	_update_danger_display()


func _update_danger_display() -> void:
	var health_ratio: float = 1.0
	if _max_health > 0.0:
		health_ratio = clampf(_health / _max_health, 0.0, 1.0)
	_danger_state = _max_health > 0.0 and health_ratio <= DANGER_HEALTH_RATIO
	if _danger_state:
		_danger_alpha = clampf((DANGER_HEALTH_RATIO - health_ratio) / DANGER_HEALTH_RATIO, 0.0, 1.0) * MAX_DANGER_ALPHA
		health_bar.add_theme_stylebox_override(&"fill", _danger_health_fill_style)
		health_label.add_theme_color_override(&"font_color", DANGER_COLOUR)
	else:
		_danger_alpha = 0.0
		if _normal_health_fill_style != null:
			health_bar.add_theme_stylebox_override(&"fill", _normal_health_fill_style)
		health_label.remove_theme_color_override(&"font_color")
	var vignette_modulate: Color = danger_vignette.modulate
	vignette_modulate.a = _danger_alpha
	danger_vignette.modulate = vignette_modulate


func _update_experience_display() -> void:
	experience_bar.max_value = maxf(_experience_required, 1.0)
	experience_bar.value = clampf(_experience, 0.0, experience_bar.max_value)
	level_label.text = "Lv.%d" % _level


func _update_time_display() -> void:
	time_label.text = format_elapsed_time(_elapsed_time)


func _update_kill_display() -> void:
	kill_label.text = "처치 %d" % _kills


func format_elapsed_time(seconds: float) -> String:
	var total_seconds: int = maxi(0, int(floor(seconds)))
	var minutes: int = int(total_seconds / 60)
	var remaining_seconds: int = total_seconds % 60
	return "%d:%02d" % [minutes, remaining_seconds]


func get_kill_count() -> int:
	return _kills


func get_elapsed_time() -> float:
	return _elapsed_time


func is_danger_state() -> bool:
	return _danger_state


func get_danger_alpha() -> float:
	return _danger_alpha


func get_displayed_values() -> Dictionary:
	return {
		"health": _health,
		"max_health": _max_health,
		"experience": _experience,
		"experience_required": _experience_required,
		"level": _level,
		"kills": _kills,
		"elapsed": _elapsed_time,
	}
