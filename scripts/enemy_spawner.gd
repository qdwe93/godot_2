extends Node


@export var enemy_scene: PackedScene
@export var spawn_interval: float = 1.5
@export var max_enemies: int = 30
@export var spawn_margin: float = 60.0
@export var enemy_container_path: NodePath
@export var target_path: NodePath

var _enemy_container: Node2D = null
var _target: Node2D = null
var _spawn_timer: Timer = null
var _spawning_enabled := false


func _ready() -> void:
	var container_node := get_node_or_null(enemy_container_path)
	var target_node := get_node_or_null(target_path)
	var configuration_valid := true

	if container_node == null:
		push_error("EnemySpawner: enemy_container_path does not resolve to a node.")
		configuration_valid = false
	elif not container_node is Node2D:
		push_error("EnemySpawner: enemy_container_path must resolve to a Node2D.")
		configuration_valid = false

	if target_node == null:
		push_error("EnemySpawner: target_path does not resolve to a node.")
		configuration_valid = false
	elif not target_node is Node2D:
		push_error("EnemySpawner: target_path must resolve to a Node2D.")
		configuration_valid = false

	if enemy_scene == null:
		push_error("EnemySpawner: enemy_scene is not assigned.")
		configuration_valid = false

	if spawn_interval <= 0.0:
		push_error("EnemySpawner: spawn_interval must be greater than zero.")
		configuration_valid = false

	if not configuration_valid:
		return

	_enemy_container = container_node as Node2D
	_target = target_node as Node2D
	_spawning_enabled = true

	_spawn_timer = Timer.new()
	_spawn_timer.name = "SpawnTimer"
	_spawn_timer.wait_time = spawn_interval
	_spawn_timer.one_shot = false
	_spawn_timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
	_spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	add_child(_spawn_timer)
	_spawn_timer.start()


func spawn_one() -> Node:
	if not _spawning_enabled:
		return null
	if _enemy_container.get_child_count() >= max_enemies:
		return null

	var enemy := enemy_scene.instantiate() as Node2D
	if enemy == null:
		push_error("EnemySpawner: enemy_scene root must inherit Node2D.")
		return null

	var design_screen_size := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width")),
		float(ProjectSettings.get_setting("display/window/size/viewport_height"))
	)
	var screen_center := design_screen_size / 2.0
	var spawn_radius := design_screen_size.length() / 2.0 + spawn_margin
	var angle := randf() * TAU
	var spawn_offset := Vector2(cos(angle), sin(angle)) * spawn_radius

	enemy.set("target", _target)
	_enemy_container.add_child(enemy)
	enemy.global_position = screen_center + spawn_offset
	enemy.add_to_group("enemies")
	return enemy


func stop() -> void:
	_spawning_enabled = false
	if is_instance_valid(_spawn_timer):
		_spawn_timer.stop()


func _on_spawn_timer_timeout() -> void:
	spawn_one()
