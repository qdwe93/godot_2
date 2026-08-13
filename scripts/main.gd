extends Node2D


var _enemy_spawner: Node = null
var _survival_time := 0.0
var _player_dead := false
## 직전 체력. 피해와 회복을 구분하기 위해 필요하다 (INF로 시작해 첫 보고를 회복으로 오인하지 않는다).
var _last_known_health: float = INF


func _ready() -> void:
	var player := get_node_or_null("Player")
	_enemy_spawner = get_node_or_null("EnemySpawner")

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

		var level_system := player.get_node_or_null("LevelSystem")
		if level_system == null:
			push_error("Main: required Player/LevelSystem node is missing; experience signals cannot be connected.")
		else:
			if not level_system.has_signal(&"experience_changed"):
				push_error("Main: Player/LevelSystem is missing the required 'experience_changed' signal.")
			else:
				level_system.connect(&"experience_changed", _on_experience_changed)
			if not level_system.has_signal(&"leveled_up"):
				push_error("Main: Player/LevelSystem is missing the required 'leveled_up' signal.")
			else:
				level_system.connect(&"leveled_up", _on_leveled_up)

	if _enemy_spawner == null:
		push_error("Main: required EnemySpawner node is missing; spawning cannot be stopped on death.")
	elif not _enemy_spawner.has_method("stop"):
		push_error("Main: EnemySpawner is missing the required stop() method.")

	var actions_ok := true
	for action_name: StringName in [&"move_left", &"move_right", &"move_up", &"move_down"]:
		if not InputMap.has_action(action_name) or InputMap.action_get_events(action_name).is_empty():
			actions_ok = false

	var version_string = str(Engine.get_version_info().get("string", "unknown"))
	print("BOOT_OK milestone=M9 actions_ok=%s version=%s" % [actions_ok, version_string])


func _process(delta: float) -> void:
	if not _player_dead:
		_survival_time += delta


func _on_player_health_changed(current: float, maximum: float) -> void:
	print("PLAYER_HEALTH current=%.3f maximum=%.3f" % [current, maximum])

	# **줄었을 때만** 흔든다.
	#
	# M12b에서 체력 재생을 넣으면서 이 시그널이 회복 중에도 매 프레임 발생하게 됐다.
	# 그런데 여기서는 그걸 구분하지 않고 무조건 흔들었다. 결과적으로 재생이 도는
	# 내내 화면이 떨렸다 — 실기 테스트에서 "조금만 깎여도 어지럽다"고 나온 원인이
	# 피해가 아니라 **회복**이었다.
	var took_damage: bool = current < _last_known_health
	_last_known_health = current
	if not took_damage:
		return

	# 그룹으로 찾으므로 흔들기 노드가 없어도 조용히 넘어간다.
	var shaker: Node = get_tree().get_first_node_in_group(&"screen_shake")
	if shaker != null and shaker.has_method("shake"):
		shaker.call("shake")


func _on_player_died() -> void:
	if _player_dead:
		return

	_player_dead = true
	print("PLAYER_DIED survival_time=%.3f" % _survival_time)
	if _enemy_spawner != null and _enemy_spawner.has_method("stop"):
		_enemy_spawner.call("stop")


func _on_experience_changed(current: float, required: float, level: int) -> void:
	print("XP_GAINED current=%.3f required=%.3f level=%d" % [current, required, level])


func _on_leveled_up(level: int) -> void:
	print("LEVEL_UP level=%d" % level)
