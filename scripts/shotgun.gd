class_name Shotgun
extends Node2D

@export var cooldown: float = 1.0
@export var projectile_scene: PackedScene
@export var projectile_damage: float = 3.0
@export var attack_range: float = 250.0
@export var pellet_count: int = 3
@export var spread_degrees: float = 30.0

var is_unlocked: bool = false

var _cooldown_timer: Timer
var _reported_missing_projectile_container: bool = false


func _ready() -> void:

	_ensure_cooldown_timer()


func unlock() -> void:

	if is_unlocked:
		return
	is_unlocked = true
	_ensure_cooldown_timer()
	_cooldown_timer.start()


func try_fire() -> Array[Node]:

	var projectiles: Array[Node] = []
	if not is_unlocked or projectile_scene == null or pellet_count <= 0:
		return projectiles

	var target: Node2D = _find_nearest_target()
	if target == null:
		return projectiles

	var projectile_parent: Node = get_tree().get_first_node_in_group(&"projectile_container")
	if projectile_parent == null:
		projectile_parent = get_tree().current_scene
		if not _reported_missing_projectile_container:
			push_error("Shotgun: no node in the projectile_container group; using the current scene.")
			_reported_missing_projectile_container = true
	if projectile_parent == null:
		return projectiles

	var aim_direction: Vector2 = global_position.direction_to(target.global_position)
	if aim_direction == Vector2.ZERO:
		return projectiles
	var centre_angle: float = aim_direction.angle()
	var total_spread: float = deg_to_rad(spread_degrees)

	for pellet_index: int in range(pellet_count):
		var spread_offset: float = 0.0
		if pellet_count > 1:
			spread_offset = -total_spread * 0.5 + total_spread * float(pellet_index) / float(pellet_count - 1)
		var pellet_direction: Vector2 = Vector2.RIGHT.rotated(centre_angle + spread_offset)
		var projectile: Node = projectile_scene.instantiate()
		projectile_parent.add_child(projectile)
		projectile.set(&"damage", projectile_damage)
		projectile.set_meta(&"shotgun_direction", pellet_direction)
		projectile.call(&"launch", global_position, pellet_direction)
		projectiles.append(projectile)

	return projectiles


func _ensure_cooldown_timer() -> void:

	if _cooldown_timer != null:
		_cooldown_timer.wait_time = cooldown
		return
	_cooldown_timer = Timer.new()
	_cooldown_timer.name = &"CooldownTimer"
	_cooldown_timer.wait_time = cooldown
	_cooldown_timer.one_shot = false
	_cooldown_timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
	add_child(_cooldown_timer)
	_cooldown_timer.timeout.connect(_on_cooldown_timer_timeout)


func _on_cooldown_timer_timeout() -> void:

	if is_unlocked:
		try_fire()


func _find_nearest_target() -> Node2D:

	var nearest_target: Node2D
	var nearest_distance: float = attack_range
	for enemy: Node in get_tree().get_nodes_in_group(&"enemies"):
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		var enemy_node: Node2D = enemy as Node2D
		if enemy_node == null:
			continue
		var distance: float = global_position.distance_to(enemy_node.global_position)
		if distance <= nearest_distance:
			nearest_target = enemy_node
			nearest_distance = distance
	return nearest_target
