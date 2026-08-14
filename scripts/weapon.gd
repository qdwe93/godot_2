extends Node2D


@export var cooldown: float = 0.5
@export var projectile_scene: PackedScene
@export var projectile_damage: float = 5.0
@export var attack_range: float = 350.0

var _cooldown_timer: Timer = null
var _reported_missing_container := false


func _ready() -> void:
	if projectile_scene == null:
		push_error("Weapon: projectile_scene is not assigned.")
	if cooldown <= 0.0:
		push_error("Weapon: cooldown must be greater than zero.")
		return

	_cooldown_timer = Timer.new()
	_cooldown_timer.name = "CooldownTimer"
	_cooldown_timer.wait_time = cooldown
	_cooldown_timer.one_shot = true
	_cooldown_timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
	_cooldown_timer.timeout.connect(_on_cooldown_timer_timeout)
	add_child(_cooldown_timer)
	_cooldown_timer.start()


func _physics_process(_delta: float) -> void:
	if _cooldown_timer != null and _cooldown_timer.is_stopped():
		try_fire()


func try_fire() -> Node:
	var target := find_nearest_enemy()
	if target == null:
		return null
	if projectile_scene == null:
		push_error("Weapon: cannot fire because projectile_scene is not assigned.")
		return null

	var projectile := projectile_scene.instantiate()
	if projectile == null:
		push_error("Weapon: projectile_scene failed to instantiate.")
		return null
	if not projectile is Node2D or not projectile.has_method("launch"):
		push_error("Weapon: projectile_scene root must inherit Node2D and implement launch().")
		projectile.free()
		return null

	var container := _find_projectile_container()
	if container == null:
		projectile.free()
		return null

	projectile.set("damage", projectile_damage)
	container.add_child(projectile)
	var travel_direction := (target.global_position - global_position).normalized()
	projectile.call("launch", global_position, travel_direction)
	Audio.play_sfx(&"shoot")
	if _cooldown_timer != null:
		_cooldown_timer.start()
	return projectile


func find_nearest_enemy() -> Node2D:
	var nearest_enemy: Node2D = null
	var nearest_distance_squared := INF
	var attack_range_squared := attack_range * attack_range

	for candidate: Node in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(candidate):
			continue
		if candidate.is_queued_for_deletion() or not candidate is Node2D:
			continue
		var enemy := candidate as Node2D
		var distance_squared := global_position.distance_squared_to(enemy.global_position)
		if distance_squared <= attack_range_squared and distance_squared < nearest_distance_squared:
			nearest_distance_squared = distance_squared
			nearest_enemy = enemy

	return nearest_enemy


func _find_projectile_container() -> Node:
	var containers := get_tree().get_nodes_in_group("projectile_container")
	for candidate: Node in containers:
		if is_instance_valid(candidate) and not candidate.is_queued_for_deletion():
			return candidate

	if not _reported_missing_container:
		push_error(
			"Weapon: no node found in group 'projectile_container'; "
			+ "falling back to the current scene."
		)
		_reported_missing_container = true

	var current_scene := get_tree().current_scene
	if current_scene == null:
		push_error("Weapon: current_scene is null, so the projectile cannot be added.")
	return current_scene


func _on_cooldown_timer_timeout() -> void:
	try_fire()
