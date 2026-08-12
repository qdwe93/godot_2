extends Node2D


var _enemy_spawner: Node = null
var _game_over_label: Label = null
var _survival_time := 0.0
var _player_dead := false


func _ready() -> void:
	var player := get_node_or_null("Player")
	_enemy_spawner = get_node_or_null("EnemySpawner")
	var game_over_node := get_node_or_null("GameOverLabel")

	if player == null:
		push_error("Main: required Player node is missing; death signals cannot be connected.")
	else:
		if not player.has_signal(&"health_changed"):
			push_error("Main: Player is missing the required 'health_changed' signal.")
		else:
			player.connect(&"health_changed", _on_player_health_changed)
		if not player.has_signal(&"died"):
			push_error("Main: Player is missing the required 'died' signal.")
		else:
			player.connect(&"died", _on_player_died)

	if _enemy_spawner == null:
		push_error("Main: required EnemySpawner node is missing; spawning cannot be stopped on death.")
	elif not _enemy_spawner.has_method("stop"):
		push_error("Main: EnemySpawner is missing the required stop() method.")

	if game_over_node == null:
		push_error("Main: required Label node 'GameOverLabel' is missing.")
	elif not game_over_node is Label:
		push_error("Main: node 'GameOverLabel' must be a Label.")
	else:
		_game_over_label = game_over_node as Label

	var actions_ok := true
	for action_name: StringName in [&"move_left", &"move_right", &"move_up", &"move_down"]:
		if not InputMap.has_action(action_name) or InputMap.action_get_events(action_name).is_empty():
			actions_ok = false

	var version_string := str(Engine.get_version_info().get("string", "unknown"))
	print("BOOT_OK milestone=M4 actions_ok=%s version=%s" % [actions_ok, version_string])


func _process(delta: float) -> void:
	if not _player_dead:
		_survival_time += delta


func _on_player_health_changed(current: float, maximum: float) -> void:
	print("PLAYER_HEALTH current=%.3f maximum=%.3f" % [current, maximum])


func _on_player_died() -> void:
	if _player_dead:
		return

	_player_dead = true
	print("PLAYER_DIED survival_time=%.3f" % _survival_time)
	if _enemy_spawner != null and _enemy_spawner.has_method("stop"):
		_enemy_spawner.call("stop")
	if _game_over_label != null:
		_game_over_label.show()
